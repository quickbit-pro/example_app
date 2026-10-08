using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.MarketData;
using NeoBanking.Application.Security;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/market-data")]
public sealed class MobileMarketDataController(IMarketRateService marketRates) : ApiControllerBase
{
    [HttpGet("rates")]
    public async Task<ActionResult<MarketRateResponse>> GetRates(
        [FromQuery] string? baseCurrency,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out _))
        {
            return MissingIdentity<MarketRateResponse>();
        }

        try
        {
            var batch = await marketRates.GetLatestAsync(
                baseCurrency,
                refreshIfEmpty: true,
                cancellationToken);

            return Ok(MarketRateResponse.From(batch));
        }
        catch (ArgumentException exception)
        {
            return Problem(
                title: "Unsupported base currency.",
                detail: exception.Message,
                statusCode: StatusCodes.Status400BadRequest);
        }
    }
}

public sealed record MarketRateResponse(
    string BaseCurrency,
    DateTimeOffset? RefreshedAt,
    bool IsStale,
    bool IsPartial,
    IReadOnlyList<string> MissingSymbols,
    IReadOnlyList<MarketRateItemResponse> Rates)
{
    public static MarketRateResponse From(MarketRateBatch batch) => new(
        batch.BaseCurrency,
        batch.RefreshedAt,
        batch.IsStale,
        batch.IsPartial,
        batch.MissingSymbols,
        batch.Rates.Select(MarketRateItemResponse.From).ToArray());
}

public sealed record MarketRateItemResponse(
    string Symbol,
    decimal Rate,
    string Provider,
    DateTimeOffset ObservedAt)
{
    public static MarketRateItemResponse From(MarketRateQuote quote) => new(
        quote.Symbol,
        quote.Rate,
        quote.Provider,
        quote.ObservedAt);
}
