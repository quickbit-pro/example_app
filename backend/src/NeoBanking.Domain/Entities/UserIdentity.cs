#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class UserIdentity : CompanyScopedEntity
{
    public Guid UserId { get; set; }

    public ApplicationUser? User { get; set; }

    public string Provider { get; set; } = string.Empty;

    public string Subject { get; set; } = string.Empty;

    public string? EmailAtProvider { get; set; }

    public string? PasswordHash { get; set; }

    public bool IsPrimary { get; set; }

    public DateTimeOffset? LastAuthenticatedAt { get; set; }

    public string ClaimsJson { get; set; } = "{}";
}
