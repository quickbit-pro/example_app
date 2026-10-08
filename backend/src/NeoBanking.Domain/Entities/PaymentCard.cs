#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class PaymentCard : CompanyScopedEntity
{
    public Guid UserId { get; set; }

    public ApplicationUser? User { get; set; }

    public string Provider { get; set; } = string.Empty;

    public string ProviderCardId { get; set; } = string.Empty;

    public string Status { get; set; } = "pending";

    public string CardType { get; set; } = "virtual";

    public string LastFour { get; set; } = string.Empty;

    public string? Bin { get; set; }

    public int? ExpiryMonth { get; set; }

    public int? ExpiryYear { get; set; }

    public string Currency { get; set; } = "USD";

    public DateTimeOffset? IssuedAt { get; set; }

    public DateTimeOffset? ActivatedAt { get; set; }

    public DateTimeOffset? SuspendedAt { get; set; }

    public DateTimeOffset? ClosedAt { get; set; }

    public string SpendingControlsJson { get; set; } = "{}";

    public string BillingAddressJson { get; set; } = "{}";
}
