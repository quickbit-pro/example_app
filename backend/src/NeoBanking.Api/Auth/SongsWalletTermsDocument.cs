using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace NeoBanking.Api.Auth;

/// <summary>Resolve Songswallet's Wix-hosted legal document without running website scripts.</summary>
internal static class SongsWalletTermsDocument
{
    private static readonly TimeSpan RegexTimeout = TimeSpan.FromSeconds(1);

    private static bool IsPublicHttps(Uri uri) => uri.Scheme == "https" && uri.IsDefaultPort &&
        string.IsNullOrEmpty(uri.UserInfo) && string.IsNullOrEmpty(uri.Fragment);

    public static bool IsTermsPage(Uri uri) => IsPublicHttps(uri) &&
        uri.Host is "songswallet.com" or "www.songswallet.com" &&
        uri.AbsolutePath.TrimEnd('/') is "/termsandconditions" or "/en/termsandconditions";

    public static bool IsMetadataUrl(Uri uri) => IsPublicHttps(uri) &&
        uri.Host == "siteassets.parastorage.com" && uri.AbsolutePath == "/pages/pages/thunderbolt";

    public static bool IsDocumentUrl(Uri uri) => IsPublicHttps(uri) &&
        uri.Host == "www-songswallet-com.filesusr.com" && string.IsNullOrEmpty(uri.Query) &&
        Regex.IsMatch(uri.AbsolutePath, @"^/html/e76d6e_[a-f0-9]{32}\.html$", RegexOptions.None, RegexTimeout);

    public static Uri MetadataUrl(string html)
    {
        var urls = new HashSet<string>(StringComparer.Ordinal);
        foreach (Match tag in Regex.Matches(html, @"<link\b[^>]*>", RegexOptions.IgnoreCase, RegexTimeout))
        {
            var attributes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (Match attribute in Regex.Matches(tag.Value,
                """(?<name>[\w-]+)\s*=\s*(?<quote>["'])(?<value>.*?)\k<quote>""",
                RegexOptions.Singleline, RegexTimeout))
                attributes[attribute.Groups["name"].Value] = WebUtility.HtmlDecode(attribute.Groups["value"].Value);
            if (attributes.TryGetValue("id", out var id) && id.StartsWith("features_", StringComparison.Ordinal) &&
                id != "features_masterPage" && attributes.TryGetValue("href", out var href))
                urls.Add(href);
        }
        if (urls.Count != 1 || !Uri.TryCreate(urls.Single(), UriKind.Absolute, out var uri) || !IsMetadataUrl(uri))
            throw new InvalidDataException("Terms page has no unambiguous supported document metadata.");
        return uri;
    }

    public static Uri DocumentUrl(byte[] metadata)
    {
        try
        {
            using var json = JsonDocument.Parse(metadata);
            var components = json.RootElement.GetProperty("props").GetProperty("render").GetProperty("compProps");
            var urls = components.EnumerateObject()
                .Where(x => x.Value.ValueKind == JsonValueKind.Object)
                .Select(x => x.Value.TryGetProperty("url", out var value) && value.ValueKind == JsonValueKind.String
                    ? value.GetString() : null)
                .Where(x => Uri.TryCreate(x, UriKind.Absolute, out var uri) && IsDocumentUrl(uri))
                .Distinct(StringComparer.Ordinal).ToArray();
            if (urls.Length != 1) throw new InvalidDataException("Terms page has no unambiguous supported legal embed.");
            return new Uri(urls[0]!, UriKind.Absolute);
        }
        catch (Exception error) when (error is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            throw new InvalidDataException("Invalid Terms document metadata.", error);
        }
    }
}
