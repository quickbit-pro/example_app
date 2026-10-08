#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NeoBanking.Application.MarketData;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Infrastructure.MarketData;

internal sealed class MarketRateService(
    NeoBankingDbContext dbContext,
    IFiatMarketRateProvider fiatProvider,
    ICryptoMarketRateProvider cryptoProvider,
    IOptions<MarketDataOptions> options,
    TimeProvider timeProvider,
    ILogger<MarketRateService> logger) : IMarketRateService
{
    public async Task<MarketRateBatch> GetLatestAsync(
        string? baseCurrency,
        bool refreshIfEmpty,
        CancellationToken cancellationToken)
    {
        var normalizedBase = ValidateBaseCurrency(baseCurrency);
        var batch = await ReadLatestAsync(normalizedBase, cancellationToken);

        if (refreshIfEmpty && batch.Rates.Count == 0 && options.Value.Enabled)
        {
            return await RefreshAsync(normalizedBase, cancellationToken);
        }

        return batch;
    }

    public async Task<MarketRateBatch> RefreshAsync(
        string? baseCurrency,
        CancellationToken cancellationToken)
    {
        var normalizedBase = ValidateBaseCurrency(baseCurrency);
        if (!options.Value.Enabled)
        {
            return await ReadLatestAsync(normalizedBase, cancellationToken);
        }

        var expectedFiat = ExpectedFiatCurrencies();
        var expectedCrypto = ExpectedCryptoCurrencies();
        var observed = new List<MarketRateQuote>(expectedFiat.Count + expectedCrypto.Count);
        observed.Add(new MarketRateQuote(
            normalizedBase,
            normalizedBase,
            1m,
            "identity",
            timeProvider.GetUtcNow()));

        try
        {
            observed.AddRange(await fiatProvider.GetRatesAsync(
                normalizedBase,
                expectedFiat,
                cancellationToken));
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            logger.LogWarning(exception, "Failed to refresh Wise fiat rates for {BaseCurrency}.", normalizedBase);
        }

        try
        {
            observed.AddRange(await cryptoProvider.GetRatesAsync(
                normalizedBase,
                expectedCrypto,
                cancellationToken));
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            logger.LogWarning(exception, "Failed to refresh CoinGecko crypto rates for {BaseCurrency}.", normalizedBase);
        }

        await PersistAsync(observed, cancellationToken);
        await PruneAsync(cancellationToken);

        return await ReadLatestAsync(normalizedBase, cancellationToken);
    }

    private async Task PersistAsync(
        IReadOnlyCollection<MarketRateQuote> quotes,
        CancellationToken cancellationToken)
    {
        foreach (var quote in quotes
                     .Where(quote => quote.Rate > 0)
                     .GroupBy(quote => new
                     {
                         quote.BaseCurrency,
                         quote.Symbol,
                         quote.Provider,
                         quote.ObservedAt
                     })
                     .Select(group => group.First()))
        {
            var exists = await dbContext.MarketRateSnapshots.AnyAsync(
                rate => rate.BaseCurrency == quote.BaseCurrency &&
                        rate.QuoteCurrency == quote.Symbol &&
                        rate.Provider == quote.Provider &&
                        rate.ObservedAt == quote.ObservedAt,
                cancellationToken);
            if (exists)
            {
                continue;
            }

            dbContext.MarketRateSnapshots.Add(new MarketRateSnapshot
            {
                BaseCurrency = quote.BaseCurrency,
                QuoteCurrency = quote.Symbol,
                Rate = quote.Rate,
                Provider = quote.Provider,
                ObservedAt = quote.ObservedAt
            });
        }

        await dbContext.SaveChangesAsync(cancellationToken);
    }

    private async Task PruneAsync(CancellationToken cancellationToken)
    {
        var retentionDays = Math.Clamp(options.Value.RetentionDays, 2, 3650);
        var cutoff = timeProvider.GetUtcNow().AddDays(-retentionDays);
        await dbContext.MarketRateSnapshots
            .Where(rate => rate.ObservedAt < cutoff)
            .ExecuteDeleteAsync(cancellationToken);
    }

    private async Task<MarketRateBatch> ReadLatestAsync(
        string baseCurrency,
        CancellationToken cancellationToken)
    {
        var retentionDays = Math.Clamp(options.Value.RetentionDays, 2, 3650);
        var cutoff = timeProvider.GetUtcNow().AddDays(-retentionDays);
        var storedRates = await dbContext.MarketRateSnapshots
            .AsNoTracking()
            .Where(rate => rate.BaseCurrency == baseCurrency && rate.ObservedAt >= cutoff)
            .OrderByDescending(rate => rate.ObservedAt)
            .ToListAsync(cancellationToken);

        var latest = storedRates
            .GroupBy(rate => rate.QuoteCurrency, StringComparer.Ordinal)
            .Select(group => group.First())
            .OrderBy(rate => rate.QuoteCurrency, StringComparer.Ordinal)
            .Select(rate => new MarketRateQuote(
                rate.QuoteCurrency,
                rate.BaseCurrency,
                rate.Rate,
                rate.Provider,
                rate.ObservedAt))
            .ToArray();

        var expected = ExpectedSymbols(baseCurrency);
        var available = latest.Select(rate => rate.Symbol).ToHashSet(StringComparer.Ordinal);
        var missing = expected.Where(symbol => !available.Contains(symbol)).ToArray();
        var refreshedAt = latest.Length == 0
            ? (DateTimeOffset?)null
            : latest.Max(rate => rate.ObservedAt);
        var staleMinutes = Math.Clamp(options.Value.StaleAfterMinutes, 5, 1440);

        return new MarketRateBatch(
            baseCurrency,
            refreshedAt,
            timeProvider.GetUtcNow().AddMinutes(-staleMinutes),
            latest,
            expected,
            missing);
    }

    private string ValidateBaseCurrency(string? baseCurrency)
    {
        var normalized = Normalize(baseCurrency);
        if (string.IsNullOrWhiteSpace(normalized))
        {
            normalized = Normalize(options.Value.DefaultBaseCurrency);
        }

        if (!ExpectedFiatCurrencies().Contains(normalized, StringComparer.Ordinal))
        {
            throw new ArgumentException($"Unsupported market-rate base currency '{normalized}'.", nameof(baseCurrency));
        }

        return normalized;
    }

    private IReadOnlyList<string> ExpectedSymbols(string baseCurrency) =>
        ExpectedFiatCurrencies()
            .Concat(ExpectedCryptoCurrencies())
            .Append(baseCurrency)
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();

    private IReadOnlyList<string> ExpectedFiatCurrencies() =>
        options.Value.FiatCurrencies
            .Select(Normalize)
            .Where(currency => currency.Length == 3)
            .Distinct(StringComparer.Ordinal)
            .ToArray();

    private IReadOnlyList<string> ExpectedCryptoCurrencies() =>
        options.Value.CryptoCurrencies
            .Select(Normalize)
            .Where(currency => !string.IsNullOrWhiteSpace(currency))
            .Distinct(StringComparer.Ordinal)
            .ToArray();

    private static string Normalize(string? value) =>
        value?.Trim().ToUpperInvariant() ?? string.Empty;
}
