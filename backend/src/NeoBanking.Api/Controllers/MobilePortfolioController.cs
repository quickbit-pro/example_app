using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Portfolio;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Infrastructure.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/portfolio")]
public sealed class MobilePortfolioController(
    IProxyHoppaRequestUseCase proxyHoppa,
    IOptions<HoppaOptions> hoppaOptions) : ApiControllerBase
{
    [HttpGet("summary")]
    public async Task<ActionResult<JsonElement?>> GetSummary(
        [FromQuery] string currency = "USD",
        CancellationToken cancellationToken = default)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var normalizedCurrency = currency.Trim().ToUpperInvariant();
        if (normalizedCurrency.Length != 3)
        {
            return Problem(
                title: "Invalid display currency.",
                detail: "Currency must be a three-letter ISO currency code.",
                statusCode: StatusCodes.Status400BadRequest);
        }

        var upstreamPath = hoppaOptions.Value.PortfolioEstimatePath?.Trim();
        if (string.IsNullOrWhiteSpace(upstreamPath))
        {
            return Problem(
                title: "Portfolio estimate is not configured.",
                detail: "Portfolio estimates are not available yet.",
                statusCode: StatusCodes.Status503ServiceUnavailable);
        }

        var result = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object?>
            {
                Method = HttpMethod.Get,
                UpstreamPath = upstreamPath,
                Query = new Dictionary<string, string?>
                {
                    ["user_id"] = userId,
                    ["currency"] = normalizedCurrency
                },
                Request = null,
                FailureCode = "mobile.portfolio.summary.failed",
                FailureMessage = "We could not estimate total assets."
            },
            cancellationToken);
        if (!result.IsSuccess)
        {
            return ToActionResult(result);
        }

        var estimate = HoppaPortfolioEstimateMapper.Map(result.Value, normalizedCurrency);
        if (estimate.Total is null)
        {
            return Problem(
                title: "The account provider returned an invalid portfolio estimate.",
                detail: "The response did not contain a recognized total-assets value.",
                statusCode: StatusCodes.Status502BadGateway);
        }

        return Ok(JsonSerializer.SerializeToElement(estimate, JsonSerializerOptions.Web));
    }
}
