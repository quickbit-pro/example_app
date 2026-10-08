using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace NeoBanking.Api.Assistant;

/// <summary>Local detection of recognizable credentials. Never logs, stores or returns matched text.</summary>
public static partial class AssistantInputPrivacy
{
    // Known registry lengths keep flight numbers followed by prose from looking like IBANs.
    // Other country prefixes still require the full IBAN shape and mod-97 checksum.
    private static readonly Dictionary<string, int> IbanLengths =
        ("AD24 AE23 AL28 AT20 AZ28 BA20 BE16 BG22 BH22 BR29 BY28 CH21 CR22 CY28 CZ24 DE22 " +
         "DK18 DO28 EE20 EG29 ES24 FI18 FO18 FR27 GB22 GE22 GI23 GL18 GR27 GT28 HR21 HU28 " +
         "IE22 IL23 IQ23 IS26 IT27 JO30 KW30 KZ20 LB28 LC32 LI21 LT20 LU20 LV21 MC27 MD24 " +
         "ME22 MK19 MR27 MT31 MU30 NL18 NO15 PK24 PL28 PS29 PT25 QA29 RO24 RS22 SA24 SC31 " +
         "SE24 SI19 SK24 SM27 ST25 SV28 TL23 TN24 TR26 UA29 VA22 VG24 XK20")
        .Split(' ').ToDictionary(entry => entry[..2], entry => int.Parse(entry[2..], CultureInfo.InvariantCulture));

    private static readonly HashSet<string> PasswordStatuses = new(StringComparer.OrdinalIgnoreCase)
    {
        "incorrect", "wrong", "invalid", "expired", "required", "missing", "forgotten", "reset", "changed",
        "blocked", "locked", "secure", "safe", "strong", "weak", "compromised", "stolen", "not", "too"
    };

    public static bool ContainsSensitiveData(string input)
    {
        try
        {
            var text = string.Concat(input.Normalize(NormalizationForm.FormKC)
                .Where(character => CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.Format))
                .Replace('\u2010', '-').Replace('\u2011', '-').Replace('\u2212', '-');
            if (PrivateKey().IsMatch(text) || ApiKey().IsMatch(text) || NumericCredential().IsMatch(text)) return true;
            foreach (Match match in AssignedCredential().Matches(text))
            {
                var value = match.Groups["value"].Value.TrimEnd('.', ',', ';', '?', '!');
                if (value.Length > 0 && !(match.Groups["quote"].Length == 0 &&
                    match.Groups["separator"].Value.Equals("is", StringComparison.OrdinalIgnoreCase) &&
                    PasswordStatuses.Contains(value))) return true;
            }
            foreach (Match match in Bearer().Matches(text))
            {
                if (match.Groups["token"].Value.ToLowerInvariant() is not
                    ("authentication" or "authorization" or "credentials")) return true;
            }
            foreach (Match match in Jwt().Matches(text))
            {
                if (HasJwtHeader(match.Groups["header"].Value)) return true;
            }
            foreach (Match match in Pan().Matches(text))
            {
                var digits = new StringBuilder(19);
                for (var index = 0; index < match.Value.Length; index++)
                {
                    if (!char.IsAsciiDigit(match.Value[index])) continue;
                    digits.Append(match.Value[index]);
                    if (digits.Length > 19) break;
                    // Check complete groups too, so an adjacent unlabeled CVV does not hide a PAN.
                    if (digits.Length >= 13 && (index + 1 == match.Value.Length || !char.IsAsciiDigit(match.Value[index + 1])))
                    {
                        var candidate = digits.ToString();
                        if (candidate.Any(digit => digit != candidate[0]) && HasLuhnChecksum(candidate)) return true;
                    }
                }
            }
            return ContainsIban(text);
        }
        catch (Exception exception) when (exception is RegexMatchTimeoutException or ArgumentException)
        {
            // Fail locally without forwarding uncertain input or including it in an exception log.
            return true;
        }
    }

    private static bool HasLuhnChecksum(string digits)
    {
        var sum = 0;
        var doubleDigit = false;
        for (var index = digits.Length - 1; index >= 0; index--)
        {
            var value = digits[index] - '0';
            if (doubleDigit) { value *= 2; if (value > 9) value -= 9; }
            sum += value;
            doubleDigit = !doubleDigit;
        }
        return sum % 10 == 0;
    }

