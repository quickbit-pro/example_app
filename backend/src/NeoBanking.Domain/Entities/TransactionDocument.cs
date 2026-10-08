namespace NeoBanking.Domain.Entities;

/// <summary>A private annotation of a provider transaction reference; never changes ledger data.</summary>
public sealed class TransactionDocument : CompanyScopedEntity
{
    public Guid OwnerUserId { get; set; }
    public string TransactionId { get; set; } = string.Empty;
    public Guid DocumentId { get; set; }
    public StoredDocument Document { get; set; } = null!;
}
