#nullable enable

namespace NeoBanking.Application.MarketData;

public sealed record MarketRateQuote(
    string Symbol,
    string BaseCurrency,
    decimal Rate,
    string Provider,
    DateTimeOffset ObservedAt);

public sealed record MarketRateBatch(
    string BaseCurrency,
    DateTimeOffset? RefreshedAt,
    DateTimeOffset StaleAfter,
    IReadOnlyList<MarketRateQuote> Rates,
    IReadOnlyList<string> ExpectedSymbols,
    IReadOnlyList<string> MissingSymbols)
{
    public bool IsPartial => MissingSymbols.Count > 0;

    public bool IsStale => RefreshedAt is null || RefreshedAt < StaleAfter;
}

public interface IMarketRateService
{
    Task<MarketRateBatch> GetLatestAsync(
        string? baseCurrency,
        bool refreshIfEmpty,
        CancellationToken cancellationToken);

    Task<MarketRateBatch> RefreshAsync(
        string? baseCurrency,
        CancellationToken cancellationToken);
}
