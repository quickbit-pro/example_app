using System.IO.Compression;
using System.ComponentModel.DataAnnotations;
using System.Security.Cryptography;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Documents;
using NeoBanking.Application.Common;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
namespace NeoBanking.Api.Statements;
public sealed class CreateMonthlyStatementDto
{
    public Guid Id { get; init; }
    [Range(2000, 9998)] public int Year { get; init; }
    [Range(1, 12)] public int Month { get; init; }
}
public sealed record MonthlyStatementDto(Guid Id, int Year, int Month, string Status, int TransactionCount, int AttachmentCount,
    long ByteLength, string Error, string? DownloadPath, DateTimeOffset CreatedAt);
public sealed class StatementDownloadTokens(IDataProtectionProvider provider)
{
    private readonly ITimeLimitedDataProtector protector = provider.CreateProtector("monthly-statement-download-v1").ToTimeLimitedDataProtector();
    public string Create(MonthlyStatementExport job) => protector.Protect($"{job.CompanyInstallationId:D}|{job.OwnerUserId:D}|{job.Id:D}", TimeSpan.FromMinutes(15));
    public (Guid Company, Guid Owner, Guid Id)? Read(string? token)
    {
        if (string.IsNullOrWhiteSpace(token) || token.Length > 2000) return null;
        try { var parts = protector.Unprotect(token).Split('|'); return parts.Length == 3 ? (Guid.Parse(parts[0]), Guid.Parse(parts[1]), Guid.Parse(parts[2])) : null; }
        catch (Exception e) when (e is CryptographicException or FormatException) { return null; }
    }
}
public sealed class MonthlyStatementService(NeoBankingDbContext db, IPrivateDocumentBlobStore blobs, StatementDownloadTokens tokens)
{
    private IQueryable<MonthlyStatementExport> Owned(Guid company, Guid owner) => db.MonthlyStatementExports.Where(j => j.CompanyInstallationId == company && j.OwnerUserId == owner);
    public Task<bool> Active(Guid company, Guid owner, CancellationToken ct) => db.Users.AnyAsync(u => u.CompanyInstallationId == company && u.Id == owner && u.LockedAt == null, ct);
    public MonthlyStatementDto Dto(MonthlyStatementExport j) => new(j.Id,j.Year,j.Month,j.Status,j.TransactionCount,j.AttachmentCount,j.ByteLength,j.ErrorMessage,
        j.Status == "ready" ? "/api/v1/statement-download?token=" + Uri.EscapeDataString(tokens.Create(j)) : null, j.CreatedAt);
    public async Task<ApplicationResult<MonthlyStatementDto>> CreateAsync(Guid company, Guid owner, string providerUser, CreateMonthlyStatementDto input, CancellationToken ct)
    {
        if (!blobs.Configured) return Fail("Document storage is unavailable. Please try again later.", 503);
        if (!await Active(company, owner, ct)) return Fail("This account cannot create statements.", 403);
        var now = DateTimeOffset.UtcNow;
        if (input.Id == Guid.Empty || input.Year < 2000 || input.Year > now.Year || input.Month < 1 || input.Month > 12 || input.Year == now.Year && input.Month > now.Month)
            return Fail("Choose the current month or an earlier month.", 400);
        var existing = await Owned(company, owner).AsNoTracking().SingleOrDefaultAsync(j => j.Id == input.Id, ct);
        if (existing is not null) return existing.Year == input.Year && existing.Month == input.Month ? ApplicationResult<MonthlyStatementDto>.Success(Dto(existing)) : Fail("Start a new export for this month.",409);
        if (await Owned(company, owner).AnyAsync(j => j.Status == "queued" || j.Status == "processing", ct)) return Fail("An export is already being prepared. Check your recent exports.",409);
        if (await Owned(company, owner).CountAsync(j => j.CreatedAt > now.AddDays(-1), ct) >= 12) return Fail("You can create 12 monthly exports per day.",429);
        var job = new MonthlyStatementExport { Id=input.Id, CompanyInstallationId=company, OwnerUserId=owner, ProviderUserId=providerUser, Year=input.Year, Month=input.Month };
        db.MonthlyStatementExports.Add(job);
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException)
        {
            db.Entry(job).State=EntityState.Detached;
            existing = await Owned(company, owner).AsNoTracking().SingleOrDefaultAsync(j => j.Id == input.Id, ct);
            if (existing is not null && existing.Year == input.Year && existing.Month == input.Month) return ApplicationResult<MonthlyStatementDto>.Success(Dto(existing));
            return Fail("An export is already being prepared. Check your recent exports.",409);
        }
        return ApplicationResult<MonthlyStatementDto>.Success(Dto(job));
    }
    public async Task<IReadOnlyList<MonthlyStatementDto>> ListAsync(Guid company, Guid owner, CancellationToken ct) =>
        (await Owned(company, owner).AsNoTracking().OrderByDescending(j => j.CreatedAt).Take(24).ToListAsync(ct)).Select(Dto).ToArray();
    public async Task<MonthlyStatementDto?> GetAsync(Guid company, Guid owner, Guid id, CancellationToken ct)
    { var job=await Owned(company, owner).AsNoTracking().SingleOrDefaultAsync(j=>j.Id==id,ct); return job is null ? null : Dto(job); }
    private static ApplicationResult<MonthlyStatementDto> Fail(string message,int status) => ApplicationResult<MonthlyStatementDto>.Failure(new ApplicationError("statement.invalid",message,status));
}
public sealed class MonthlyStatementBuilder(NeoBankingDbContext db, IStatementTransactionSource source, IPrivateDocumentBlobStore blobs)
{
    public const long MaxAttachmentBytes = 200L * 1024 * 1024;
    public async Task<(byte[] Bytes, int Transactions, int Attachments)> BuildAsync(MonthlyStatementExport job, CancellationToken ct)
    {
        var user=await db.Users.AsNoTracking().SingleOrDefaultAsync(u=>u.CompanyInstallationId==job.CompanyInstallationId && u.Id==job.OwnerUserId && u.LockedAt==null,ct)
            ?? throw new StatementExportException("This account cannot create statements.");
        var transactions=await source.LoadAsync(job.ProviderUserId,job.Year,job.Month,ct);
        var ids=transactions.SelectMany(t=>new[]{t.Id,t.ExternalId,t.RelatedId}).Where(id=>!string.IsNullOrWhiteSpace(id)).Distinct().ToArray();
        var attached=await db.TransactionDocuments.AsNoTracking().Include(d=>d.Document).Where(d=>d.CompanyInstallationId==job.CompanyInstallationId && d.OwnerUserId==job.OwnerUserId &&
            d.Document.CompanyInstallationId==job.CompanyInstallationId && d.Document.OwnerUserId==job.OwnerUserId && ids.Contains(d.TransactionId))
            .OrderBy(d=>d.CreatedAt).ThenBy(d=>d.Id).ToListAsync(ct);
        if (attached.Sum(d=>d.Document.ByteLength)>MaxAttachmentBytes) throw new StatementExportException("This month's attachments exceed the 200 MB export limit.");
        var filesByTransaction = new Dictionary<string,List<TransactionDocument>>();
        foreach (var link in attached)
        {
            var matches = transactions.Where(t => t.Id == link.TransactionId).ToArray();
            if (matches.Length == 0) matches = transactions.Where(t => t.ExternalId == link.TransactionId).ToArray();
            if (matches.Length == 0) matches = transactions.Where(t => t.RelatedId == link.TransactionId).ToArray();
            if (matches.Length != 1) throw new StatementExportException("An invoice matches multiple transaction references. Please contact support.");
            if (!filesByTransaction.TryGetValue(matches[0].Id, out var files)) filesByTransaction[matches[0].Id] = files = [];
            // The same document can be attached from both card details and the activity list.
            if (!files.Any(f => f.DocumentId == link.DocumentId)) files.Add(link);
        }
        var rows=new List<StatementRow>(); using var output=new MemoryStream(); long readTotal=0;
        using (var zip=new ZipArchive(output,ZipArchiveMode.Create,true))
        {
            for(var i=0;i<transactions.Count;i++)
            {
                var t=transactions[i]; var files=new List<string>();
                foreach(var link in filesByTransaction.GetValueOrDefault(t.Id,[]))
                {
                    var name=StatementFiles.AttachmentName(i+1,t.Merchant,files.Count+1,link.Document.ContentType);
                    await using var original=await blobs.ReadAsync(link.Document.BlobKey,ct);
                    await using var target=zip.CreateEntry(name,CompressionLevel.Fastest).Open();
                    var buffer=new byte[65536]; int read; long length=0;
                    while((read=await original.ReadAsync(buffer,ct))>0)
                    { length+=read; readTotal+=read; if(readTotal>MaxAttachmentBytes) throw new StatementExportException("This month's attachments exceed the 200 MB export limit."); await target.WriteAsync(buffer.AsMemory(0,read),ct); }
                    if(length!=link.Document.ByteLength) throw new StatementExportException("An invoice could not be read completely. Please try again.");
                    files.Add(name);
                }
                rows.Add(new(i+1,t,files));
            }
            async Task Add(string name,byte[] bytes) { await using var target=zip.CreateEntry(name,CompressionLevel.Fastest).Open(); await target.WriteAsync(bytes,ct); }
            await Add($"statement-{job.Year:D4}-{job.Month:D2}.csv",StatementFiles.Csv(rows));
            await Add($"statement-{job.Year:D4}-{job.Month:D2}.pdf",StatementFiles.Pdf(job.Year,job.Month,user.DisplayName ?? "Account holder",rows,DateTimeOffset.UtcNow));
        }
        return(output.ToArray(),transactions.Count,rows.Sum(r=>r.Files.Count));
    }
}
