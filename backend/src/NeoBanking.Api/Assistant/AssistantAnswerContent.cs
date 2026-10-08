using System.Text.Json;
using System.Text.RegularExpressions;

namespace NeoBanking.Api.Assistant;

/// <summary>Accepts bounded inert recommendation text and composes the legacy history representation.</summary>
internal static partial class AssistantAnswerContent
{
    private const int MaxTotalCharacters = 2400;

    public static bool TryRead(JsonElement root, out AssistantAnswerDto? answer, out string reply,
        bool recommendationLinks = false, IReadOnlyList<AssistantSourceDto>? sources = null)
    {
        answer = null;
        reply = string.Empty;
        if (!root.TryGetProperty("answer", out var value) || value.ValueKind == JsonValueKind.Null)
            return TryText(root, "reply", 2500, out reply);

        // A malformed new contract must not be hidden by an unrelated fallback reply.
        if (!HasOnlyUniqueProperties(value, ["title", "summary", "options", "nextStep"]) ||
            !TryText(value, "title", 80, out var title) ||
            !TryText(value, "summary", 240, out var summary) ||
            !TryOptionalText(value, "nextStep", 200, out var nextStep) ||
            !value.TryGetProperty("options", out var optionValues) || optionValues.ValueKind != JsonValueKind.Array ||
            optionValues.GetArrayLength() > 3) return false;

        var total = title.Length + summary.Length + (nextStep?.Length ?? 0);
        List<AssistantAnswerOptionDto> options = [];
        foreach (var option in optionValues.EnumerateArray())
        {
            if (!HasOnlyUniqueProperties(option, recommendationLinks
                    ? ["title", "highlights", "details", "sourceUrl"] : ["title", "highlights", "details"]) ||
                !TryText(option, "title", 80, out var optionTitle) ||
                !TryOptionalText(option, "details", 600, out var details) ||
                !option.TryGetProperty("highlights", out var highlightValues) ||
                highlightValues.ValueKind != JsonValueKind.Array || highlightValues.GetArrayLength() is < 1 or > 2)
                return false;

            List<string> highlights = [];
            foreach (var highlight in highlightValues.EnumerateArray())
            {
                if (!TryText(highlight, 160, out var text)) return false;
                highlights.Add(text);
                total += text.Length;
            }
            // A model-selected URL is only a reference to a returned search citation.
            // Never turn an uncorroborated URL (even on a known merchant) into a link.
            AssistantSourceDto? source = null;
            if (recommendationLinks && option.TryGetProperty("sourceUrl", out var sourceUrl) &&
                sourceUrl.ValueKind == JsonValueKind.String &&
                AssistantLinks.TryPublicHttpsUrl(sourceUrl.GetString(), out var safeUrl))
                source = sources?.FirstOrDefault(candidate => candidate.Url == safeUrl);
            options.Add(new AssistantAnswerOptionDto(optionTitle, highlights, details, source));
            total += optionTitle.Length + (details?.Length ?? 0);
        }

        if (total > MaxTotalCharacters) return false;
        answer = new AssistantAnswerDto(title, summary, options, nextStep);
        reply = ComposeReply(answer);
        return true;
    }

    private static string ComposeReply(AssistantAnswerDto answer)
    {
        List<string> blocks = [answer.Title, answer.Summary];
        foreach (var option in answer.Options)
        {
            var block = option.Title + "\n" + string.Join("\n", option.Highlights.Select(highlight => "• " + highlight));
            if (option.Details is { } details) block += "\n" + details;
            blocks.Add(block);
        }
        if (answer.NextStep is { } nextStep) blocks.Add(nextStep);
        return string.Join("\n\n", blocks);
    }

    private static bool HasOnlyUniqueProperties(JsonElement value, string[] allowed)
    {
        if (value.ValueKind != JsonValueKind.Object) return false;
        HashSet<string> seen = [];
        return value.EnumerateObject().All(property => allowed.Contains(property.Name, StringComparer.Ordinal) && seen.Add(property.Name));
    }

    private static bool TryOptionalText(JsonElement value, string key, int max, out string? text)
    {
        text = null;
        if (!value.TryGetProperty(key, out var field) || field.ValueKind == JsonValueKind.Null) return true;
        if (!TryText(field, max, out var parsed)) return false;
        text = parsed;
        return true;
    }

    private static bool TryText(JsonElement value, string key, int max, out string text)
    {
        text = string.Empty;
        return value.TryGetProperty(key, out var field) && TryText(field, max, out text);
    }

    private static bool TryText(JsonElement value, int max, out string text)
    {
        text = string.Empty;
        if (value.ValueKind != JsonValueKind.String) return false;
        text = value.GetString()!.Trim();
        return text.Length >= 1 && text.Length <= max &&
            !text.Any(c => char.IsControl(c) && c is not '\n' and not '\r' and not '\t') && !ProseUrl().IsMatch(text);
    }

    [GeneratedRegex(@"(?:[a-z][a-z0-9+.-]*://|www\.|\]\s*\(|<\s*a\b)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex ProseUrl();
}
