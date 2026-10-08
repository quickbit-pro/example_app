using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace NeoBanking.Api.Assistant;

/// <summary>Only coarse onboarding choices used to build editable starter questions in the client.</summary>
public sealed record AssistantPreferencesDto(string? City = null, string? CountryCode = null,
    string? ExpectedMonthlyVolume = null);

public static partial class AssistantPreferences
{
    private static readonly HashSet<string> MonthlyVolumeBands = new(StringComparer.Ordinal)
    {
        "0-1000", "1001-5000", "5001-15000", "15001-50000", "50001-100000", "100001+"
    };

    private static readonly Dictionary<string, string> CountryCodes = BuildCountryCodes();

    // GET /api/v2/users/{id} returns a flat UserDetailResponseV2 with City and Country.
    // Never recursively search a profile: e.g. a business, delivery address or another user is not home.
    public static AssistantPreferencesDto FromUserProfile(JsonElement profile)
    {
        if (profile.ValueKind != JsonValueKind.Object) return new();
        return new(NormalizeCity(String(profile, "City", "city")),
            NormalizeCountry(String(profile, "Country", "country")),
            NormalizeMonthlyVolume(String(profile, "ExpectedMonthlyVolume", "expectedMonthlyVolume")));
    }

    public static string? NormalizeMonthlyVolume(string? value) =>
        value is not null && MonthlyVolumeBands.Contains(value.Trim()) ? value.Trim() : null;

    private static string? NormalizeCity(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > 100) return null;
        try
        {
            var city = value.Trim().Normalize(NormalizationForm.FormC);
            if (!CityLabel().IsMatch(city) || !city.Any(char.IsLetter) ||
                AssistantInputPrivacy.ContainsSensitiveData(city)) return null;
            return city;
        }
        catch (Exception exception) when (exception is ArgumentException or RegexMatchTimeoutException)
        {
            return null;
        }
    }

    private static string? NormalizeCountry(string? value) => value is null
        ? null : CountryCodes.GetValueOrDefault(value.Trim().ToUpperInvariant());

    private static Dictionary<string, string> BuildCountryCodes()
    {
        var countries = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var culture in CultureInfo.GetCultures(CultureTypes.SpecificCultures))
        {
            var region = new RegionInfo(culture.Name);
            var twoLetter = region.TwoLetterISORegionName;
            if (twoLetter.Length != 2 || !twoLetter.All(char.IsAsciiLetter)) continue;
            countries[twoLetter] = twoLetter;
            countries[region.ThreeLetterISORegionName] = twoLetter;
        }
        return countries;
    }

    private static string? String(JsonElement profile, string pascalName, string camelName)
    {
        if (!profile.TryGetProperty(pascalName, out var value) && !profile.TryGetProperty(camelName, out value)) return null;
        return value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    }

    [GeneratedRegex(@"\A[\p{L}\p{M}\p{N} .,'’()\-]{1,100}\z", RegexOptions.CultureInvariant, 100)]
    private static partial Regex CityLabel();
}
