using System.Collections.Concurrent;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using NeoBanking.Api.Documents;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Xunit;
namespace NeoBanking.Api.Tests;
public sealed class DocumentStorageTests
{
    private static readonly byte[] Photo = Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aDfcAAAAASUVORK5CYII=");
    private static FormFile File(byte[] bytes, string name = "original.png") => new(new MemoryStream(bytes), 0, bytes.Length, "file", name);
    [Fact]
    public async Task SavesExactBytes_Deduplicates_AndScopesReadsToOwnerAndCompany()
    {
        await using var db = Database(); var company = Guid.NewGuid(); var owner = Guid.NewGuid(); var other = Guid.NewGuid();
        db.Users.AddRange(new ApplicationUser { Id = owner, CompanyInstallationId = company }, new ApplicationUser { Id = other, CompanyInstallationId = company }); await db.SaveChangesAsync();
        var blobs = new FakeBlobs(); var service = new DocumentService(db, blobs, NullLogger<DocumentService>.Instance);
        var saved = await service.UploadAsync(company, owner, File(Photo), default); Assert.True(saved.IsSuccess, saved.Error?.Message);
        Assert.Equal(saved.Value!.Id, (await service.UploadAsync(company, owner, File(Photo, "again.png"), default)).Value!.Id);
        Assert.Single(blobs.Files); Assert.Single(await db.StoredDocuments.ToListAsync());
        var document = await service.FindAsync(company, owner, saved.Value.Id, default); Assert.NotNull(document);
        using var original = await service.ReadAsync(document!, default); using var copy = new MemoryStream(); await original.CopyToAsync(copy);
        Assert.Equal(Photo, copy.ToArray()); Assert.Equal("image/png", document!.ContentType);
        Assert.Null(await service.FindAsync(company, other, document.Id, default));
        Assert.Null(await service.FindAsync(Guid.NewGuid(), owner, document.Id, default));
        Assert.Empty(await service.ListAsync(company, other, default));
        var otherCopy = await service.UploadAsync(company, other, File(Photo), default);
        Assert.NotEqual(document.Id, otherCopy.Value!.Id); Assert.Equal(2, blobs.Files.Count);
    }
    [Fact]
    public async Task RejectsUnsupportedBytes_AndDoesNotRecordFailedStorageWrites()
    {
        await using var db = Database(); var company = Guid.NewGuid(); var owner = Guid.NewGuid();
        db.Users.Add(new ApplicationUser { Id = owner, CompanyInstallationId = company }); await db.SaveChangesAsync();
        var blobs = new FakeBlobs(); var service = new DocumentService(db, blobs, NullLogger<DocumentService>.Instance);
        Assert.False((await service.UploadAsync(company, owner, File("<script>alert(1)</script>"u8.ToArray(), "photo.png"), default)).IsSuccess);
        Assert.Empty(blobs.Files);
        blobs.Fail = true;
        Assert.Equal(503, (await service.UploadAsync(company, owner, File(Photo), default)).Error!.StatusCode);
        Assert.Empty(await db.StoredDocuments.ToListAsync());
        Assert.False((await service.UploadAsync(Guid.NewGuid(), owner, File(Photo), default)).IsSuccess);
    }
    [Fact]
    public void DocumentSignatures_AcceptPdfAndRejectSvg()
    {
        Assert.Equal("application/pdf", DocumentService.Detect("%PDF-1.7\nfixture"u8.ToArray()));
        Assert.Null(DocumentService.Detect("<svg/>"u8.ToArray()));
    }
    private static NeoBankingDbContext Database() => new(new DbContextOptionsBuilder<NeoBankingDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
    public sealed class FakeBlobs : IPrivateDocumentBlobStore
    {
        public bool Configured => true;
        public bool Fail;
        public ConcurrentDictionary<string, byte[]> Files = new();
        public Task UploadAsync(string key, byte[] bytes, string type, CancellationToken ct)
        { if (Fail) throw new InvalidOperationException("Fixture failure"); Files.TryAdd(key, bytes.ToArray()); return Task.CompletedTask; }
        public Task<Stream> ReadAsync(string key, CancellationToken ct) => Task.FromResult<Stream>(new MemoryStream(Files[key]));
    }
}
