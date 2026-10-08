#nullable enable

using System.Text.Json;
using Microsoft.Extensions.Options;
using NeoBanking.Application.MarketData;

namespace NeoBanking.Infrastructure.MarketData;

internal sealed class CoinGeckoCryptoMarketRateProvider(
    HttpClient httpClient,
    IOptions<MarketDataOptions> options) : ICryptoMarketRateProvider
{
    private static readonly IReadOnlyDictionary<string, string> CoinIds =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["USDT"] = "tether",
            ["USDC"] = "usd-coin"
        };

    public async Task<IReadOnlyList<MarketRateQuote>> GetRatesAsync(
        string baseCurrency,
        IReadOnlyCollection<string> symbols,
        CancellationToken cancellationToken)
    {
        var requested = symbols
            .Select(Normalize)
            .Where(CoinIds.ContainsKey)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (requested.Length == 0)
        {
            return [];
        }

        var marketOptions = options.Value;
        var coinIds = string.Join(',', requested.Select(symbol => CoinIds[symbol]));
        var normalizedBase = Normalize(baseCurrency);
        var versusCurrency = normalizedBase.ToLowerInvariant();
        var path = $"simple/price?ids={Uri.EscapeDataString(coinIds)}" +
                   $"&vs_currencies={Uri.EscapeDataString(versusCurrency)}&include_last_updated_at=true";

        using var request = new HttpRequestMessage(HttpMethod.Get, path);
        var apiKey = marketOptions.CoinGecko.ApiKey?.Trim();
        if (!string.IsNullOrWhiteSpace(apiKey))
        {
            request.Headers.TryAddWithoutValidation(
                marketOptions.CoinGecko.ProApi ? "x-cg-pro-api-key" : "x-cg-demo-api-key",
                apiKey);
        }

        using var response = await httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var now = DateTimeOffset.UtcNow;
        var quotes = new List<MarketRateQuote>(requested.Length);

        foreach (var symbol in requested)
        {
            if (!document.RootElement.TryGetProperty(CoinIds[symbol], out var coin) ||
                !coin.TryGetProperty(versusCurrency, out var priceElement) ||
                !priceElement.TryGetDecimal(out var rate) ||
                rate <= 0)
            {
                continue;
            }

            var observedAt = now;
            if (coin.TryGetProperty("last_updated_at", out var timestampElement) &&
                timestampElement.TryGetInt64(out var unixTimestamp))
            {
                observedAt = DateTimeOffset.FromUnixTimeSeconds(unixTimestamp);
            }

            quotes.Add(new MarketRateQuote(
                symbol,
                normalizedBase,
                rate,
                "coingecko",
                observedAt));
        }

        return quotes;
    }

    private static string Normalize(string? value) =>
        value?.Trim().ToUpperInvariant() ?? string.Empty;
}
