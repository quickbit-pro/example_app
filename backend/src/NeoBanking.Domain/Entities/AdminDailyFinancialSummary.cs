#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class AdminDailyFinancialSummary : CompanyScopedEntity
{
    public Guid UserId { get; set; }

    public ApplicationUser? User { get; set; }

    public DateOnly Day { get; set; }

    public string Currency { get; set; } = "USD";

    public int CompletedTransactionCount { get; set; }

    public long InflowMinor { get; set; }

    public long OutflowMinor { get; set; }
}
