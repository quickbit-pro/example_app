namespace NeoBanking.Api.Auth;

public static class RateLimitPolicies
{
    public const string Auth = "auth";

    /// <summary>Money-moving peer actions: one per 15 seconds per user and path.</summary>
    public const string PeerSensitive = "peer-sensitive";

    /// <summary>Member lookups by email or phone: capped so nobody can enumerate members.</summary>
    public const string PeerLookup = "peer-lookup";
}

public static class JwtOptionsGuard
{
    private static readonly string[] KnownPlaceholders =
    {
        "replace-this-development-key-with-a-secure-secret",
        "change-me",
        "changeme",
        "secret",
    };

    /// <summary>Throws when the signing key is missing, a known placeholder, or shorter than 256 bits.</summary>
    public static void EnsureProductionSafe(JwtOptions options)
    {
        var key = options.SigningKey?.Trim() ?? string.Empty;
        if (key.Length < 32 || KnownPlaceholders.Contains(key, StringComparer.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                "Jwt:SigningKey must be a unique secret of at least 32 characters outside Development. " +
                "Set it through environment variables or the deployment overlay, never in committed appsettings.");
        }
    }
}
