#nullable enable

using System.Text.Json;
using System.Text.Json.Nodes;

namespace NeoBanking.Api.Tiers;

/// <summary>
/// The tiers a customer may see and choose.
/// </summary>
/// <remarks>
/// The provider's <c>GET /api/v2/tiers</c> answers for the whole company: since
/// 2026-06-11 it returns tiers for every account type, and it has always included
/// inactive tiers and hidden ones (<c>IsHidden</c>: "unavailable for public
/// selection or reserved for users with a linked invite code"). A customer is
/// offered only the active, public tiers of their own account type. The tier they
/// are already on is always kept, whatever its flags, so the app can still name it
/// and say what it includes.
/// </remarks>
public static class CustomerTierCatalog
{
    /// <summary>Same traversal as <c>CardLimitPolicy.FindTier</c>, so a tier this filter keeps is one that lookup finds.</summary>
    private static readonly string[] ContainerKeys = ["tiers", "Tiers", "items", "Items", "data", "Data", "result", "Result"];

    /// <summary>A blank account type, or one of these, marks a tier every account type may choose.</summary>
    private static readonly HashSet<string> AnyAccountType = new(StringComparer.OrdinalIgnoreCase) { "all", "any", "both" };

    public static string NormalizeAccountType(string? accountType) =>
        string.Equals(accountType?.Trim(), "business", StringComparison.OrdinalIgnoreCase)
            ? "business"
            : "personal";

    public static bool IsOffered(JsonElement tier, string accountType, int? currentTierId)
    {
        if (tier.ValueKind != JsonValueKind.Object) return false;
        if (currentTierId is not null && ReadInt(tier, "id", "Id", "tierId", "TierId") == currentTierId) return true;
        if (ReadBool(tier, "isHidden", "IsHidden") == true) return false;
        if (ReadBool(tier, "isActive", "IsActive") == false) return false;

        var tierAccountType = ReadString(tier, "accountType", "AccountType")?.Trim();
        return string.IsNullOrEmpty(tierAccountType) ||
               AnyAccountType.Contains(tierAccountType) ||
               string.Equals(tierAccountType, NormalizeAccountType(accountType), StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// A copy of <paramref name="payload"/> with every tier the customer is not offered
    /// removed. The envelope (<c>{ "Tiers": [...] }</c>, a bare array, a <c>data</c>
    /// wrapper) is kept as the provider sent it.
    /// </summary>
    public static JsonElement Filter(JsonElement payload, string accountType, int? currentTierId)
    {
        var root = JsonNode.Parse(payload.GetRawText());
        if (root is null) return payload.Clone();

        foreach (var list in TierLists(root))
        {
            for (var index = list.Count - 1; index >= 0; index--)
            {
                var entry = list[index];
                if (entry is JsonObject && IsOffered(ToElement(entry), accountType, currentTierId)) continue;
                list.RemoveAt(index);
            }
        }

        return ToElement(root);
    }

    private static IEnumerable<JsonArray> TierLists(JsonNode node)
    {
        switch (node)
        {
            case JsonArray array:
                yield return array;
                break;
            case JsonObject container:
                foreach (var key in ContainerKeys)
                {
                    if (container[key] is not { } nested) continue;
                    foreach (var list in TierLists(nested)) yield return list;
                }
                break;
        }
    }

    private static JsonElement ToElement(JsonNode node) => JsonSerializer.SerializeToElement(node);

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

    private static bool? ReadBool(JsonElement element, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (!element.TryGetProperty(key, out var value)) continue;
            switch (value.ValueKind)
            {
                case JsonValueKind.True:
                    return true;
                case JsonValueKind.False:
                    return false;
                case JsonValueKind.String when bool.TryParse(value.GetString(), out var parsed):
                    return parsed;
            }
        }

        return null;
    }

    private static string? ReadString(JsonElement element, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (element.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String)
            {
                return value.GetString();
            }
        }

        return null;
    }
}
