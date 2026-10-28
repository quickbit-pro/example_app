using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobileOnboardingRoutingTests
{
    internal static readonly Guid Company = Guid.NewGuid();
    internal static readonly Guid User = Guid.NewGuid();

    [Fact]
    public async Task ExistingStatusAndNewRequirementsRouteIndependently_AndInviteIsReachable()
    {
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        var options = new DbContextOptionsBuilder<NeoBankingDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options;
        builder.Services.AddScoped(_ => new NeoBankingDbContext(options));
        builder.Services.AddSingleton<IProxyHoppaRequestUseCase, OnboardingProxy>();
        builder.Services.AddSingleton<IOptions<CompanyOptions>>(
            Options.Create(new CompanyOptions { Features = new() { EqualsMoneyEnabled = true } }));
        // Register the entire API assembly: testing each controller alone misses route collisions.
        builder.Services.AddControllers().AddApplicationPart(typeof(MobileOnboardingController).Assembly);
        builder.Services.AddAuthentication("onboarding-test")
            .AddScheme<AuthenticationSchemeOptions, OnboardingTestAuth>("onboarding-test", _ => { });
        builder.Services.AddAuthorization(o => o.AddPolicy(AuthorizationPolicyNames.User, p => p.RequireAuthenticatedUser()));
        await using var app = builder.Build();
        app.UseAuthentication();
        app.UseAuthorization();
        app.MapControllers();
        await using (var db = new NeoBankingDbContext(options))
        {
            db.Users.Add(new ApplicationUser { Id = User, CompanyInstallationId = Company });
            await db.SaveChangesAsync();
        }
        await app.StartAsync();
        try
        {
            using var client = new HttpClient {
                BaseAddress = new Uri(app.Services.GetRequiredService<IServer>()
                    .Features.Get<IServerAddressesFeature>()!.Addresses.Single())
            };
            const string root = "/api/v1/mobile/onboarding/";
            foreach (var path in new[] { "status", "requirements", "invite", "fees" })
                Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync(root + path)).StatusCode);

            client.DefaultRequestHeaders.Add("X-Onboarding-Test", "customer");
            var status = await client.GetFromJsonAsync<JsonElement>(root + "status");
            Assert.Equal("start", status.GetProperty("currentStep").GetString());
            Assert.True(status.TryGetProperty("requiredActions", out _));
            Assert.False(status.TryGetProperty("nextAction", out _));

            var requirements = await client.GetFromJsonAsync<JsonElement>(root + "requirements");
            Assert.Equal("START_KYC2", requirements.GetProperty("nextAction").GetString());
            var fees = await client.GetAsync(root + "fees");
            Assert.Equal(HttpStatusCode.OK, fees.StatusCode);
            Assert.True(fees.Headers.CacheControl?.NoStore);
            Assert.True((await fees.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("success").GetBoolean());
            var invite = await client.GetFromJsonAsync<JsonElement>(root + "invite");
            Assert.True(invite.GetProperty("inviteRequired").GetBoolean());
            Assert.Equal(JsonValueKind.Null, invite.GetProperty("inviteStatus").ValueKind);
        }
        finally { await app.StopAsync(); }
    }

    private sealed class OnboardingProxy : IProxyHoppaRequestUseCase
    {
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command, CancellationToken ct)
        {
            var json = command.UpstreamPath switch {
                "/api/v2/mobile-onboarding/fees" => "{\"success\":true,\"data\":{\"tierLabel\":\"Smart\",\"sections\":[]}}",
                "/api/v2/mobile-onboarding/status" => "{\"nextAction\":\"START_KYC2\"}",
                "/api/v2/mobile-onboarding/invite" => "{\"inviteRequired\":true,\"inviteStatus\":null}",
                _ => "{}"
            };
            return Task.FromResult(ApplicationResult<JsonElement?>.Success(JsonSerializer.Deserialize<JsonElement>(json)));
        }
    }
}

public sealed class OnboardingTestAuth(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync() => Task.FromResult(
        Request.Headers["X-Onboarding-Test"] != "customer" ? AuthenticateResult.NoResult() :
        AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity([
            new Claim("company_installation_id", MobileOnboardingRoutingTests.Company.ToString()),
            new Claim("local_user_id", MobileOnboardingRoutingTests.User.ToString()),
            new Claim("hoppa_user_id", "10466")
        ], Scheme.Name)), Scheme.Name)));
}
