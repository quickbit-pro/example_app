using System.Text.Json;

namespace NeoBanking.Api.Portfolio;

public sealed record PortfolioEstimateResponse(
    string Currency,
    decimal? Total,
    DateTimeOffset? ValuedAt,
    bool IsPartial,
    bool IsStale,
    IReadOnlyList<string> MissingCurrencies,
    IReadOnlyList<PortfolioProviderTotalResponse> ProviderTotals,
    string Source,
    IReadOnlyList<PortfolioValuationRateResponse> ValuationRates);

public sealed record PortfolioValuationRateResponse(string Currency, decimal Rate);

public sealed record PortfolioProviderTotalResponse(
    string Provider,
    decimal? Total,
    string Currency,
    int AssetCount,
    bool IsAvailable,
    IReadOnlyList<string> UnpricedAssetCodes);

public static class HoppaPortfolioEstimateMapper
{
    public static PortfolioEstimateResponse Map(JsonElement? payload, string requestedCurrency)
    {
        var root = Unwrap(payload);
        var currency = ReadString(
                           root,
                           "currency", "Currency", "baseCurrency", "BaseCurrency",
                           "displayCurrency", "DisplayCurrency") ?? requestedCurrency;
        var total = ReadDecimal(
                        root,
                        "total", "Total", "totalValue", "TotalValue", "totalAssets", "TotalAssets",
                        "estimatedTotal", "EstimatedTotal", "estimatedTotalAssets", "EstimatedTotalAssets");
        var valuedAt = ReadDateTimeOffset(
            root,
            "calculatedAt", "CalculatedAt", "valuedAt", "ValuedAt", "asOf", "AsOf",
            "timestamp", "Timestamp", "updatedAt", "UpdatedAt");
        var missing = ReadStrings(
            root,
            "unpricedAssetCodes", "UnpricedAssetCodes",
            "missingCurrencies", "MissingCurrencies", "missingAssets", "MissingAssets");
        var isComplete = ReadBoolean(root, "isComplete", "IsComplete");
        var isPartial = ReadBoolean(root, "isPartial", "IsPartial", "partial", "Partial") == true ||
                        isComplete == false ||
                        (isComplete is null && missing.Count > 0);

        return new PortfolioEstimateResponse(
            currency.Trim().ToUpperInvariant(),
            total,
            valuedAt,
            isPartial,
            ReadBoolean(root, "isStale", "IsStale", "stale", "Stale") == true,
            missing,
            ReadProviderTotals(root),
            "hoppa",
            ReadValuationRates(root, currency));
    }

