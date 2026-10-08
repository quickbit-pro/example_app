#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class BankingSnapshot : CompanyScopedEntity
{
    public Guid? UserId { get; set; }

    public ApplicationUser? User { get; set; }

    public string Provider { get; set; } = string.Empty;

    public string ProviderReference { get; set; } = string.Empty;

    public string SnapshotType { get; set; } = "account";

    public DateTimeOffset AsOf { get; set; } = DateTimeOffset.UtcNow;

    public string Currency { get; set; } = "USD";

    public long? AvailableBalanceMinor { get; set; }

    public long? CurrentBalanceMinor { get; set; }

    public string? SourceHash { get; set; }

    public string SnapshotJson { get; set; } = "{}";
}
