#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class IdempotencyRecord : CompanyScopedEntity
{
    public string Scope { get; set; } = string.Empty;

    public string Key { get; set; } = string.Empty;

    public string RequestHash { get; set; } = string.Empty;

    public string Status { get; set; } = "started";

    public int? ResponseStatusCode { get; set; }

    public DateTimeOffset? LockedUntil { get; set; }

    public DateTimeOffset? CompletedAt { get; set; }

    public DateTimeOffset ExpiresAt { get; set; }

    public string? ResponseBodyJson { get; set; }
}
