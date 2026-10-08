#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class ProviderMapping : CompanyScopedEntity
{
    public string Provider { get; set; } = string.Empty;

    public string ProviderEntityType { get; set; } = string.Empty;

    public string ProviderEntityId { get; set; } = string.Empty;

    public string InternalEntityType { get; set; } = string.Empty;

    public Guid InternalEntityId { get; set; }

    public string ExternalStatus { get; set; } = "unknown";

    public DateTimeOffset? LastSyncedAt { get; set; }

    public string SyncStateJson { get; set; } = "{}";
}
