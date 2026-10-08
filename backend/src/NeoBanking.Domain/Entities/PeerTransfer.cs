#nullable enable

namespace NeoBanking.Domain.Entities;

/// <summary>
/// A customer-to-customer transfer inside one installation. Money moves
/// through the provider in two legs (sender → master account → recipient),
/// so the row keeps both provider transfer ids and the settlement state.
/// </summary>
public sealed class PeerTransfer : CompanyScopedEntity
{
    public Guid SenderUserId { get; set; }

    public ApplicationUser? Sender { get; set; }

    public Guid RecipientUserId { get; set; }

    public ApplicationUser? Recipient { get; set; }

    public decimal Amount { get; set; }

    public string Currency { get; set; } = "USD";

    public string? Note { get; set; }

    /// <summary>pending, completed, failed, refunded or needs_attention.</summary>
    public string Status { get; set; } = "pending";

    public decimal FeeAmount { get; set; }

    /// <summary>Reference shared by both provider legs so support can trace them.</summary>
    public string ExternalReferenceId { get; set; } = string.Empty;

    public string? DebitTransferId { get; set; }

    public string? CreditTransferId { get; set; }

    public string? RefundTransferId { get; set; }

    public Guid? PaymentRequestId { get; set; }

    public string? ErrorCode { get; set; }

    public string? ErrorMessage { get; set; }

    public DateTimeOffset? CompletedAt { get; set; }
}
