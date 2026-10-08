using System.Text.Json;

namespace NeoBanking.Api.Cards;

public sealed record CardControlCapabilitiesResponse(
    bool CanFreeze,
    bool CanRevealSecureData,
    bool CanSetPin,
    bool CanUpdateLimits,
    bool CanMerchantLock,
    bool CanControlOnlinePayments,
    bool CanControlContactless,
    bool CanControlAtm,
    bool CanControlInternational,
    bool IsMerchantLocked,
    string? LockedMerchantName,
    string Source,
    IReadOnlyList<string> SupportedActions,
    JsonElement? Limits)
{
    /// <summary>
    /// The issuer's auto-lock switch ("Auto freeze" in the app): Hoppa
    /// freezes the card again by itself ten minutes after it is unfrozen
    /// while this is on. Read by <see cref="HoppaCardAutoFreeze"/> from the
    /// same card payload the capabilities come from.
    /// </summary>
    public bool AutoFreezeEnabled { get; init; }

    /// <summary>When the current unfreeze window ends; null while frozen or off.</summary>
    public DateTimeOffset? AutoFreezeActiveUntil { get; init; }
}

public static class CardControlCapabilitiesMapper
{
    public static CardControlCapabilitiesResponse Map(JsonElement? payload)
    {
        var root = Unwrap(payload);
        var capabilityRoots = new List<JsonElement>();
        AddObject(capabilityRoots, root);
        foreach (var key in new[]
                 {
                     "capabilities", "Capabilities", "controls", "Controls",
                     "cardControls", "CardControls", "cardTypeMetadata", "CardTypeMetadata",
                     "cardProduct", "CardProduct"
                 })
        {
            if (TryProperty(root, key, out var nested) && nested.ValueKind == JsonValueKind.Object)
            {
                capabilityRoots.Add(nested);
            }
        }

        var actions = ReadActions(capabilityRoots);
        bool Supports(string action, params string[] booleanKeys) =>
            actions.Contains(NormalizeAction(action)) ||
            booleanKeys.Any(key => ReadBoolean(capabilityRoots, key) == true);

        var canControlOnline = Supports(
            "online_payments",
            "supportsOnlinePayments", "onlinePaymentsSupported", "canControlOnlinePayments");
        var canControlContactless = Supports(
            "contactless",
            "supportsContactless", "contactlessSupported", "canControlContactless");
        var canControlAtm = Supports(
            "atm",
            "supportsAtmControls", "atmControlsSupported", "canControlAtm");
        var canControlInternational = Supports(
            "international",
            "supportsInternationalControls", "internationalControlsSupported", "canControlInternational");

        var limits = ReadObject(capabilityRoots, "limits", "Limits", "currentLimits", "CurrentLimits");
        return new CardControlCapabilitiesResponse(
            CanFreeze: Supports("freeze", "supportsFreeze", "canFreeze"),
            CanRevealSecureData: Supports(
                "reveal_secure_data", "supportsSecureData", "canRevealSecureData", "supportsWidget"),
            CanSetPin: Supports("set_pin", "supportsPin", "pinSupported", "canSetPin"),
            CanUpdateLimits: Supports(
                "limits", "supportsLimits", "limitsSupported", "canUpdateLimits"),
            CanMerchantLock: Supports(
                "merchant_lock", "supportsMerchantLock", "merchantLockSupported", "canMerchantLock"),
            CanControlOnlinePayments: canControlOnline,
            CanControlContactless: canControlContactless,
            CanControlAtm: canControlAtm,
            CanControlInternational: canControlInternational,
            IsMerchantLocked: ReadBoolean(
                capabilityRoots, "isMerchantLocked", "merchantLocked", "MerchantLocked") == true,
            LockedMerchantName: ReadString(
                capabilityRoots, "lockedMerchantName", "merchantLockName", "merchantName"),
            Source: "hoppa-card-metadata",
            SupportedActions: actions.Order(StringComparer.Ordinal).ToArray(),
            Limits: limits);
    }

