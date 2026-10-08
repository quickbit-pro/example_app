using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.MarketData;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobileMarketDataControllerTests
{
    [Fact]
    public async Task GetRates_ReturnsFreshnessAndMissingSymbols()
    {
        var now = DateTimeOffset.Parse("2026-09-01T08:00:00Z");
        var service = new StubMarketRateService(new MarketRateBatch(
            "USD",
            now,
            now.AddMinutes(-90),
            [new MarketRateQuote("EUR", "USD", 1.17m, "wise", now)],
            ["EUR", "USDC"],
            ["USDC"]));
        var controller = CreateController(service);

        var response = await controller.GetRates("USD", CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);
        var payload = Assert.IsType<MarketRateResponse>(ok.Value);
        Assert.True(payload.IsPartial);
        Assert.False(payload.IsStale);
        Assert.Equal("USDC", Assert.Single(payload.MissingSymbols));
        Assert.Equal("wise", Assert.Single(payload.Rates).Provider);
    }

    private static MobileMarketDataController CreateController(IMarketRateService service)
    {
        var controller = new MobileMarketDataController(service)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(
                        [new Claim("hoppa_user_id", "10466")],
                        "test"))
                }
            }
        };
        return controller;
    }

    private sealed class StubMarketRateService(MarketRateBatch batch) : IMarketRateService
    {
        public Task<MarketRateBatch> GetLatestAsync(
            string? baseCurrency,
            bool refreshIfEmpty,
            CancellationToken cancellationToken) => Task.FromResult(batch);

        public Task<MarketRateBatch> RefreshAsync(
            string? baseCurrency,
            CancellationToken cancellationToken) => Task.FromResult(batch);
    }
}
