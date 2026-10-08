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
    }

    private sealed class RecordingProxy : IProxyHoppaRequestUseCase
    {
        public string? Path { get; private set; }

        public IReadOnlyDictionary<string, string?>? Query { get; private set; }

        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(
            ProxyHoppaRequestCommand<TRequest> command,
            CancellationToken cancellationToken)
        {
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
