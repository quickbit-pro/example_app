namespace NeoBanking.Domain.Entities;
public sealed class MonthlyStatementExport : CompanyScopedEntity
{
    public Guid OwnerUserId { get; set; }
    public string ProviderUserId { get; set; } = "";
    public int Year { get; set; }
    public int Month { get; set; }
    public string Status { get; set; } = "queued";
    public int Attempt { get; set; }
    public int TransactionCount { get; set; }
    public int AttachmentCount { get; set; }
    public long ByteLength { get; set; }
    public string BlobKey { get; set; } = "";
    public string ErrorMessage { get; set; } = "";
}