    private static JsonElement Unwrap(JsonElement? payload)
    {
        if (payload is null || payload.Value.ValueKind != JsonValueKind.Object)
        {
            return default;
        }

        var current = payload.Value;
        foreach (var key in new[] { "data", "Data", "result", "Result", "card", "Card" })
        {
            if (TryProperty(current, key, out var nested) && nested.ValueKind == JsonValueKind.Object)
            {
                current = nested;
            }
        }

        return current;
    }

    private static HashSet<string> ReadActions(IReadOnlyList<JsonElement> roots)
    {
        var actions = new HashSet<string>(StringComparer.Ordinal);
        foreach (var root in roots)
        {
            foreach (var key in new[] { "supportedActions", "SupportedActions", "actions", "Actions" })
            {
                if (!TryProperty(root, key, out var value)) continue;
                if (value.ValueKind == JsonValueKind.Array)
                {
                    foreach (var item in value.EnumerateArray())
                    {
                        if (item.ValueKind == JsonValueKind.String)
                        {
                            AddAction(actions, item.GetString());
                        }
                    }
                }
                else if (value.ValueKind == JsonValueKind.Object)
                {
                    foreach (var property in value.EnumerateObject())
                    {
                        if (AsBoolean(property.Value) == true)
                        {
                            AddAction(actions, property.Name);
                        }
                    }
                }
            }
        }

        return actions;
    }

    private static void AddAction(ISet<string> actions, string? value)
    {
        var normalized = NormalizeAction(value);
        if (!string.IsNullOrWhiteSpace(normalized)) actions.Add(normalized);
    }

    private static string NormalizeAction(string? value)
    {
        var normalized = string.Concat((value ?? string.Empty)
                .Trim()
                .Select(character => char.IsLetterOrDigit(character) ? char.ToLowerInvariant(character) : '_'))
            .Replace("__", "_", StringComparison.Ordinal)
            .Trim('_');
        return normalized.Replace("_", string.Empty, StringComparison.Ordinal) switch
        {
            "updatelimits" or "spendinglimits" => "limits",
            "merchantlock" => "merchant_lock",
            "setpin" or "updatepin" => "set_pin",
            "revealsecuredata" or "securedata" or "widget" => "reveal_secure_data",
            "onlinepayments" => "online_payments",
            _ => normalized
        };
    }

    private static bool? ReadBoolean(IReadOnlyList<JsonElement> roots, params string[] keys)
    {
        foreach (var root in roots)
        {
            foreach (var key in keys)
            {
                if (TryProperty(root, key, out var value))
                {
                    var parsed = AsBoolean(value);
                    if (parsed is not null) return parsed;
                }
            }
        }

        return null;
    }

    private static bool? AsBoolean(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        JsonValueKind.Number when value.TryGetInt32(out var number) => number != 0,
        JsonValueKind.String when bool.TryParse(value.GetString(), out var boolean) => boolean,
        JsonValueKind.String when value.GetString() is "1" or "yes" or "enabled" => true,
        JsonValueKind.String when value.GetString() is "0" or "no" or "disabled" => false,
        _ => null
    };

    private static string? ReadString(IReadOnlyList<JsonElement> roots, params string[] keys)
    {
        foreach (var root in roots)
        {
            foreach (var key in keys)
            {
                if (TryProperty(root, key, out var value) && value.ValueKind == JsonValueKind.String)
                {
                    var text = value.GetString()?.Trim();
                    if (!string.IsNullOrWhiteSpace(text)) return text;
                }
            }
        }

        return null;
    }

    private static JsonElement? ReadObject(IReadOnlyList<JsonElement> roots, params string[] keys)
    {
        foreach (var root in roots)
        {
            foreach (var key in keys)
            {
                if (TryProperty(root, key, out var value) && value.ValueKind == JsonValueKind.Object)
                {
                    return value.Clone();
                }
            }
        }

        return null;
    }

    private static void AddObject(ICollection<JsonElement> values, JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object) values.Add(value);
    }

    private static bool TryProperty(JsonElement value, string key, out JsonElement property)
    {
        if (value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out property))
        {
            return true;
        }

        property = default;
        return false;
    }
}
