using System.Text.RegularExpressions;

namespace NeoBanking.Domain.Identity;

public static class UserNickname
{
    public const string RulesMessage = "Use 3–30 letters, numbers or underscores, starting with a letter.";

    public static string Normalize(string value)
    {
        var nickname = value.Trim();
        if (nickname.StartsWith('@')) nickname = nickname[1..];
        return nickname.ToLowerInvariant();
    }

    public static bool IsValid(string value) =>
        Regex.IsMatch(value, "\\A[a-z][a-z0-9_]{2,29}\\z", RegexOptions.CultureInvariant);
}
