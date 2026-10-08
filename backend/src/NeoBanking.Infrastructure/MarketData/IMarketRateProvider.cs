#nullable enable

using NeoBanking.Application.MarketData;

namespace NeoBanking.Infrastructure.MarketData;

internal interface IFiatMarketRateProvider
{
    Task<IReadOnlyList<MarketRateQuote>> GetRatesAsync(
        string baseCurrency,
        IReadOnlyCollection<string> symbols,
        CancellationToken cancellationToken);
}

internal interface ICryptoMarketRateProvider
{
    Task<IReadOnlyList<MarketRateQuote>> GetRatesAsync(
        string baseCurrency,
        IReadOnlyCollection<string> symbols,
        CancellationToken cancellationToken);
}
