using System.Net;
using System.Reflection;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Controllers;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AppOriginCheckTests
{
    private const string App = "https://app.example.test";
    private const string Chrome = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36";

    private static bool Allows(string? origin, string? referer, string? userAgent, bool native = true) =>
        AppOriginCheck.Allows(origin, referer, userAgent, "api.example.test", native, candidate => candidate == App);

    [Fact]
    public void AppPagesAreAllowed()
    {
        Assert.True(Allows(App, null, Chrome));
        // Some browsers send only the page address; its site is what counts.
        Assert.True(Allows(null, App + "/signup?step=2", Chrome));
        // A page served by the API host itself.
        Assert.True(Allows("https://api.example.test", null, Chrome));
    }

    [Theory]
    [InlineData(null, null, "curl/7.88.1")]
    [InlineData(null, null, Chrome)]
    [InlineData(null, null, "HoppaMobile/1.0")]
    [InlineData(null, null, null)]
    [InlineData("https://evil.example.test", null, Chrome)]
    [InlineData("null", null, Chrome)]
    [InlineData("https://app.example.test.evil.test", null, Chrome)]
    [InlineData(null, "https://evil.example.test/?next=https://app.example.test", Chrome)]
    public void ScriptsAndOtherSitesAreRefused(string? origin, string? referer, string? userAgent)
    {
        Assert.False(Allows(origin, referer, userAgent));
    }

    [Fact]
    public void NativeBuildsPassOnlyWhileTheInstallationAllowsThem()
    {
        Assert.True(Allows(null, null, "Dart/3.12 (dart:io)"));
        Assert.False(Allows(null, null, "Dart/3.12 (dart:io)", native: false));
        // Naming another site still loses, whatever the client says it is.
        Assert.False(Allows("https://evil.example.test", null, "Dart/3.12 (dart:io)"));
    }

    [Theory]
    [InlineData(false, null, null)]
    [InlineData(true, App, null)]
    [InlineData(true, null, 403)]
    [InlineData(true, "https://evil.example.test", 403)]
    public void Filter_OnlyActsWhenTheInstallationRequiresIt(bool required, string? origin, int? expectedStatus)
    {
        var services = new ServiceCollection()
            .AddLogging()
            .AddSingleton<IConfiguration>(new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["AppOrigin:RequireOnAuth"] = required ? "true" : "false"
            }).Build())
            .AddCors(options => options.AddPolicy(RequireAppOriginAttribute.CorsPolicyName,
                policy => policy.SetIsOriginAllowed(candidate => candidate == App)))
            .BuildServiceProvider();
        var http = new DefaultHttpContext { RequestServices = services };
        http.Request.Host = new HostString("api.example.test");
        http.Request.Headers.UserAgent = "curl/7.88.1";
        if (origin is not null) http.Request.Headers.Origin = origin;
        var context = new ResourceExecutingContext(
            new ActionContext(http, new RouteData(), new ActionDescriptor()), [], []);

        new RequireAppOriginAttribute().OnResourceExecuting(context);

        Assert.Equal(expectedStatus, (context.Result as ObjectResult)?.StatusCode);
    }

    [Fact]
    public void EverySignInAndSignUpRouteCarriesTheCheck()
    {
        string[] guarded =
        [
            "login", "login/2fa", "auth/signup", "signup/email-code",
            "account-claim/challenges", "account-claim/complete"
        ];
        var actions = typeof(AuthController).GetMethods()
            .Where(method => method.GetCustomAttributes<HttpPostAttribute>().Any(route =>
                guarded.Any(suffix => route.Template == suffix || route.Template?.EndsWith("/" + suffix) == true)))
            .ToList();

        // Editions differ (the email-code step is newer), but these two always exist.
        Assert.Contains(actions, method => method.Name == nameof(AuthController.Login));
        Assert.Contains(actions, method => method.Name == nameof(AuthController.Signup));
        Assert.All(actions, method => Assert.NotNull(method.GetCustomAttribute<RequireAppOriginAttribute>()));
    }

    /// <summary>The whole way through a running server: routing, CORS policy lookup, the filter, the action.</summary>
    [Fact]
    public async Task RunningServer_TurnsScriptsAwayAndLetsTheAppThrough()
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Configuration.AddInMemoryCollection(new Dictionary<string, string?> { ["AppOrigin:RequireOnAuth"] = "true" });
        builder.Services.AddCors(options => options.AddPolicy(RequireAppOriginAttribute.CorsPolicyName,
            policy => policy.SetIsOriginAllowed(candidate => candidate == App)));
        builder.Services.AddControllers().AddApplicationPart(typeof(OriginProbeController).Assembly);
        await using var app = builder.Build();
        app.UseCors(RequireAppOriginAttribute.CorsPolicyName);
        app.MapControllers();
        await app.StartAsync();
        var address = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single();
        using var client = new HttpClient { BaseAddress = new Uri(address) };

        async Task<HttpStatusCode> Post(string? origin, string userAgent)
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, "/origin-probe");
            request.Headers.TryAddWithoutValidation("User-Agent", userAgent);
            if (origin is not null) request.Headers.TryAddWithoutValidation("Origin", origin);
            using var response = await client.SendAsync(request);
            return response.StatusCode;
        }

        Assert.Equal(HttpStatusCode.Forbidden, await Post(null, "curl/7.88.1"));
        Assert.Equal(HttpStatusCode.Forbidden, await Post(null, Chrome));
        Assert.Equal(HttpStatusCode.Forbidden, await Post("https://evil.example.test", Chrome));
        Assert.Equal(HttpStatusCode.OK, await Post(App, Chrome));
        Assert.Equal(HttpStatusCode.OK, await Post(null, "Dart/3.12 (dart:io)"));
    }
}

[ApiController]
[Route("origin-probe")]
public sealed class OriginProbeController : ControllerBase
{
    [RequireAppOrigin]
    [HttpPost]
    public IActionResult Post() => Ok();
}
