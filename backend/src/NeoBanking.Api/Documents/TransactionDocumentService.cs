using System.ComponentModel.DataAnnotations;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.Common;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
namespace NeoBanking.Api.Documents;
public sealed record AttachTransactionDocumentDto([Required, StringLength(200)] string TransactionId, Guid DocumentId);
public sealed record TransactionDocumentDto(Guid Id, DocumentDto Document);

public sealed class TransactionDocumentService(NeoBankingDbContext db)
{
    private IQueryable<TransactionDocument> Owned(Guid company, Guid owner) => db.TransactionDocuments.Where(x =>
        x.CompanyInstallationId == company && x.OwnerUserId == owner &&
        x.Document.CompanyInstallationId == company && x.Document.OwnerUserId == owner);
    private Task<bool> Active(Guid company, Guid owner, CancellationToken ct) => db.Users.AnyAsync(x =>
        x.Id == owner && x.CompanyInstallationId == company && x.LockedAt == null, ct);
    private static bool Valid(string? id) => !string.IsNullOrWhiteSpace(id) && id.Length <= 200 && !id.Any(char.IsControl);
    public async Task<ApplicationResult<IReadOnlyList<TransactionDocumentDto>>> ListAsync(Guid company, Guid owner, string transactionId, CancellationToken ct)
    {
        if (!Valid(transactionId)) return Fail<IReadOnlyList<TransactionDocumentDto>>("Choose a valid transaction.", 400);
        if (!await Active(company, owner, ct)) return Fail<IReadOnlyList<TransactionDocumentDto>>("This account cannot access invoices.", 403);
        var rows = await Owned(company, owner).AsNoTracking().Include(x => x.Document)
            .Where(x => x.TransactionId == transactionId).OrderBy(x => x.CreatedAt).ThenBy(x => x.Id).ToListAsync(ct);
        return ApplicationResult<IReadOnlyList<TransactionDocumentDto>>.Success(rows.Select(Dto).ToArray());
    }
    public async Task<ApplicationResult<TransactionDocumentDto>> AttachAsync(Guid company, Guid owner, AttachTransactionDocumentDto input, CancellationToken ct)
    {
        if (!Valid(input.TransactionId) || input.DocumentId == Guid.Empty) return Fail<TransactionDocumentDto>("Choose a transaction and invoice.", 400);
        if (!await Active(company, owner, ct)) return Fail<TransactionDocumentDto>("This account cannot add invoices.", 403);
        var document = await db.StoredDocuments.SingleOrDefaultAsync(x => x.Id == input.DocumentId && x.CompanyInstallationId == company && x.OwnerUserId == owner, ct);
        if (document is null) return Fail<TransactionDocumentDto>("Invoice not found.", 404);
        var existing = await Owned(company, owner).Include(x => x.Document).SingleOrDefaultAsync(x => x.TransactionId == input.TransactionId && x.DocumentId == input.DocumentId, ct);
        if (existing is not null) return ApplicationResult<TransactionDocumentDto>.Success(Dto(existing));
        // Stable identity plus a unique index makes retry/concurrent attachment idempotent.
        var key = System.Text.Json.JsonSerializer.Serialize(new { company, owner, input.TransactionId, input.DocumentId });
        var row = new TransactionDocument { Id = new Guid(SHA256.HashData(Encoding.UTF8.GetBytes(key)).AsSpan(0,16)),
            CompanyInstallationId = company, OwnerUserId = owner, TransactionId = input.TransactionId, DocumentId = document.Id, Document = document };
        db.TransactionDocuments.Add(row);
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException)
        {
            db.Entry(row).State = EntityState.Detached;
            existing = await Owned(company, owner).AsNoTracking().Include(x => x.Document).SingleOrDefaultAsync(x => x.Id == row.Id, ct);
            if (existing is null) throw;
            return ApplicationResult<TransactionDocumentDto>.Success(Dto(existing));
        }
        return ApplicationResult<TransactionDocumentDto>.Success(Dto(row));
    }
    public async Task<ApplicationResult<bool>> RemoveAsync(Guid company, Guid owner, Guid id, CancellationToken ct)
    {
        if (!await Active(company, owner, ct)) return Fail<bool>("This account cannot change invoices.", 403);
        var row = await Owned(company, owner).SingleOrDefaultAsync(x => x.Id == id, ct);
        if (row is null) return Fail<bool>("Invoice attachment not found.", 404);
        // Detach only: the same original may also belong to another transaction or a shared bill.
        db.TransactionDocuments.Remove(row); await db.SaveChangesAsync(ct);
        return ApplicationResult<bool>.Success(true);
    }
    private static TransactionDocumentDto Dto(TransactionDocument row) => new(row.Id, DocumentService.Dto(row.Document));
    private static ApplicationResult<T> Fail<T>(string message, int status) => ApplicationResult<T>.Failure(new ApplicationError("transaction_document.invalid", message, status));
}