    // Preserve the rates implicit in Hoppa's per-asset valuations. These are
    // estimates in one common currency, so clients can compare native balances.
    private static IReadOnlyList<PortfolioValuationRateResponse> ReadValuationRates(
        JsonElement root, string currency)
    {
        var rates = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase)
        {
            [currency.Trim().ToUpperInvariant()] = 1m
        };
        if (root.ValueKind == JsonValueKind.Object &&
            (root.TryGetProperty("balances", out var balances) ||
             root.TryGetProperty("Balances", out balances)) &&
            balances.ValueKind == JsonValueKind.Array)
        {
            foreach (var row in balances.EnumerateArray())
            {
                var symbol = ReadString(row, "assetCode", "AssetCode")?.Trim().ToUpperInvariant();
                var target = ReadString(row, "targetCurrency", "TargetCurrency");
                var balance = ReadDecimal(row, "balance", "Balance");
                var value = ReadDecimal(row, "estimatedValue", "EstimatedValue");
                if (string.IsNullOrEmpty(symbol) ||
                    !string.Equals(target?.Trim(), currency.Trim(), StringComparison.OrdinalIgnoreCase) ||
                    balance is null or 0 || value is null ||
                    Math.Sign(balance.Value) != Math.Sign(value.Value)) continue;
                var rate = value.Value / balance.Value;
                if (rate > 0) rates.TryAdd(symbol, rate);
            }
        }
        return rates.Select(pair => new PortfolioValuationRateResponse(pair.Key, pair.Value)).ToArray();
    }

    private static JsonElement Unwrap(JsonElement? payload)
    {
        if (payload is null || payload.Value.ValueKind != JsonValueKind.Object) return default;
        var current = payload.Value;
        foreach (var key in new[] { "data", "Data", "result", "Result", "portfolio", "Portfolio", "summary", "Summary" })
        {
            if (current.ValueKind == JsonValueKind.Object &&
                current.TryGetProperty(key, out var nested) &&
                nested.ValueKind == JsonValueKind.Object)
            {
                current = nested;
            }
        }
        return current;
    }

    private static string? ReadString(JsonElement root, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (root.ValueKind == JsonValueKind.Object &&
                root.TryGetProperty(key, out var value) &&
                value.ValueKind == JsonValueKind.String &&
                !string.IsNullOrWhiteSpace(value.GetString()))
            {
                return value.GetString();
            }
        }
        return null;
    }

    private static decimal? ReadDecimal(JsonElement root, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty(key, out var value)) continue;
            if (value.ValueKind == JsonValueKind.Number && value.TryGetDecimal(out var number)) return number;
            if (value.ValueKind == JsonValueKind.String && decimal.TryParse(
                    value.GetString(),
                    System.Globalization.NumberStyles.Number,
                    System.Globalization.CultureInfo.InvariantCulture,
                    out number)) return number;
        }
        return null;
    }

    private static DateTimeOffset? ReadDateTimeOffset(JsonElement root, params string[] keys)
    {
        var text = ReadString(root, keys);
        return DateTimeOffset.TryParse(text, out var value) ? value : null;
    }

    private static bool? ReadBoolean(JsonElement root, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty(key, out var value)) continue;
            if (value.ValueKind == JsonValueKind.True) return true;
            if (value.ValueKind == JsonValueKind.False) return false;
            if (value.ValueKind == JsonValueKind.String && bool.TryParse(value.GetString(), out var parsed)) return parsed;
        }
        return null;
    }

    private static IReadOnlyList<string> ReadStrings(JsonElement root, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty(key, out var value) ||
                value.ValueKind != JsonValueKind.Array) continue;
            return value.EnumerateArray()
                .Where(item => item.ValueKind == JsonValueKind.String)
                .Select(item => item.GetString()?.Trim().ToUpperInvariant() ?? string.Empty)
                .Where(item => !string.IsNullOrWhiteSpace(item))
                .Distinct(StringComparer.Ordinal)
                .ToArray();
        }
        return [];
    }

    private static IReadOnlyList<PortfolioProviderTotalResponse> ReadProviderTotals(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object ||
            (!root.TryGetProperty("providerTotals", out var totals) &&
             !root.TryGetProperty("ProviderTotals", out totals)) ||
            totals.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        return totals.EnumerateArray()
            .Where(item => item.ValueKind == JsonValueKind.Object)
            .Select(item => new PortfolioProviderTotalResponse(
                (ReadString(item, "provider", "Provider") ?? string.Empty).Trim().ToLowerInvariant(),
                ReadDecimal(item, "estimatedTotalAssets", "EstimatedTotalAssets", "total", "Total"),
                (ReadString(item, "currency", "Currency") ?? string.Empty).Trim().ToUpperInvariant(),
                ReadInt(item, "assetCount", "AssetCount") ?? 0,
                ReadBoolean(item, "isAvailable", "IsAvailable") != false,
                ReadStrings(item, "unpricedAssetCodes", "UnpricedAssetCodes")))
            .Where(item => !string.IsNullOrWhiteSpace(item.Provider))
            .ToArray();
    }

    private static int? ReadInt(JsonElement root, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty(key, out var value)) continue;
            if (value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var number)) return number;
            if (value.ValueKind == JsonValueKind.String && int.TryParse(value.GetString(), out number)) return number;
        }
        return null;
    }
}
