#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class RefreshSession : CompanyScopedEntity
{
    public Guid UserId { get; set; }

    public ApplicationUser? User { get; set; }

    public string TokenHash { get; set; } = string.Empty;

    public string? RotatedFromTokenHash { get; set; }

    public string? DeviceId { get; set; }

    public string? DeviceName { get; set; }

    public string? IpAddress { get; set; }

    public string? UserAgent { get; set; }

    public DateTimeOffset ExpiresAt { get; set; }

    public DateTimeOffset? LastUsedAt { get; set; }

    public DateTimeOffset? RevokedAt { get; set; }

    public string? RevocationReason { get; set; }

    public string MetadataJson { get; set; } = "{}";
}
