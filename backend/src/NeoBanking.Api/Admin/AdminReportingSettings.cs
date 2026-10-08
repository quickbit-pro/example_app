using System.Text.Json;

namespace NeoBanking.Api.Admin;

/// <summary>
/// Per-installation reporting settings, stored under "reporting" in the company
/// settings document. The time zone decides where a reporting day starts, so daily
/// figures match the brand's customers instead of UTC midnight.
/// </summary>
public static class AdminReportingSettings
{
    public const string SettingsKey = "reporting";
    public const string DefaultTimeZone = "UTC";

    /// <summary>Offered in the admin panel; any IANA id the server knows is accepted.</summary>
    public static readonly IReadOnlyList<string> SuggestedTimeZones =
    [
        "UTC", "Europe/London", "Europe/Berlin", "Europe/Ljubljana", "Europe/Istanbul", "Europe/Kyiv",
        "Asia/Dubai", "Asia/Singapore", "America/New_York", "America/Los_Angeles"
    ];

    public static string ReadTimeZone(string? settingsJson)
    {
        try
        {
            using var document = JsonDocument.Parse(string.IsNullOrWhiteSpace(settingsJson) ? "{}" : settingsJson);
            if (document.RootElement.ValueKind == JsonValueKind.Object &&
                document.RootElement.TryGetProperty(SettingsKey, out var reporting) &&
                reporting.ValueKind == JsonValueKind.Object &&
                reporting.TryGetProperty("timeZone", out var zone) &&
                zone.ValueKind == JsonValueKind.String &&
                TryResolve(zone.GetString(), out _))
            {
                return zone.GetString()!;
            }
        }
        catch (JsonException)
        {
            // A malformed legacy document keeps the UTC default.
        }

        return DefaultTimeZone;
    }

    public static bool TryResolve(string? id, out TimeZoneInfo timeZone)
    {
        timeZone = TimeZoneInfo.Utc;
        if (string.IsNullOrWhiteSpace(id) || id.Length > 64)
        {
            return false;
        }

        try
        {
            timeZone = TimeZoneInfo.FindSystemTimeZoneById(id.Trim());
            return true;
        }
        catch (Exception exception) when (exception is TimeZoneNotFoundException or InvalidTimeZoneException)
        {
            return false;
        }
    }

    public static TimeZoneInfo Resolve(string? id) => TryResolve(id, out var zone) ? zone : TimeZoneInfo.Utc;

    public static string WriteTimeZone(string? settingsJson, string timeZone)
    {
        Dictionary<string, JsonElement> settings;
        try
        {
            using var document = JsonDocument.Parse(string.IsNullOrWhiteSpace(settingsJson) ? "{}" : settingsJson);
            settings = document.RootElement.ValueKind == JsonValueKind.Object
                ? document.RootElement.EnumerateObject().ToDictionary(property => property.Name, property => property.Value.Clone(), StringComparer.Ordinal)
                : new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        }
        catch (JsonException)
        {
            settings = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        }

        settings[SettingsKey] = JsonSerializer.SerializeToElement(new { timeZone });
        return JsonSerializer.Serialize(settings);
    }
}
