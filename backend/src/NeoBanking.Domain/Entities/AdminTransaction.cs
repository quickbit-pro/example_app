#nullable enable

namespace NeoBanking.Domain.Entities;

/// <summary>
/// One provider ledger row, classified for operator reporting. The admin sync
/// upserts these by provider id; KPIs and the money pages read only this table.
/// </summary>
public sealed class AdminTransaction : CompanyScopedEntity
{
    public Guid UserId { get; set; }

    public ApplicationUser? User { get; set; }

    public string ProviderTransactionId { get; set; } = string.Empty;

    public DateTimeOffset OccurredAt { get; set; }

    public string RawType { get; set; } = string.Empty;

    public string RawStatus { get; set; } = string.Empty;

    /// <summary>Why the provider declined or failed the row, when it says so.</summary>
    public string? StatusReason { get; set; }

    /// <summary>completed, pending, failed or other.</summary>
    public string Status { get; set; } = "other";

    /// <summary>What the row means, see AdminTransactionKinds.</summary>
    public string Kind { get; set; } = "other";

    public string? FeeType { get; set; }

    /// <summary>in, out, internal (between the customer's own balances) or none.</summary>
    public string Direction { get; set; } = "none";

    /// <summary>Always positive; <see cref="Direction"/> carries the sign.</summary>
    public decimal Amount { get; set; }

    public string Currency { get; set; } = "USD";

    public string Description { get; set; } = string.Empty;

    public string? Merchant { get; set; }

    public string? MerchantCategory { get; set; }

    public string? CardReference { get; set; }

    public string? WalletReference { get; set; }

    public string? BudgetReference { get; set; }

    public string? AccountReference { get; set; }

    public string? ExternalReference { get; set; }

    public string? RelatedReference { get; set; }

    public string? ClientReference { get; set; }

    public decimal? FeeAmount { get; set; }

    public string? FeeCurrency { get; set; }

    /// <summary>False for related provider legs the provider leaves out of its own statistics.</summary>
    public bool IsPrimary { get; set; } = true;

    /// <summary>A second view of a movement that another row already reports.</summary>
    public bool IsDuplicate { get; set; }

    public DateTimeOffset LastSeenAt { get; set; }
}
