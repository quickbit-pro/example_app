#nullable enable

namespace NeoBanking.Infrastructure.MarketData;

public sealed class MarketDataOptions
{
    public const string SectionName = "MarketData";

    public bool Enabled { get; init; }

    public string DefaultBaseCurrency { get; init; } = "USD";

    public int RefreshMinutes { get; init; } = 60;

    public int StaleAfterMinutes { get; init; } = 90;

    public int RetentionDays { get; init; } = 400;

    public string[] FiatCurrencies { get; init; } =
    [
        "AED", "AUD", "BBD", "BHD", "CAD", "CHF", "CZK", "DKK", "EUR", "GBP",
        "GHS", "HKD", "HUF", "ILS", "JPY", "KES", "MWK", "MXN", "NOK", "NZD",
        "OMR", "PHP", "PKR", "PLN", "QAR", "RON", "SAR", "SEK", "SGD", "THB",
        "TND", "TRY", "TTD", "UGX", "USD", "ZAR", "ZMW"
    ];

    public string[] CryptoCurrencies { get; init; } = ["USDT", "USDC"];

    public WiseRateOptions Wise { get; init; } = new();

    public CoinGeckoRateOptions CoinGecko { get; init; } = new();
}

public sealed class WiseRateOptions
{
    public Uri BaseUrl { get; init; } = new("https://api.wise.com/");

    public string ApiVersion { get; init; } = "2026Q3";

    public string? BearerToken { get; init; }

    public int TimeoutSeconds { get; init; } = 30;
}

public sealed class CoinGeckoRateOptions
{
    public Uri BaseUrl { get; init; } = new("https://api.coingecko.com/api/v3/");

    public string? ApiKey { get; init; }

    public bool ProApi { get; init; }

    public int TimeoutSeconds { get; init; } = 30;
}
