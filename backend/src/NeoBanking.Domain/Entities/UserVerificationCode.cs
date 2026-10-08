#nullable enable

namespace NeoBanking.Domain.Entities;

/// <summary>
/// One-time numeric code emailed to a user for password reset or email
/// confirmation. Only the hash is stored.
/// </summary>
public sealed class UserVerificationCode : CompanyScopedEntity
{
    public Guid UserId { get; set; }

    public ApplicationUser? User { get; set; }

    public string Purpose { get; set; } = string.Empty;

    public string CodeHash { get; set; } = string.Empty;

    public DateTimeOffset ExpiresAt { get; set; }

    public DateTimeOffset? ConsumedAt { get; set; }

    public int AttemptCount { get; set; }

    public int MaxAttempts { get; set; } = 5;
}
