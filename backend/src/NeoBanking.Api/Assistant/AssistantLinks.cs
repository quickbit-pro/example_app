using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace NeoBanking.Api.Assistant;

public static partial class AssistantLinks
{
    public static IReadOnlyList<AssistantActionDto> BuildActions(JsonElement root, bool providerNeutral = false)
    {
        var result = new List<AssistantActionDto>();
        if (!root.TryGetProperty("searches", out var searches) || searches.ValueKind != JsonValueKind.Array)
            return result;
        foreach (var search in searches.EnumerateArray().Take(3))
        {
            if (search.ValueKind != JsonValueKind.Object ||
                !search.TryGetProperty("kind", out var kind) || kind.ValueKind != JsonValueKind.String ||
                !search.TryGetProperty("query", out var query) || query.ValueKind != JsonValueKind.String)
                continue;
            var text = query.GetString()!.Trim();
            if (text.Length is < 2 or > 160 || !SafeSearch().IsMatch(text)) continue;
            var encoded = Uri.EscapeDataString(text);
            var action = kind.GetString() switch
            {
                "flights" => new AssistantActionDto("Search flights", "https://www.google.com/travel/flights?q=" + encoded, "flights"),
                "hotels" => new AssistantActionDto("Search hotels", (providerNeutral
                    ? "https://www.google.com/travel/hotels?q=" : "https://www.booking.com/searchresults.html?ss=") + encoded, "hotels"),
                "maps" => new AssistantActionDto("Explore places", "https://www.google.com/maps/search/?api=1&query=" + encoded, "maps"),
                _ => null
            };
            if (action is not null && result.All(existing => existing.Url != action.Url)) result.Add(action);
        }
        return result;
    }

    public static IReadOnlyList<AssistantSourceDto> ReadSources(JsonElement message)
    {
        var sources = new List<AssistantSourceDto>();
        if (!message.TryGetProperty("annotations", out var annotations) || annotations.ValueKind != JsonValueKind.Array)
            return sources;
        foreach (var annotation in annotations.EnumerateArray())
        {
            if (sources.Count == 5) break;
            if (annotation.ValueKind != JsonValueKind.Object ||
                !annotation.TryGetProperty("type", out var type) || type.ValueKind != JsonValueKind.String || type.GetString() != "url_citation" ||
                !annotation.TryGetProperty("url_citation", out var citation) || citation.ValueKind != JsonValueKind.Object ||
                !citation.TryGetProperty("url", out var url) || url.ValueKind != JsonValueKind.String ||
                !TryPublicHttpsUrl(url.GetString(), out var safeUrl)) continue;
            var title = citation.TryGetProperty("title", out var titleValue) && titleValue.ValueKind == JsonValueKind.String
                ? titleValue.GetString()?.Trim() : null;
            if (string.IsNullOrEmpty(title) || title.Length > 160 || title.Any(char.IsControl))
                title = new Uri(safeUrl).Host;
            if (sources.All(source => source.Url != safeUrl)) sources.Add(new AssistantSourceDto(title, safeUrl));
        }
        return sources;
    }

    public static bool TryPublicHttpsUrl(string? value, out string safeUrl)
    {
        safeUrl = string.Empty;
        if (value is null || value.Length > 2048 || value.Any(char.IsControl) || value.Contains('\\') ||
            !Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
            !uri.IsDefaultPort || !string.IsNullOrEmpty(uri.UserInfo) || uri.HostNameType != UriHostNameType.Dns)
            return false;
        var host = uri.IdnHost.TrimEnd('.').ToLowerInvariant();
        if (IPAddress.TryParse(host, out _) || !PublicHost().IsMatch(host) ||
            new[] { "localhost", "local", "internal", "invalid", "test", "example", "onion", "lan", "home", "arpa" }
                .Any(suffix => host == suffix || host.EndsWith("." + suffix, StringComparison.Ordinal))) return false;
        safeUrl = uri.AbsoluteUri;
        return true;
    }

    [GeneratedRegex(@"^[\p{L}\p{M}\p{N} ',()\-]+$", RegexOptions.CultureInvariant)]
    private static partial Regex SafeSearch();
    [GeneratedRegex(@"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$", RegexOptions.CultureInvariant)]
    private static partial Regex PublicHost();
}
