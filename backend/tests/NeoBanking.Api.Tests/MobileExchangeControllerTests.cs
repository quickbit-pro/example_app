using Xunit;
using System.Net;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Tests;

public sealed class MobileExchangeControllerTests
{
    [Theory]
    [InlineData(1)]
    [InlineData(-200)]
    public async Task PayInAddressUsesAuthenticatedUserAndDoesNotRequireOutflows(int chain)
    {
        var proxy = new Recorder();
        await Controller(proxy, true, false).CreatePayInAddress(
            JsonSerializer.SerializeToElement(new { userId = 999, crypto_currency = "USDT", chain_id = chain }), default);
        Assert.Equal("/api/v2/crypto-virtual-accounts/payin-address", proxy.Path);
        Assert.Equal(HttpMethod.Post, proxy.Method);
        Assert.Equal("42", proxy.Query!["userId"]);
        Assert.Equal(42, proxy.Body.GetProperty("userId").GetInt32());
        Assert.Equal("USDT", proxy.Body.GetProperty("crypto_currency").GetString());
        Assert.Equal(chain, proxy.Body.GetProperty("chain_id").GetInt32());
        Assert.True(proxy.Private);
    }

    [Fact]
    public async Task PayInAddressRemainsDisabledWhenExchangeIsDisabled()
    {
        var proxy = new Recorder();
        var result = await Controller(proxy, false).CreatePayInAddress(
            JsonSerializer.SerializeToElement(new { crypto_currency = "USDT", chain_id = -200 }), default);
        Assert.Equal(403, Assert.IsType<ObjectResult>(result.Result).StatusCode);
        Assert.Null(proxy.Path);
    }

    [Fact]
    public async Task ApplicationUsesAuthenticatedIdentityAndPreservesQuestionnaireKeys()
    {
        var proxy = new Recorder(); var controller = Controller(proxy);
        await controller.SubmitApplication(JsonDocument.Parse("""{"userId":999,"UserId":998,"USERID":997,"answers":{"sdd_country_select":"SI","annual_income":"75"}}""").RootElement, default);
        Assert.Equal("/api/v2/crypto-virtual-accounts/verification/application", proxy.Path);
        Assert.Equal("42", proxy.Query!["userId"]);
        Assert.Equal(42, proxy.Body.GetProperty("userId").GetInt32());
        Assert.False(proxy.Body.TryGetProperty("USERID", out _));
        Assert.Equal("SI", proxy.Body.GetProperty("answers").GetProperty("sdd_country_select").GetString());
        Assert.True(proxy.Private);
    }

    [Theory]
    [InlineData(false, true)] [InlineData(true, false)]
    public async Task PayoutRequiresExchangeAndOutflows(bool exchange, bool outflows)
    {
        var proxy = new Recorder(); var controller = Controller(proxy, exchange, outflows);
        var result = await controller.CryptoPayout(JsonSerializer.SerializeToElement(new { amount = "1" }), default);
        Assert.Equal(403, Assert.IsType<ObjectResult>(result.Result).StatusCode);
        Assert.Null(proxy.Path);
    }

    [Fact]
    public async Task QuotesAreAvailableWithoutOutflowsButAcceptanceIsBlocked()
    {
        var proxy = new Recorder(); var controller = Controller(proxy, true, false);
        await controller.GetExchangeQuote(JsonSerializer.SerializeToElement(new { sellAmount = "1" }), default);
        Assert.Equal("/api/v2/crypto-virtual-accounts/exchange/quote", proxy.Path);
        proxy.Path = null;
        var result = await controller.AcceptExchangeQuote(JsonSerializer.SerializeToElement(new { quoteId = "q" }), default);
        Assert.Equal(403, Assert.IsType<ObjectResult>(result.Result).StatusCode);
        Assert.Null(proxy.Path);
    }

