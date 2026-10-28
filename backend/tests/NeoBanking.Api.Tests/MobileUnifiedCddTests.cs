using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Company;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public class MobileUnifiedCddTests
{
    [Theory]
    [InlineData(false, true, false)]
    [InlineData(true, false, false)]
    [InlineData(true, true, true)]
    public async Task ProviderAvailabilityAndStoredSelectionAreBothRequired(bool enabled, bool selected, bool allowed)
    {
        await using var db = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(db);
        db.Attach(user);
        user.MetadataJson = JsonSerializer.Serialize(new { unifiedCdd = new { exchange = selected, banking = false } });
        await db.SaveChangesAsync();
        var options = Options.Create(new CompanyOptions { Features = new() { BoomFiExchangeEnabled = enabled } });
        var proxy = new Recorder();
        var controller = new MobileUnifiedCddController(proxy, options, db, new EqualsConsentService(db, options)) {
            ControllerContext = Context(user.Id, user.CompanyInstallationId)
        };
        var result = await controller.Start(default);
        if (!allowed) { Assert.IsType<NotFoundResult>(result.Result); Assert.Null(proxy.Path); return; }
        Assert.Equal("/api/v2/mobile-onboarding/cdd/session", proxy.Path);
        Assert.Equal("42", proxy.Query!["userId"]);
        Assert.True(proxy.Private);
        Assert.True(proxy.Body.GetProperty("exchange").GetBoolean());
        Assert.False(proxy.Body.GetProperty("banking").GetBoolean());
        proxy.Failure = new ApplicationError("upstream", "Failed", 404, "{\"traceId\":\"internal\"}");
        var unavailable = Assert.IsType<ObjectResult>((await controller.Start(default)).Result);
        Assert.Equal(503, unavailable.StatusCode);
        var body = JsonSerializer.SerializeToElement(unavailable.Value);
        Assert.Equal("Verification is temporarily unavailable. Please try again shortly.", body.GetProperty("message").GetString());
        Assert.DoesNotContain("internal", body.ToString());
        proxy.Failure = null;
        controller.ControllerContext = Context(user.Id, Guid.NewGuid());
        Assert.IsType<NotFoundResult>((await controller.Start(default)).Result);
    }

    [Fact]
    public async Task BankingRequiresExistingEqualsConsentBeforeAnyUpstreamMutation()
    {
        await using var db = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(db);
        db.Attach(user);
        user.MetadataJson = "{\"unifiedCdd\":{\"exchange\":false,\"banking\":true}}";
        await db.SaveChangesAsync();
        var options = Options.Create(new CompanyOptions { Features = new() { EqualsMoneyEnabled = true },
            Branding = new() { EqualsGeneralTermsUrl = "https://example.test/terms.pdf" } });
        var proxy = new Recorder();
        var controller = new MobileUnifiedCddController(proxy, options, db, new EqualsConsentService(db, options)) { ControllerContext = Context(user.Id, user.CompanyInstallationId) };
        Assert.Equal(428, Assert.IsType<ObjectResult>((await controller.Submit(default)).Result).StatusCode);
        Assert.Null(proxy.Path);
        EqualsConsentService.AddEvidence(db, user, options.Value.Branding, DateTimeOffset.UtcNow, "test");
        await db.SaveChangesAsync();
        await controller.Start(default);
        Assert.Equal("/api/v2/mobile-onboarding/cdd/session", proxy.Path);
    }

    private static ControllerContext Context(Guid user, Guid company) => new() { HttpContext = new DefaultHttpContext {
        User = new ClaimsPrincipal(new ClaimsIdentity([new Claim("hoppa_user_id", "42"), new Claim("local_user_id", user.ToString()), new Claim("company_installation_id", company.ToString())], "test")) } };
    private sealed class Recorder : IProxyHoppaRequestUseCase
    {
        public ApplicationError? Failure;
        public string? Path; public bool Private; public JsonElement Body; public IReadOnlyDictionary<string, string?>? Query;
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command, CancellationToken ct)
        {
            Path = command.UpstreamPath; Private = command.SuppressPayloadLogging; Query = command.Query;
            Body = JsonSerializer.SerializeToElement(command.Request);
            if (Failure != null) return Task.FromResult(ApplicationResult<JsonElement?>.Failure(Failure));
            return Task.FromResult(ApplicationResult<JsonElement?>.Success(JsonSerializer.SerializeToElement(new { status = "in_progress" })));
        }
    }
}
