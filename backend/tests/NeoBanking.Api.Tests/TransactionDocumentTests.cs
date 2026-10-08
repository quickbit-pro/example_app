using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Documents;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Npgsql;
using Xunit;
namespace NeoBanking.Api.Tests;

public sealed class TransactionDocumentTests
{
    [Theory]
    [InlineData("/api/v1/mobile/documents")]
    [InlineData("/api/v1/mobile/transaction-documents")]
    public async Task InvoiceRoutes_BypassFlowLogging(string path)
    {
        var context = new Microsoft.AspNetCore.Http.DefaultHttpContext(); context.Request.Path = path;
        var body = context.Response.Body; var called = false;
        var middleware = new NeoBanking.Api.HoppaLogging.HoppaFlowLoggingMiddleware(ctx => {
            called = true; Assert.Same(body,ctx.Response.Body); return Task.CompletedTask;
        }, Microsoft.Extensions.Logging.Abstractions.NullLogger<NeoBanking.Api.HoppaLogging.HoppaFlowLoggingMiddleware>.Instance);
        await middleware.InvokeAsync(context, null!, null!, null!);
        Assert.True(called);
    }

    [Fact]
    public async Task AttachmentPersists_IsIdempotent_Private_AndDetachPreservesOriginal()
    {
        var options = new DbContextOptionsBuilder<NeoBankingDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options;
        var company = Guid.NewGuid(); var owner = Guid.NewGuid(); var other = Guid.NewGuid(); var documentId = Guid.NewGuid();
        await using (var db = new NeoBankingDbContext(options))
        {
            db.Users.AddRange(User(owner, company), User(other, company));
            db.StoredDocuments.Add(Document(documentId, company, owner)); await db.SaveChangesAsync();
            var service = new TransactionDocumentService(db);
            var first = await service.AttachAsync(company, owner, new("provider/transaction-1", documentId), default);
            Assert.True(first.IsSuccess, first.Error?.Message);
            Assert.Equal(first.Value!.Id, (await service.AttachAsync(company, owner, new("provider/transaction-1", documentId), default)).Value!.Id);
            Assert.False((await service.AttachAsync(company, other, new("provider/transaction-1", documentId), default)).IsSuccess);
            Assert.False((await service.AttachAsync(Guid.NewGuid(), owner, new("provider/transaction-1", documentId), default)).IsSuccess);
            Assert.False((await service.AttachAsync(company, owner, new("", documentId), default)).IsSuccess);
            Assert.False((await service.AttachAsync(company, owner, new(new string('x',201), documentId), default)).IsSuccess);
            Assert.False((await service.AttachAsync(company, owner, new("transaction\n2", documentId), default)).IsSuccess);
            Assert.Empty((await service.ListAsync(company, other, "provider/transaction-1", default)).Value!);
            Assert.Empty((await service.ListAsync(company, owner, "different", default)).Value!);
            Assert.False((await service.RemoveAsync(company, other, first.Value.Id, default)).IsSuccess);
            Assert.True((await service.AttachAsync(company, owner, new("transaction-2", documentId), default)).IsSuccess);
        }
        await using (var db = new NeoBankingDbContext(options))
        {
            var service = new TransactionDocumentService(db);
            var row = Assert.Single((await service.ListAsync(company, owner, "provider/transaction-1", default)).Value!);
            Assert.Equal("invoice.pdf", row.Document.FileName);
            Assert.True((await service.RemoveAsync(company, owner, row.Id, default)).IsSuccess);
            Assert.Single(await db.StoredDocuments.ToListAsync());
            Assert.Single((await service.ListAsync(company, owner, "transaction-2", default)).Value!);
            (await db.Users.SingleAsync(u => u.Id == owner)).LockedAt = DateTimeOffset.UtcNow; await db.SaveChangesAsync();
            Assert.False((await service.ListAsync(company, owner, "transaction-2", default)).IsSuccess);
            Assert.False((await service.AttachAsync(company, owner, new("transaction-3", documentId), default)).IsSuccess);
        }
    }

    [TransactionDocumentsPostgresFact]
    public async Task Postgres_MigrationAndConcurrentAttachments_PreserveOneLink()
    {
        var admin = new NpgsqlConnectionStringBuilder(Environment.GetEnvironmentVariable("DOCUMENT_TEST_POSTGRES")!) { Database = "postgres", Pooling = false };
        var name = $"invoice_test_{Guid.NewGuid():N}";
        await using var connection = new NpgsqlConnection(admin.ConnectionString); await connection.OpenAsync();
        await using (var create = new NpgsqlCommand($"CREATE DATABASE \"{name}\"", connection)) await create.ExecuteNonQueryAsync();
        try
        {
            var test = new NpgsqlConnectionStringBuilder(admin.ConnectionString) { Database = name };
            var options = new DbContextOptionsBuilder<NeoBankingDbContext>().UseNpgsql(test.ConnectionString).Options;
            var owner = Guid.NewGuid(); var company = Guid.NewGuid(); var documentId = Guid.NewGuid();
            await using (var db = new NeoBankingDbContext(options))
            {
                await db.Database.MigrateAsync();
                Assert.False(db.Database.HasPendingModelChanges());
                db.CompanyInstallations.Add(new CompanyInstallation { Id = company, Slug = name, LegalName = "Test", DisplayName = "Test", Status = "active" });
                db.Users.Add(User(owner, company)); db.StoredDocuments.Add(Document(documentId, company, owner)); await db.SaveChangesAsync();
            }
            await using var a = new NeoBankingDbContext(options); await using var b = new NeoBankingDbContext(options);
            var results = await Task.WhenAll(new TransactionDocumentService(a).AttachAsync(company, owner, new("same-transaction", documentId), default),
                new TransactionDocumentService(b).AttachAsync(company, owner, new("same-transaction", documentId), default));
            Assert.All(results, result => Assert.True(result.IsSuccess, result.Error?.Message));
            Assert.Equal(results[0].Value!.Id, results[1].Value!.Id);
            await using var read = new NeoBankingDbContext(options); Assert.Single(await read.TransactionDocuments.ToListAsync());
        }
        finally { await using var drop = new NpgsqlCommand($"DROP DATABASE \"{name}\" WITH (FORCE)", connection); await drop.ExecuteNonQueryAsync(); }
    }
    private static ApplicationUser User(Guid id, Guid company) => new() { Id = id, CompanyInstallationId = company, Email = $"{id}@example.test", EmailNormalized = $"{id}@EXAMPLE.TEST", Status = "active" };
    private static StoredDocument Document(Guid id, Guid company, Guid owner) => new() { Id = id, CompanyInstallationId = company, OwnerUserId = owner, BlobKey = "synthetic", Sha256 = new string('a',64), ContentType = "application/pdf", FileName = "invoice.pdf", ByteLength = 12 };
}
public sealed class TransactionDocumentsPostgresFactAttribute : FactAttribute
{
    public TransactionDocumentsPostgresFactAttribute() { if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("DOCUMENT_TEST_POSTGRES"))) Skip = "Set DOCUMENT_TEST_POSTGRES to run isolated migration/concurrency checks."; }
}