    [Fact]
    public async Task DeleteDestinationScopesUserAndUsesPublicRoute()
    {
        var proxy = new Recorder(); await Controller(proxy).DeleteDestination(81, default);
        Assert.Equal(HttpMethod.Delete, proxy.Method);
        Assert.Equal("/api/v2/crypto-virtual-accounts/external-accounts/81", proxy.Path);
        Assert.Equal("42", proxy.Query!["userId"]);
    }

    [Theory]
    [InlineData(400, "The provider could not accept your shared verification or application answers. No Exchange account was created. Review your details and retry, or contact support if this continues.", true)]
    [InlineData(409, "Exchange already has an organisation for this email address. Contact support.", true)]
    [InlineData(502, "Internal provider failure", false)]
    [InlineData(400, "secret token abc", false)]
    [InlineData(400, "https://internal.invalid/trace", false)]
    public async Task ExchangeOnlyExposesActionableSafeErrors(int status, string upstream, bool visible)
    {
        const string generic = "We could not process the Exchange request.";
        var proxy = new Recorder { Error = new ApplicationError("mobile.exchange.upstream_failed", generic, status,
            JsonSerializer.Serialize(new { message = upstream, secret = "never-forward" })) };
        var result = await Controller(proxy).SubmitApplication(JsonSerializer.SerializeToElement(new { answers = new { } }), default);
        var problem = Assert.IsType<ProblemDetails>(Assert.IsType<ObjectResult>(result.Result).Value);
        Assert.Equal(visible ? upstream : generic, problem.Title);
        Assert.Null(problem.Detail);
        Assert.Equal(status, problem.Status);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task SavingDestinationDoesNotRequireOutflowsAndUsesAuthenticatedUser(bool bank)
    {
        var proxy = new Recorder(); var controller = Controller(proxy, true, false);
        var payload = JsonSerializer.SerializeToElement(new { userId = 999, name = "My destination" });
        if (bank) await controller.RegisterBank(payload, default);
        else await controller.RegisterCrypto(payload, default);
        Assert.Equal("/api/v2/crypto-virtual-accounts/" + (bank ? "bank-address-book" : "crypto-address-book"), proxy.Path);
        Assert.Equal("42", proxy.Query!["userId"]);
        Assert.Equal(42, proxy.Body.GetProperty("userId").GetInt32());
        Assert.True(proxy.Private);
    }

    [Fact]
    public async Task SavingCryptoDestinationStillRequiresExchangeFeature()
    {
        var proxy = new Recorder();
        var result = await Controller(proxy, false, false).RegisterCrypto(JsonSerializer.SerializeToElement(new { }), default);
        Assert.Equal(403, Assert.IsType<ObjectResult>(result.Result).StatusCode);
        Assert.Null(proxy.Path);
    }

    private static MobileExchangeController Controller(Recorder proxy, bool exchange=true, bool outflows=true) => new(proxy,
        Options.Create(new CompanyOptions { Features = new CompanyFeatureOptions { BoomFiExchangeEnabled=exchange, WalletOutflowsEnabled=outflows } }))
    { ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext {
        User = new ClaimsPrincipal(new ClaimsIdentity([new Claim("hoppa_user_id","42")],"test")) } } };

    private sealed class Recorder : IProxyHoppaRequestUseCase
    {
        public ApplicationError? Error;
        public string? Path; public HttpMethod? Method; public JsonElement Body;
        public IReadOnlyDictionary<string,string?>? Query; public bool Private;
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command, CancellationToken ct)
        {
            Path=command.UpstreamPath; Method=command.Method; Query=command.Query; Private=command.SuppressPayloadLogging;
            Body=JsonSerializer.SerializeToElement(command.Request);
            if (Error is not null) return Task.FromResult(ApplicationResult<JsonElement?>.Failure(Error));
            return Task.FromResult(ApplicationResult<JsonElement?>.Success(JsonSerializer.SerializeToElement(new { success=true })));
        }
    }
}
