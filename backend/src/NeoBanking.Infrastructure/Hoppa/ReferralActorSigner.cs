using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;

namespace NeoBanking.Infrastructure.Hoppa;

/// <summary>Signs the exact outgoing bytes, path and query using installation-scoped trust.</summary>
public static class ReferralActorSigner
{
    public static async Task SignAsync(HttpRequestMessage message, string? actorId,
        ReferralAuditDelegationOptions options, CancellationToken ct)
    {
        if (!options.Enabled || string.IsNullOrWhiteSpace(actorId)) return;
        if (string.IsNullOrWhiteSpace(options.InstallationId) || options.CompanyId <= 0 ||
            string.IsNullOrWhiteSpace(options.Secret) || Encoding.UTF8.GetByteCount(options.Secret) < 32)
            throw new InvalidOperationException("Enabled referral audit delegation requires an installation, company and a secret of at least 32 bytes.");
        var uri = message.RequestUri ?? throw new InvalidOperationException("Missing upstream URI.");
        var path = uri.IsAbsoluteUri ? uri.PathAndQuery : uri.OriginalString;
        // This capability is deliberately confined to referral administration.
        if (!path.StartsWith("/api/v2/referrals/", StringComparison.Ordinal)) return;
        var bytes = message.Content is null ? Array.Empty<byte>() : await message.Content.ReadAsByteArrayAsync(ct);
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var payload = WebEncoders.Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(new
        {
            v = 1, installation_id = options.InstallationId, company_id = options.CompanyId,
            actor_id = actorId, issued_at = now, expires_at = now + 120, nonce = Guid.NewGuid().ToString("D"),
            method = message.Method.Method.ToUpperInvariant(), path,
            body_sha256 = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant()
        }));
        var signature = HMACSHA256.HashData(Encoding.UTF8.GetBytes(options.Secret), Encoding.UTF8.GetBytes(payload));
        message.Headers.Add("X-Referral-Actor", payload);
        message.Headers.Add("X-Referral-Actor-Signature", WebEncoders.Base64UrlEncode(signature));
    }
}
