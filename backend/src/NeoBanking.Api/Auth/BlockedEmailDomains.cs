using System.Collections.Frozen;
using NeoBanking.Infrastructure.Email;

namespace NeoBanking.Api.Auth;

/// <summary>
/// Rejects sign-ups from throwaway mailbox providers, the same rule the Hoppa platform
/// applies to its own registrations. The bundled list is Hoppa's blocked_email_domains
/// table; <see cref="EmailOptions.BlockedSignupDomains"/> adds domains and
/// <see cref="EmailOptions.AllowedSignupDomains"/> exempts one that is listed by mistake.
/// </summary>
public static class BlockedEmailDomains
{
    private const string ResourceName = "NeoBanking.Api.Auth.blocked-email-domains.txt";

    private static readonly Lazy<FrozenSet<string>> Bundled = new(LoadBundled);

    public static bool IsBlocked(string? email, EmailOptions options)
    {
        var domain = DomainOf(email);
        if (domain is null) return false;

        var allowed = Parse(options.AllowedSignupDomains);
        var extra = Parse(options.BlockedSignupDomains);
        // Walk from the full domain up to its parents, so "inbox.mailinator.com" matches
        // "mailinator.com". The most specific entry wins, which lets an installation allow
        // one subdomain of a blocked provider or block one subdomain of an allowed one.
        for (var candidate = domain; ;)
        {
            if (allowed.Contains(candidate)) return false;
            if (extra.Contains(candidate)) return true;
            if (options.BlockDisposableSignupDomains && Bundled.Value.Contains(candidate)) return true;

            var dot = candidate.IndexOf('.');
            if (dot < 0) return false;
            candidate = candidate[(dot + 1)..];
        }
    }

    /// <summary>The lower-case domain of an address, or null when it has none worth matching.</summary>
    public static string? DomainOf(string? email)
    {
        if (string.IsNullOrWhiteSpace(email)) return null;
        var at = email.LastIndexOf('@');
        return at < 0 ? null : Normalize(email[(at + 1)..]);
    }

    private static string? Normalize(string value)
    {
        var domain = value.Trim().Trim('.').ToLowerInvariant();
        if (domain.Length == 0 || !domain.Contains('.')) return null;
        foreach (var character in domain)
        {
            if (!(char.IsAsciiLetterOrDigit(character) || character is '.' or '-')) return null;
        }
        return domain;
    }

    private static HashSet<string> Parse(string? commaSeparated)
    {
        var domains = new HashSet<string>(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(commaSeparated)) return domains;
        foreach (var entry in commaSeparated.Split([',', ';', ' ', '\n'], StringSplitOptions.RemoveEmptyEntries))
        {
            if (Normalize(entry) is { } domain) domains.Add(domain);
        }
        return domains;
    }

    private static FrozenSet<string> LoadBundled()
    {
        using var stream = typeof(BlockedEmailDomains).Assembly.GetManifestResourceStream(ResourceName)
            ?? throw new InvalidOperationException($"Embedded resource {ResourceName} is missing.");
        using var reader = new StreamReader(stream);
        var domains = new HashSet<string>(StringComparer.Ordinal);
        while (reader.ReadLine() is { } line)
        {
            if (line.StartsWith('#')) continue;
            if (Normalize(line) is { } domain) domains.Add(domain);
        }
        return domains.ToFrozenSet(StringComparer.Ordinal);
    }
}
