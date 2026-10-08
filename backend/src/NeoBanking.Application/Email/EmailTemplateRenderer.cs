using System.Net;
using System.Text.RegularExpressions;

namespace NeoBanking.Application.Email;

public sealed record RenderedEmail(string Subject, string HtmlBody, string TextBody);

/// <summary>
/// Minimal mustache-style renderer. Placeholders look like <c>{{code}}</c>.
/// Values are HTML-encoded inside the HTML body and inserted verbatim into
/// the subject and plain-text body.
/// </summary>
public static partial class EmailTemplateRenderer
{
    [GeneratedRegex(@"\{\{\s*([A-Za-z0-9_]+)\s*\}\}", RegexOptions.CultureInvariant)]
    private static partial Regex PlaceholderPattern();

    public static RenderedEmail Render(
        string subject,
        string htmlBody,
        string textBody,
        IReadOnlyDictionary<string, string> values)
    {
        var lookup = new Dictionary<string, string>(values, StringComparer.OrdinalIgnoreCase);

        return new RenderedEmail(
            Replace(subject, lookup, encodeHtml: false).ReplaceLineEndings(" ").Trim(),
            Replace(htmlBody, lookup, encodeHtml: true),
            Replace(textBody, lookup, encodeHtml: false));
    }

    public static IReadOnlyCollection<string> FindPlaceholders(params string?[] sources)
    {
        var found = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var source in sources)
        {
            if (string.IsNullOrEmpty(source))
            {
                continue;
            }

            foreach (Match match in PlaceholderPattern().Matches(source))
            {
                found.Add(match.Groups[1].Value);
            }
        }

        return found;
    }

    private static string Replace(string template, Dictionary<string, string> values, bool encodeHtml)
    {
        if (string.IsNullOrEmpty(template))
        {
            return string.Empty;
        }

        return PlaceholderPattern().Replace(template, match =>
        {
            if (!values.TryGetValue(match.Groups[1].Value, out var value))
            {
                return string.Empty;
            }

            return encodeHtml ? WebUtility.HtmlEncode(value) : value;
        });
    }
}
