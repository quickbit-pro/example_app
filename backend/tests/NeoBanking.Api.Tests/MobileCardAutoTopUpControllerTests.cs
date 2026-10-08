using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobileCardAutoTopUpControllerTests
{
    [Fact]
    public async Task ReadUsesTrustedIdentityIgnoringCallerQuery()
    {
        var proxy = new Proxy();
        var controller = Controller(proxy);
        controller.Request.QueryString = new QueryString("?userId=999");
        await controller.Get(123, default);
        Assert.Equal("/api/v2/cards/123/auto-topup", proxy.Path);
        Assert.Equal("10466", proxy.UserId);
        Assert.Equal(HttpMethod.Get, proxy.Method);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("0")]
    [InlineData("abc")]
    public async Task MissingIdentityNeverReachesProvider(string? identity)
    {
        var proxy = new Proxy();
        var result = await Controller(proxy, identity).Get(123, default);
        Assert.Equal(401, Assert.IsType<ObjectResult>(result.Result).StatusCode);
        Assert.Equal(0, proxy.Calls);
    }

    [Theory]
    [InlineData(false, 10, 50, 500)]
    [InlineData(true, 0, 50, 500)]
    [InlineData(true, 50, 50, 500)]
    [InlineData(true, 10, 50, 0)]
    public async Task InvalidLowBalanceDoesNotChangeSettings(bool consent, int threshold, int target, int monthly)
    {
        var proxy = new Proxy();
        var result = await Controller(proxy).LowBalance(new(123, true, threshold, target, monthly, consent), default);
        Assert.Equal(400, Assert.IsType<ObjectResult>(result.Result).StatusCode);
        Assert.Equal(0, proxy.Calls);
    }

    [Fact]
    public async Task LowBalanceForwardsTargetAndConsent()
    {
        var proxy = new Proxy();
        await Controller(proxy).LowBalance(new(123, true, 10, 50, 500, true), default);
        Assert.Equal("/api/v2/cards/auto-topup/low-balance", proxy.Path);
        Assert.Equal(HttpMethod.Post, proxy.Method);
        Assert.Equal("10466", proxy.UserId);
        Assert.Equal(50, proxy.Body.GetProperty("TargetBalance").GetDecimal());
        Assert.True(proxy.Body.GetProperty("DisclaimerAccepted").GetBoolean());
    }

    [Fact]
    public async Task EachModeCanBeDisabledWithoutConsentOrAmounts()
    {
        var proxy = new Proxy();
        var controller = Controller(proxy);
        await controller.LowBalance(new(123, false, 0, 0, 0, false), default);
        await controller.FailedTransaction(new(123, false, 0, 0, false), default);
        await controller.Deposit(new(123, false, [new("USDC", false, 0), new("USDT", false, 0)]), default);
        Assert.Equal(3, proxy.Calls);
    }

    [Fact]
    public async Task InvalidFailedPaymentOrDepositNeverReachesProvider()
    {
        var proxy = new Proxy();
        var controller = Controller(proxy);
        var requests = new[] {
            await controller.FailedTransaction(new(123, true, 10, 100, false), default),
            await controller.FailedTransaction(new(123, true, 0, 100, true), default),
            await controller.Deposit(new(123, false, [new("USDC", true, 10)]), default),
            await controller.Deposit(new(123, true, [new("BTC", true, 10)]), default),
            await controller.Deposit(new(123, true, [new("USDC", true, 10), new("USDC", true, 20)]), default),
            await controller.Deposit(new(123, true, null), default)
        };
        Assert.All(requests, result => Assert.Equal(400, Assert.IsType<ObjectResult>(result.Result).StatusCode));
        Assert.Equal(0, proxy.Calls);
    }

    [Fact]
    public async Task OwnershipFailureIsNotReportedAsSuccess()
    {
        var proxy = new Proxy { Fail = true };
        var result = await Controller(proxy).Get(123, default);
        Assert.Equal(404, Assert.IsType<ObjectResult>(result.Result).StatusCode);
    }

    private static MobileCardAutoTopUpController Controller(Proxy proxy, string? identity = "10466") => new(proxy) {
        ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext {
            User = new ClaimsPrincipal(new ClaimsIdentity(identity is null ? [] : new[] { new Claim("hoppa_user_id", identity) }, "test"))
        } }
    };

    private sealed class Proxy : IProxyHoppaRequestUseCase
    {
        public int Calls;
        public string? Path, UserId;
        public HttpMethod? Method;
        public JsonElement Body;
        public bool Fail;
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command, CancellationToken cancellationToken)
        {
            Calls++;
            Path = command.UpstreamPath;
            Method = command.Method;
            UserId = command.Query["userId"];
            Body = JsonSerializer.SerializeToElement(command.Request);
            return Task.FromResult(Fail
                ? ApplicationResult<JsonElement?>.Failure(new ApplicationError("not_found", "Card not found", 404))
                : ApplicationResult<JsonElement?>.Success(JsonSerializer.SerializeToElement(new { success = true })));
        }
    }
}
