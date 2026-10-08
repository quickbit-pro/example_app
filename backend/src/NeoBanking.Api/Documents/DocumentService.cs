using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.Common;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Documents;
public sealed record DocumentDto(Guid Id, string FileName, string ContentType, long ByteLength, DateTimeOffset CreatedAt);
public sealed class DocumentService(NeoBankingDbContext db, IPrivateDocumentBlobStore blobs, ILogger<DocumentService> logger)
{
    public const int MaxBytes = 10 * 1024 * 1024;
    private IQueryable<StoredDocument> Owned(Guid company, Guid owner) => db.StoredDocuments.Where(x => x.CompanyInstallationId == company && x.OwnerUserId == owner);
    public Task<StoredDocument?> FindAsync(Guid company, Guid owner, Guid id, CancellationToken ct) => Owned(company, owner).AsNoTracking().SingleOrDefaultAsync(x => x.Id == id, ct);
    public async Task<IReadOnlyList<DocumentDto>> ListAsync(Guid company, Guid owner, CancellationToken ct) =>
        (await Owned(company, owner).AsNoTracking().OrderByDescending(x => x.CreatedAt).Take(100).ToListAsync(ct)).Select(Dto).ToArray();
    public async Task<ApplicationResult<DocumentDto>> UploadAsync(Guid company, Guid owner, IFormFile? file, CancellationToken ct)
    {
        if (!blobs.Configured) return Fail("unavailable", "Document storage is not available. Please try again later.", 503);
        if (!await db.Users.AnyAsync(x => x.Id == owner && x.CompanyInstallationId == company && x.LockedAt == null, ct))
            return Fail("unavailable", "This account cannot upload documents.", 403);
        if (file is null || file.Length <= 0 || file.Length > MaxBytes) return Fail("size", "Choose a document up to 10 MB.", 400);
        using var source = file.OpenReadStream(); using var buffer = new MemoryStream();
        var chunk = new byte[65536]; int read;
        while ((read = await source.ReadAsync(chunk, ct)) > 0)
        {
            if (buffer.Length + read > MaxBytes) return Fail("size", "Choose a document up to 10 MB.", 413);
            await buffer.WriteAsync(chunk.AsMemory(0, read), ct);
        }
        var bytes = buffer.ToArray(); var type = Detect(bytes);
        if (type is null) return Fail("type", "Choose a JPEG, PNG, WebP image or PDF document.", 400);
        var sha = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        var existing = await Owned(company, owner).SingleOrDefaultAsync(x => x.Sha256 == sha, ct);
        if (existing is not null) return ApplicationResult<DocumentDto>.Success(Dto(existing));
        var key = $"{company:N}/{owner:N}/{sha}";
        try { await blobs.UploadAsync(key, bytes, type, ct); }
        catch (Exception e) when (e is Azure.RequestFailedException or InvalidOperationException or FormatException)
        {
            logger.LogWarning("Document upload failed ({ErrorType}).", e.GetType().Name);
            return Fail("storage", "The original document could not be saved. Please try again.", 503);
        }
        var name = Path.GetFileName(file.FileName.Replace('\\', '/'));
        name = new string(name.Where(c => !char.IsControl(c)).Take(160).ToArray());
        var doc = new StoredDocument { Id = new Guid(SHA256.HashData(Encoding.UTF8.GetBytes(key)).AsSpan(0, 16)),
            CompanyInstallationId = company, OwnerUserId = owner, BlobKey = key, Sha256 = sha, ByteLength = bytes.Length,
            ContentType = type, FileName = string.IsNullOrWhiteSpace(name) ? "invoice" : name };
        db.StoredDocuments.Add(doc);
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException)
        {
            db.Entry(doc).State = EntityState.Detached;
            existing = await Owned(company, owner).AsNoTracking().SingleOrDefaultAsync(x => x.Sha256 == sha, ct);
            if (existing is null) throw;
            return ApplicationResult<DocumentDto>.Success(Dto(existing));
        }
        return ApplicationResult<DocumentDto>.Success(Dto(doc));
    }
    public Task<Stream> ReadAsync(StoredDocument doc, CancellationToken ct) => blobs.ReadAsync(doc.BlobKey, ct);
    public static DocumentDto Dto(StoredDocument doc) => new(doc.Id, doc.FileName, doc.ContentType, doc.ByteLength, doc.CreatedAt);
    public static string? Detect(byte[] b) => b.Length >= 4 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff ? "image/jpeg" :
        b.AsSpan().StartsWith(new byte[] { 137,80,78,71,13,10,26,10 }) ? "image/png" :
        b.Length >= 12 && b.AsSpan(0,4).SequenceEqual("RIFF"u8) && b.AsSpan(8,4).SequenceEqual("WEBP"u8) ? "image/webp" :
        b.AsSpan().StartsWith("%PDF-"u8) ? "application/pdf" : null;
    private static ApplicationResult<DocumentDto> Fail(string code, string message, int status) => ApplicationResult<DocumentDto>.Failure(new ApplicationError("document." + code, message, status));
}