    private static bool ContainsIban(string text)
    {
        foreach (Match start in IbanStart().Matches(text))
        {
            var normalized = new StringBuilder(34);
            var country = start.Groups["country"].Value.ToUpperInvariant();
            var expectedLength = IbanLengths.GetValueOrDefault(country);
            for (var index = start.Index; index < text.Length && normalized.Length < 34; index++)
            {
                var character = text[index];
                if (character is ' ' or '-') continue;
                if (!char.IsAsciiLetterOrDigit(character)) break;
                normalized.Append(char.ToUpperInvariant(character));
                var length = normalized.Length;
                var boundary = index + 1 == text.Length || !char.IsAsciiLetterOrDigit(text[index + 1]);
                if (boundary && (expectedLength == 0 ? length is >= 15 and <= 34 : length == expectedLength) &&
                    HasIbanChecksum(normalized.ToString())) return true;
                if (expectedLength != 0 && length >= expectedLength) break;
            }
        }
        return false;
    }

    private static bool HasIbanChecksum(string value)
    {
        var remainder = 0;
        for (var index = 0; index < value.Length; index++)
        {
            var character = value[(index + 4) % value.Length];
            if (char.IsAsciiDigit(character)) remainder = (remainder * 10 + character - '0') % 97;
            else remainder = (remainder * 100 + character - 'A' + 10) % 97;
        }
        return remainder == 1;
    }

    private static bool HasJwtHeader(string encoded)
    {
        try
        {
            var base64 = encoded.Replace('-', '+').Replace('_', '/');
            base64 = base64.PadRight((base64.Length + 3) / 4 * 4, '=');
            using var header = JsonDocument.Parse(Convert.FromBase64String(base64), new JsonDocumentOptions { MaxDepth = 4 });
            return header.RootElement.ValueKind == JsonValueKind.Object && header.RootElement.TryGetProperty("alg", out _);
        }
        catch (Exception exception) when (exception is FormatException or JsonException) { return false; }
    }

    // Conventional card grouping avoids concatenating unrelated dates (4-2-2) or phone numbers.
    [GeneratedRegex(@"(?<![A-Za-z0-9])(?:[0-9]{13,19}|[0-9]{3,6}(?:[ -]+[0-9]{3,6}){2,5})(?![A-Za-z0-9])", RegexOptions.CultureInvariant, 100)]
    private static partial Regex Pan();
    [GeneratedRegex(@"(?<![A-Za-z0-9])(?<country>[A-Z]{2}) ?[0-9]{2}", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant, 100)]
    private static partial Regex IbanStart();
    [GeneratedRegex(@"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant, 100)]
    private static partial Regex PrivateKey();
    [GeneratedRegex(@"\b(?:sk-or-v1-[A-Za-z0-9_-]{16,}|sk-(?:proj-|live_|test_)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{16,}|AKIA[A-Z0-9]{16}|AIza[A-Za-z0-9_-]{30,})\b", RegexOptions.CultureInvariant, 100)]
    private static partial Regex ApiKey();
    [GeneratedRegex("\\b(?:pin|cvv2?|cvc2?|otp|passcode|(?:one[- ]time|security|verification)[ -](?:code|password))\\b[\"']?[ \\t]*(?:(?:is|code|number)[ \\t]*|[:=][ \\t]*)?[\"']?[0-9]{3,12}\\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant, 100)]
    private static partial Regex NumericCredential();
    [GeneratedRegex("\\b(?:password|passwd|passphrase|passcode|api[_ -]?key|client[_ -]?secret|access[_ -]?token|refresh[_ -]?token|secret[_ -]?key)\\b[\"']?[ \\t]*(?<separator>:|=|is\\b)[ \\t]*(?<quote>[\"']?)(?<value>[^\\s\"'<>]{1,512})", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant, 100)]
    private static partial Regex AssignedCredential();
    [GeneratedRegex(@"\bBearer[ \t]+(?<token>[A-Za-z0-9._~+/\-]{8,2048}={0,2})", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant, 100)]
    private static partial Regex Bearer();
    [GeneratedRegex(@"(?<![A-Za-z0-9_-])(?<header>[A-Za-z0-9_-]{5,512})\.[A-Za-z0-9_-]{2,2048}\.[A-Za-z0-9_-]{8,1024}(?![A-Za-z0-9_-])", RegexOptions.CultureInvariant, 100)]
    private static partial Regex Jwt();
}
