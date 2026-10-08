#nullable enable

using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.Extensions.Options;
using NeoBanking.Application.MarketData;

namespace NeoBanking.Infrastructure.MarketData;

internal sealed class WiseFiatMarketRateProvider(
    HttpClient httpClient,
    IOptions<MarketDataOptions> options) : IFiatMarketRateProvider
{
    public async Task<IReadOnlyList<MarketRateQuote>> GetRatesAsync(
        string baseCurrency,
        IReadOnlyCollection<string> symbols,
        CancellationToken cancellationToken)
    {
        var marketOptions = options.Value;
        var token = marketOptions.Wise.BearerToken?.Trim();
        if (string.IsNullOrWhiteSpace(token))
        {
            throw new InvalidOperationException(
                "Wise market rates are enabled but MarketData:Wise:BearerToken is not configured.");
        }

        var normalizedBase = Normalize(baseCurrency);
        var quotes = new List<MarketRateQuote>(symbols.Count);
        foreach (var symbol in symbols.Select(Normalize).Distinct(StringComparer.Ordinal))
        {
            if (symbol == normalizedBase)
            {
                continue;
            }

            using var request = new HttpRequestMessage(
                HttpMethod.Get,
                $"{Uri.EscapeDataString(marketOptions.Wise.ApiVersion)}/rates" +
                $"?source={Uri.EscapeDataString(symbol)}&target={Uri.EscapeDataString(normalizedBase)}");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

            using var response = await httpClient.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();

            var payload = await response.Content.ReadFromJsonAsync<List<WiseRateResponse>>(
                cancellationToken: cancellationToken) ?? [];
            var rate = payload
                .Where(item => Normalize(item.Source) == symbol && Normalize(item.Target) == normalizedBase)
                .OrderByDescending(item => item.Time)
                .FirstOrDefault();

            if (rate is null || rate.Rate <= 0)
            {
                continue;
            }

            quotes.Add(new MarketRateQuote(
                symbol,
                normalizedBase,
                rate.Rate,
                "wise",
                rate.Time));
        }

        return quotes;
    }

    private static string Normalize(string? value) =>
        value?.Trim().ToUpperInvariant() ?? string.Empty;

    private sealed record WiseRateResponse(
        decimal Rate,
        string Source,
        string Target,
        DateTimeOffset Time);
}
