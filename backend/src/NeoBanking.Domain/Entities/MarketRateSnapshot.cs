#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class MarketRateSnapshot : AuditableEntity
{
    public string BaseCurrency { get; set; } = "USD";

    public string QuoteCurrency { get; set; } = string.Empty;

    public decimal Rate { get; set; }

    public string Provider { get; set; } = string.Empty;

    public DateTimeOffset ObservedAt { get; set; }
}
