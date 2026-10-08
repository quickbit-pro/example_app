#nullable enable

using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Infrastructure.Security;

public static class VerificationPurposes
{
    public const string PasswordReset = "password_reset";
    public const string EmailVerification = "email_verification";
}

public enum VerificationCodeOutcome
{
    Valid,
    Invalid,
    Expired,
    Locked,
    NotFound
}

public sealed record IssuedVerificationCode(string Code, DateTimeOffset ExpiresAt, Guid Id);

/// <summary>
/// Issues and checks six-digit one-time codes. Only a hash is stored; the
/// plain code is returned once so it can be emailed. Callers own SaveChanges.
/// </summary>
public sealed class UserVerificationCodeService(NeoBankingDbContext dbContext, TimeProvider? timeProvider = null)
{
    public const int CodeLength = 6;
    private const int DefaultMaxAttempts = 5;

    /// <summary>
    /// Creates a new code, retiring any active code for the same purpose.
    /// Returns null when a code was issued more recently than <paramref name="cooldown"/>.
    /// </summary>
    public async Task<IssuedVerificationCode?> IssueAsync(
        ApplicationUser user,
        string purpose,
        TimeSpan lifetime,
        TimeSpan cooldown,
        CancellationToken cancellationToken)
    {
        var now = (timeProvider ?? TimeProvider.System).GetUtcNow();
        var active = await dbContext.UserVerificationCodes
            .Where(code => code.UserId == user.Id && code.Purpose == purpose && code.ConsumedAt == null && code.ExpiresAt > now)
            .ToListAsync(cancellationToken);

        if (cooldown > TimeSpan.Zero && active.Any(code => code.CreatedAt > now.Subtract(cooldown)))
        {
            return null;
        }

        foreach (var code in active)
        {
            code.ConsumedAt = now;
            code.UpdatedAt = now;
        }

        var plain = RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
        var expiresAt = now.Add(lifetime);
        var verification = new UserVerificationCode
        {
            CompanyInstallationId = user.CompanyInstallationId,
            UserId = user.Id,
            Purpose = purpose,
            CodeHash = Hash(user.Id, purpose, plain),
            ExpiresAt = expiresAt,
            MaxAttempts = DefaultMaxAttempts,
            CreatedAt = now,
            UpdatedAt = now
        };
        dbContext.UserVerificationCodes.Add(verification);

        return new IssuedVerificationCode(plain, expiresAt, verification.Id);
    }

    /// <summary>
    /// Checks a code. A valid code is consumed; a wrong code burns one attempt
    /// on the newest active code so brute force is bounded.
    /// </summary>
    public async Task<VerificationCodeOutcome> VerifyAsync(
        Guid userId,
        string purpose,
        string code,
        CancellationToken cancellationToken)
    {
        var now = (timeProvider ?? TimeProvider.System).GetUtcNow();
        var candidate = await dbContext.UserVerificationCodes
            .Where(existing => existing.UserId == userId && existing.Purpose == purpose && existing.ConsumedAt == null)
            .OrderByDescending(existing => existing.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        if (candidate is null)
        {
            return VerificationCodeOutcome.NotFound;
        }

        if (candidate.ExpiresAt <= now)
        {
            return VerificationCodeOutcome.Expired;
        }

        if (candidate.AttemptCount >= candidate.MaxAttempts)
        {
            return VerificationCodeOutcome.Locked;
        }

        var expected = Encoding.ASCII.GetBytes(candidate.CodeHash);
        var actual = Encoding.ASCII.GetBytes(Hash(userId, purpose, code.Trim()));
        candidate.UpdatedAt = now;
        if (expected.Length == actual.Length && CryptographicOperations.FixedTimeEquals(expected, actual))
        {
            candidate.ConsumedAt = now;
            return VerificationCodeOutcome.Valid;
        }

        candidate.AttemptCount++;
        return candidate.AttemptCount >= candidate.MaxAttempts
            ? VerificationCodeOutcome.Locked
            : VerificationCodeOutcome.Invalid;
    }

    public static bool LooksLikeCode(string? code)
    {
        return code is { Length: CodeLength } && code.All(char.IsAsciiDigit);
    }

    private static string Hash(Guid userId, string purpose, string code)
    {
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes($"{userId:N}:{purpose}:{code}")));
    }
}
