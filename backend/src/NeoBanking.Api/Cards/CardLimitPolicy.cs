#nullable enable

using System.Globalization;
using System.Text.Json;

namespace NeoBanking.Api.Cards;

/// <summary>Ceilings a customer may not exceed when setting their own card limits.</summary>
public sealed record CardLimitCaps(decimal? Daily, decimal? Weekly, decimal? Monthly, string Source)
{
    public static readonly CardLimitCaps None = new(null, null, null, "none");

    public bool HasAny => Daily.HasValue || Weekly.HasValue || Monthly.HasValue;
}

/// <summary>Limits the customer chose, kept on our side because the provider does not read them back.</summary>
public sealed record StoredCardLimits(decimal? Daily, decimal? Weekly, decimal? Monthly, string Currency, DateTimeOffset UpdatedAt);

/// <summary>
/// Card spending limits are customer-adjustable but capped by the tier: the
/// provider enforces the card type's ceilings, and we mirror that check so
/// the app can show the ceiling and refuse higher values before the call.
/// </summary>
public static class CardLimitPolicy
{
    private static readonly string[] DailyKeys =
    [
        "daily", "Daily", "daily_limit", "dailyLimit", "DailyLimit", "daily_spend", "dailySpend", "DailySpend",
        "dailySpendLimit", "DailySpendLimit", "daily_spend_limit", "dailyTransactionLimit", "DailyTransactionLimit",
    ];

    private static readonly string[] WeeklyKeys =
    [
        "weekly", "Weekly", "weekly_limit", "weeklyLimit", "WeeklyLimit", "weekly_spend", "weeklySpend", "WeeklySpend",
        "weeklySpendLimit", "WeeklySpendLimit", "weekly_spend_limit",
    ];

    private static readonly string[] MonthlyKeys =
    [
        "monthly", "Monthly", "monthly_limit", "monthlyLimit", "MonthlyLimit", "monthly_spend", "monthlySpend", "MonthlySpend",
        "monthlySpendLimit", "MonthlySpendLimit", "monthly_spend_limit", "monthlyTransactionLimit", "MonthlyTransactionLimit",
    ];

    private static readonly string[] LimitContainers = ["limits", "Limits", "spendingLimits", "SpendingLimits", "caps", "Caps"];

    private static readonly string[] Wrappers = ["data", "Data", "result", "Result", "cardTypeTier", "CardTypeTier", "cardType", "CardType", "tier", "Tier"];

    /// <summary>
    /// Card-type ceilings win over tier-wide ones; a tier without either
    /// leaves the provider as the only guard.
    /// </summary>
    public static CardLimitCaps ResolveCaps(JsonElement? cardTierPayload, JsonElement? tierPayload)
    {
        var fromCardType = ReadCaps(FindCardTypeElement(cardTierPayload), "card_type");
        if (fromCardType.HasAny)
        {
            return fromCardType;
        }

        var fromTier = ReadCaps(Unwrap(tierPayload), "tier");
        return fromTier.HasAny ? fromTier : CardLimitCaps.None;
    }

