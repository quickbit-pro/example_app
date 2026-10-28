using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobilePersonalOnboardingTests
{
    [Fact]
    public async Task UsesTrustedActorAndSuppressesCodeAndPaymentPayloads()
    {
        using var db = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(db);
        var proxy = new Recorder();
        var controller = new MobilePersonalOnboardingController(proxy, db,
            Options.Create(new CompanyOptions { Features = new() { EqualsMoneyEnabled = true } })) {
            ControllerContext = MobileIdentityTestSupport.ControllerContext(user.Id)
        };
        ((ClaimsIdentity)controller.User.Identity!).AddClaim(new("company_installation_id", user.CompanyInstallationId.ToString()));
        controller.Request.QueryString = new QueryString("?userId=999&companyId=999");
        await controller.Status(default);
        await controller.Invite(default);
        await controller.RequestInvite(default);
        await controller.VerifyInvite(new("TESTCODE"), default);
        await controller.Checkout(1, new(false), default);
        Assert.Equal(new[] { "status", "invite", "invite/request", "invite/verify", "gates/1/checkout" },
            proxy.Calls.Select(x => x.Path.Replace("/api/v2/mobile-onboarding/", "")));
        Assert.All(proxy.Calls, x => { Assert.Equal("10466", x.Actor); Assert.True(x.Private); });
        Assert.False(proxy.Calls.Last().Body.GetProperty("TermsAccepted").GetBoolean());
        proxy.Error = new("upstream", "terms", 428, "{\"error\":\"PAYMENT_TERMS_REQUIRED\",\"terms\":{\"version\":\"1\"}}");
        var terms = Assert.IsType<ObjectResult>((await controller.Checkout(1, new(false), default)).Result);
        Assert.Equal(428, terms.StatusCode);
        Assert.Equal("PAYMENT_TERMS_REQUIRED", Assert.IsType<JsonElement>(terms.Value).GetProperty("error").GetString());
        controller.ControllerContext = MobileIdentityTestSupport.ControllerContext(Guid.NewGuid());
        var count = proxy.Calls.Count;
        Assert.IsType<NotFoundResult>((await controller.Invite(default)).Result);
        Assert.Equal(count, proxy.Calls.Count);
    }
    private sealed class Recorder : IProxyHoppaRequestUseCase
    {
        public ApplicationError? Error;
        public List<(string Path, string? Actor, bool Private, JsonElement Body)> Calls = [];
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command, CancellationToken ct)
        {
            Calls.Add((command.UpstreamPath, command.Query["userId"], command.SuppressPayloadLogging, JsonSerializer.SerializeToElement(command.Request)));
            return Task.FromResult(Error != null ? ApplicationResult<JsonElement?>.Failure(Error)
                : ApplicationResult<JsonElement?>.Success(JsonSerializer.SerializeToElement(new { nextAction = "START_KYC1" })));
        }
    }
}
