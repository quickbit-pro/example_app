namespace NeoBanking.Domain.Entities;

public sealed class StoredDocument : CompanyScopedEntity
{
    public Guid OwnerUserId { get; set; }
    public string BlobKey { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public string ContentType { get; set; } = string.Empty;
    public string Sha256 { get; set; } = string.Empty;
    public long ByteLength { get; set; }
}
