#nullable enable

namespace NeoBanking.Domain.Entities;

/// <summary>
/// "Request money": the requester asks the payer for an amount; accepting it
/// creates a <see cref="PeerTransfer"/> from the payer to the requester.
/// </summary>
public sealed class PeerPaymentRequest : CompanyScopedEntity
{
    public Guid RequesterUserId { get; set; }

    public ApplicationUser? Requester { get; set; }

    public Guid PayerUserId { get; set; }

    public ApplicationUser? Payer { get; set; }

    public decimal Amount { get; set; }

    public string Currency { get; set; } = "USD";

    public string? Note { get; set; }

    /// <summary>pending, accepted, declined, expired or cancelled.</summary>
    public string Status { get; set; } = "pending";

    public DateTimeOffset ExpiresAt { get; set; }

    public DateTimeOffset? RespondedAt { get; set; }

    public Guid? TransferId { get; set; }
}