    /// <summary>
    /// `GET tiers/card-tier/{tierId}` lists every card-type tier of a tier;
    /// pick the one for this card by its card-type-tier id, else its card
    /// type, else the only entry.
    /// </summary>
    public static JsonElement? FindCardTypeTier(JsonElement? payload, int? cardTypeTierId, int? cardTypeId)
    {
        if (payload is null) return null;
        var entries = new List<JsonElement>();
        var root = Unwrap(payload);
        if (root is not null)
        {
            foreach (var key in new[] { "cardTypeTiers", "CardTypeTiers", "items", "Items" })
            {
                if (root.Value.TryGetProperty(key, out var list) && list.ValueKind == JsonValueKind.Array)
                {
                    entries.AddRange(list.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.Object));
                }
            }

            if (entries.Count == 0 && (root.Value.TryGetProperty("cardType", out _) || root.Value.TryGetProperty("CardType", out _)))
            {
                entries.Add(root.Value);
            }
        }
        else if (payload.Value.ValueKind == JsonValueKind.Array)
        {
            entries.AddRange(payload.Value.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.Object));
        }

        if (entries.Count == 0) return null;
        if (cardTypeTierId is > 0)
        {
            var byTierRow = entries.FirstOrDefault(entry =>
                ReadInt(entry, "cardTypeSecondaryId", "CardTypeSecondaryId", "id", "Id", "cardTypeTierId", "CardTypeTierId") == cardTypeTierId);
            if (byTierRow.ValueKind == JsonValueKind.Object) return byTierRow;
        }

        if (cardTypeId is > 0)
        {
            var byCardType = entries.FirstOrDefault(entry => ReadInt(entry, "cardTypeId", "CardTypeId") == cardTypeId);
            if (byCardType.ValueKind == JsonValueKind.Object) return byCardType;
        }

        return entries.Count == 1 ? entries[0] : null;
    }

    /// <summary>Finds the tier with the given id inside a tiers list payload.</summary>
    public static JsonElement? FindTier(JsonElement? tiersPayload, int tierId)
    {
        if (tiersPayload is null) return null;
        foreach (var element in EnumerateObjects(tiersPayload.Value))
        {
            if (ReadInt(element, "id", "Id", "tierId", "TierId") == tierId)
            {
                return element;
            }
        }

        return null;
    }

    public static string? ValidationError(decimal? daily, decimal? weekly, decimal? monthly, CardLimitCaps caps)
    {
        foreach (var (name, value, cap) in new[]
                 {
                     ("Daily limit", daily, caps.Daily),
                     ("Weekly limit", weekly, caps.Weekly),
                     ("Monthly limit", monthly, caps.Monthly),
                 })
        {
            if (value is null) continue;
            if (value < 0) return $"{name} cannot be negative.";
            if (cap.HasValue && value > cap.Value)
            {
                return $"{name} cannot exceed your tier's ceiling of {Format(cap.Value)}.";
            }
        }

        if (daily.HasValue && weekly.HasValue && daily > weekly) return "Daily limit cannot exceed the weekly limit.";
        if (weekly.HasValue && monthly.HasValue && weekly > monthly) return "Weekly limit cannot exceed the monthly limit.";
        if (daily.HasValue && monthly.HasValue && daily > monthly) return "Daily limit cannot exceed the monthly limit.";
        return null;
    }

    public static string Format(decimal value) => value.ToString("#,##0.##", CultureInfo.InvariantCulture);

    private static CardLimitCaps ReadCaps(JsonElement? element, string source)
    {
        if (element is null || element.Value.ValueKind != JsonValueKind.Object) return CardLimitCaps.None;
        var roots = new List<JsonElement> { element.Value };
        foreach (var container in LimitContainers)
        {
            if (element.Value.TryGetProperty(container, out var nested) && nested.ValueKind == JsonValueKind.Object)
            {
                roots.Insert(0, nested);
            }
        }

        return new CardLimitCaps(
            ReadDecimal(roots, DailyKeys),
            ReadDecimal(roots, WeeklyKeys),
            ReadDecimal(roots, MonthlyKeys),
            source);
    }

    private static JsonElement? FindCardTypeElement(JsonElement? payload)
    {
        var root = Unwrap(payload);
        if (root is null) return null;
        foreach (var key in new[] { "cardTypeTier", "CardTypeTier" })
        {
            if (root.Value.TryGetProperty(key, out var wrapper) && wrapper.ValueKind == JsonValueKind.Object)
            {
                root = wrapper;
            }
        }

        foreach (var key in new[] { "cardType", "CardType" })
        {
            if (root.Value.TryGetProperty(key, out var nested) && nested.ValueKind == JsonValueKind.Object)
            {
                return nested;
            }
        }

        return root;
    }

    private static JsonElement? Unwrap(JsonElement? payload)
    {
        if (payload is null || payload.Value.ValueKind != JsonValueKind.Object) return null;
        var current = payload.Value;
        foreach (var key in new[] { "data", "Data", "result", "Result" })
        {
            if (current.TryGetProperty(key, out var nested) && nested.ValueKind == JsonValueKind.Object)
            {
                current = nested;
            }
        }

        return current;
    }

    private static IEnumerable<JsonElement> EnumerateObjects(JsonElement payload)
    {
        switch (payload.ValueKind)
        {
            case JsonValueKind.Array:
                foreach (var item in payload.EnumerateArray())
                {
                    if (item.ValueKind == JsonValueKind.Object) yield return item;
                }
                break;
            case JsonValueKind.Object:
                foreach (var key in new[] { "tiers", "Tiers", "items", "Items", "data", "Data", "result", "Result" })
                {
                    if (payload.TryGetProperty(key, out var nested))
                    {
                        foreach (var item in EnumerateObjects(nested)) yield return item;
                    }
                }
                break;
        }
    }

    private static int? ReadInt(JsonElement element, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (!element.TryGetProperty(key, out var value)) continue;
            if (value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var number)) return number;
            if (value.ValueKind == JsonValueKind.String && int.TryParse(value.GetString(), out var parsed)) return parsed;
        }

        return null;
    }

    private static decimal? ReadDecimal(IReadOnlyList<JsonElement> roots, string[] keys)
    {
        foreach (var root in roots)
        {
            foreach (var key in keys)
            {
                if (!root.TryGetProperty(key, out var value)) continue;
                switch (value.ValueKind)
                {
                    case JsonValueKind.Number when value.TryGetDecimal(out var number):
                        return number > 0 ? number : null;
                    case JsonValueKind.String when decimal.TryParse(value.GetString(), NumberStyles.Number, CultureInfo.InvariantCulture, out var parsed):
                        return parsed > 0 ? parsed : null;
                }
            }
        }

        return null;
    }

    public static string StorageKey(string cardId) => cardId.Trim();
}
