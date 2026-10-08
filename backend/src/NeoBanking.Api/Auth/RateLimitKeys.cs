#nullable enable

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace NeoBanking.Api.Auth;

/// <summary>
/// Partition keys for per-user throttles. The rate limiter runs before
/// authentication, so the user id is read from the bearer token payload
/// without verifying it: a forged id only isolates the forger in their own
/// bucket, and the real authorization check still follows.
/// </summary>
public static class RateLimitKeys
{
    public static string PerUser(HttpContext context, string clientAddress)
    {
        var header = context.Request.Headers.Authorization.FirstOrDefault();
        if (string.IsNullOrWhiteSpace(header))
        {
            return $"ip:{clientAddress}";
        }

        var token = header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ? header[7..].Trim() : header.Trim();
        var userId = UnverifiedClaim(token, "local_user_id") ?? UnverifiedClaim(token, "sub");
        if (!string.IsNullOrWhiteSpace(userId))
        {
            return $"user:{userId}";
        }

        var digest = SHA256.HashData(Encoding.UTF8.GetBytes(token));
        return $"token:{Convert.ToHexString(digest.AsSpan(0, 12))}";
    }

    public static string? UnverifiedClaim(string token, string claim)
    {
        var parts = token.Split('.');
        if (parts.Length < 2)
        {
            return null;
        }

        try
        {
            var payload = parts[1].Replace('-', '+').Replace('_', '/');
            payload = payload.PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=');
            using var document = JsonDocument.Parse(Convert.FromBase64String(payload));
            return document.RootElement.TryGetProperty(claim, out var value) && value.ValueKind == JsonValueKind.String
                ? value.GetString()
                : null;
        }
        catch (FormatException)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
