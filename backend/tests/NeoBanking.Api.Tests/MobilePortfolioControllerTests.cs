using System.Net.Http;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Infrastructure.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobilePortfolioControllerTests
{
    [Fact]
    public async Task GetSummary_InjectsAuthenticatedHoppaUserIdAndCurrency()
    {
        var proxy = new RecordingProxy();
        var controller = new MobilePortfolioController(
            proxy,
            Options.Create(new HoppaOptions
            {
                PortfolioEstimatePath = "/api/v2/prices/estimated-total-assets"
            }))
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

        var response = await controller.GetSummary("gbp", CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);
        var payload = Assert.IsType<JsonElement>(ok.Value);
        Assert.Equal(100m, payload.GetProperty("total").GetDecimal());
        Assert.False(payload.TryGetProperty("Total", out _));
        Assert.Equal("/api/v2/prices/estimated-total-assets", proxy.Path);
        Assert.Equal("10466", proxy.Query?["user_id"]);
        Assert.Equal("GBP", proxy.Query?["currency"]);
        Assert.Equal("/api/v2/prices", proxy.PricesPath);
        var eurRate = Assert.Single(payload.GetProperty("valuationRates").EnumerateArray(),
            row => row.GetProperty("currency").GetString() == "EUR");
        Assert.Equal(.8m, eurRate.GetProperty("rate").GetDecimal());
    }

    [Fact]
    public async Task GetSummary_PreservesEstimateWhenReferencePricesAreUnavailable()
    {
        var proxy = new RecordingProxy { PricesUnavailable = true };
        var controller = new MobilePortfolioController(proxy,
            Options.Create(new HoppaOptions { PortfolioEstimatePath = "/api/v2/prices/estimated-total-assets" }))
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(
                        [new Claim("hoppa_user_id", "227")], "test"))
                }
            }
        };

        var response = await controller.GetSummary("GBP", CancellationToken.None);
        var payload = Assert.IsType<JsonElement>(Assert.IsType<OkObjectResult>(response.Result).Value);
        Assert.Equal(100m, payload.GetProperty("total").GetDecimal());
        Assert.Single(payload.GetProperty("valuationRates").EnumerateArray());
    }

    private sealed class RecordingProxy : IProxyHoppaRequestUseCase
    {
        public string? Path { get; private set; }

        public IReadOnlyDictionary<string, string?>? Query { get; private set; }

        public string? PricesPath { get; private set; }
        public bool PricesUnavailable { get; init; }

        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(
            ProxyHoppaRequestCommand<TRequest> command,
            CancellationToken cancellationToken)
        {
            if (command.UpstreamPath == "/api/v2/prices")
            {
                PricesPath = command.UpstreamPath;
                if (PricesUnavailable)
                    return Task.FromResult(ApplicationResult<JsonElement?>.Failure(
                        new ApplicationError("prices.unavailable", "Unavailable", 503)));
                return Task.FromResult(ApplicationResult<JsonElement?>.Success(JsonSerializer.SerializeToElement(new[]
                {
                    new { assetCode = "USD", baseCurrency = "USD", price = 1m, isAvailable = true },
                    new { assetCode = "EUR", baseCurrency = "USD", price = 1.12m, isAvailable = true },
                    new { assetCode = "GBP", baseCurrency = "USD", price = 1.4m, isAvailable = true }
                })));
            }
            Path = command.UpstreamPath;
            Query = command.Query;
            using var document = JsonDocument.Parse("""
                { "estimatedTotalAssets": 100, "currency": "GBP" }
                """);
            return Task.FromResult(ApplicationResult<JsonElement?>.Success(
                document.RootElement.Clone()));
        }
    }
}
