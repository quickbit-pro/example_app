using System.Text.Json;

namespace NeoBanking.Api.Cards;

/// <summary>
/// The issuer's auto-lock switch, which the app calls "Auto freeze". Hoppa
/// freezes the card again by itself ten minutes after it is unfrozen; this
/// backend only reads and forwards the on/off state, it never freezes
/// anything.
///
/// Contract (staging.hoppa.global/scalar, tag cards):
/// <c>PUT /api/v2/cards/{cardId}/auto-lock?userId=</c> with <c>{ "Enabled": bool }</c>
/// answers <c>{ Success, Message, AutoLockEnabled, AutoLockActiveUntil }</c>;
/// <c>GET /api/v2/cards/{cardId}</c> carries the same <c>AutoLockEnabled</c>
/// and <c>AutoLockActiveUntil</c> fields.
/// </summary>
public static class HoppaCardAutoFreeze
{
    /// <summary>Relative to <c>/api/v2/</c>, like the other card routes.</summary>
    public static string SettingPath(string cardIdSegment) => $"cards/{cardIdSegment}/auto-lock";

    private static readonly string[] EnabledKeys = { "autoLockEnabled", "AutoLockEnabled" };
    private static readonly string[] ActiveUntilKeys = { "autoLockActiveUntil", "AutoLockActiveUntil" };

    /// <summary>The switch as the issuer reports it; null when the payload does not say.</summary>
    public static bool? ReadEnabled(JsonElement? payload)
    {
        var root = Unwrap(payload);
        if (root.ValueKind != JsonValueKind.Object) return null;
        foreach (var key in EnabledKeys)
        {
            if (root.TryGetProperty(key, out var value))
            {
                var parsed = AsBoolean(value);
                if (parsed is not null) return parsed;
            }
        }

        return null;
    }

    /// <summary>When the current unfreeze runs out and the issuer freezes the card again; null while frozen or off.</summary>
    public static DateTimeOffset? ReadActiveUntil(JsonElement? payload)
    {
        var root = Unwrap(payload);
        if (root.ValueKind != JsonValueKind.Object) return null;
        foreach (var key in ActiveUntilKeys)
        {
            if (root.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String &&
                value.TryGetDateTimeOffset(out var parsed))
            {
                return parsed;
            }
        }

        return null;
    }

    public static string? ReadMessage(JsonElement? payload)
    {
        var root = Unwrap(payload);
        if (root.ValueKind != JsonValueKind.Object) return null;
        foreach (var key in new[] { "message", "Message" })
        {
            if (root.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String)
            {
                var text = value.GetString()?.Trim();
                if (!string.IsNullOrWhiteSpace(text)) return text;
            }
        }

        return null;
    }

    private static JsonElement Unwrap(JsonElement? payload)
    {
        if (payload is null || payload.Value.ValueKind != JsonValueKind.Object) return default;
        var current = payload.Value;
        foreach (var key in new[] { "data", "Data", "result", "Result", "card", "Card" })
        {
            if (current.TryGetProperty(key, out var nested) && nested.ValueKind == JsonValueKind.Object)
            {
                current = nested;
            }
        }

        return current;
    }

    private static bool? AsBoolean(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        JsonValueKind.Number when value.TryGetInt32(out var number) => number != 0,
        JsonValueKind.String when bool.TryParse(value.GetString(), out var boolean) => boolean,
        _ => null
    };
}
