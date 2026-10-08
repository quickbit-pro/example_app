using Npgsql;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using NeoBanking.Api.Documents;
using NeoBanking.Api.Statements;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Xunit;
namespace NeoBanking.Api.Tests;
public sealed class MonthlyStatementTests
{
    private static readonly Guid Company=Guid.NewGuid(), Owner=Guid.NewGuid();
    private static NeoBankingDbContext Database()=>new(new DbContextOptionsBuilder<NeoBankingDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
    private static readonly StatementTransaction Row=new("transaction-1",new(2026,8,12,10,20,0,TimeSpan.Zero),"Laško / Café","CARD_PAYMENT","completed",-12.34m,"EUR","card","Lunch","card-reference");
    [Fact]
    public async Task Zip_LinksNumberedInvoiceCopies_AndExcludesAnotherOwnersFiles()
    {
        await using var db=Database(); db.Users.Add(new ApplicationUser{Id=Owner,CompanyInstallationId=Company,DisplayName="Test owner"});
        var blobs=new DocumentStorageTests.FakeBlobs(); var bytes="original photo bytes"u8.ToArray();
        blobs.Files["photo"]=bytes;
        var doc=new StoredDocument{CompanyInstallationId=Company,OwnerUserId=Owner,BlobKey="photo",FileName="phone.jpg",ContentType="image/jpeg",ByteLength=bytes.Length};
        var other=new StoredDocument{CompanyInstallationId=Company,OwnerUserId=Guid.NewGuid(),BlobKey="private-other",ContentType="image/jpeg"};
        db.StoredDocuments.AddRange(doc,other);
        db.TransactionDocuments.AddRange(new TransactionDocument{CompanyInstallationId=Company,OwnerUserId=Owner,TransactionId=Row.ExternalId,Document=doc},new TransactionDocument{CompanyInstallationId=Company,OwnerUserId=other.OwnerUserId,TransactionId=Row.Id,Document=other});
        await db.SaveChangesAsync();
        var job=new MonthlyStatementExport{CompanyInstallationId=Company,OwnerUserId=Owner,Year=2026,Month=8};
        var source=new FakeSource([Row]);
        var result=await new MonthlyStatementBuilder(db,source,blobs).BuildAsync(job,default);
        using var zip=new ZipArchive(new MemoryStream(result.Bytes));
        Assert.Equal(3,zip.Entries.Count); Assert.Equal(1,result.Attachments);
        var name="invoices/0001_Lasko_Cafe_01.jpg";
        using var original=new MemoryStream(); await zip.GetEntry(name)!.Open().CopyToAsync(original); Assert.Equal(bytes,original.ToArray());
        using var reader=new StreamReader(zip.GetEntry("statement-2026-08.csv")!.Open()); var csv=await reader.ReadToEndAsync(); Assert.Contains(name,csv); Assert.Contains("Laško / Café",csv);
        Assert.Equal("phone.jpg",doc.FileName);
        var output=Environment.GetEnvironmentVariable("STATEMENT_PREVIEW_PDF");
        if(!string.IsNullOrEmpty(output)) { using var file=File.Create(output); await zip.GetEntry("statement-2026-08.pdf")!.Open().CopyToAsync(file); }
        blobs.Files["photo"]=[];
        await Assert.ThrowsAsync<StatementExportException>(()=>new MonthlyStatementBuilder(db,source,blobs).BuildAsync(job,default));
    }
    [Fact]
    public async Task JobCreation_IsIdempotent_OwnerScoped_AndRejectsFutureMonths()
    {
        await using var db=Database(); db.Users.Add(new ApplicationUser{Id=Owner,CompanyInstallationId=Company}); await db.SaveChangesAsync();
        var tokens=new StatementDownloadTokens(new EphemeralDataProtectionProvider());
        var service=new MonthlyStatementService(db,new DocumentStorageTests.FakeBlobs(),tokens);
        var input=new CreateMonthlyStatementDto{Id=Guid.NewGuid(),Year=2026,Month=1};
        var created=await service.CreateAsync(Company,Owner,"provider-1",input,default); Assert.True(created.IsSuccess);
        Assert.Equal(created.Value!.Id,(await service.CreateAsync(Company,Owner,"provider-1",input,default)).Value!.Id);
        Assert.Null(await service.GetAsync(Company,Guid.NewGuid(),input.Id,default));
        Assert.Equal(409,(await service.CreateAsync(Company,Owner,"provider-1",new(){Id=Guid.NewGuid(),Year=2026,Month=1},default)).Error!.StatusCode);
        Assert.Equal(400,(await service.CreateAsync(Company,Owner,"provider-1",new(){Id=Guid.NewGuid(),Year=9998,Month=1},default)).Error!.StatusCode);
        var job=await db.MonthlyStatementExports.SingleAsync(); var token=tokens.Create(job);
        Assert.Equal((Company,Owner,job.Id),tokens.Read(token)); Assert.Null(tokens.Read(token+"tampered")); Assert.Null(tokens.Read(null));
    }
    [Fact]
    public async Task Source_ReadsEveryPage_AndRefusesTruncatedOrChangingLists()
    {
        var proxy=new FakeProxy(); var source=new StatementTransactionSource(proxy);
        var rows=await source.LoadAsync("trusted-user",2026,8,default); Assert.Equal(2,rows.Count); Assert.Equal(2,proxy.Calls); Assert.All(rows,r=>Assert.Equal(-2.5m,r.Amount));
        Assert.All(proxy.Queries,q=>Assert.Equal("trusted-user",q["userId"]));
        Assert.Equal("2",rows[0].Id); Assert.Equal("1",rows[1].Id);
        proxy.Calls=0;proxy.Truncated=true;
        await Assert.ThrowsAsync<StatementExportException>(()=>source.LoadAsync("trusted-user",2026,8,default));
    }
    [Fact]
    public void Filenames_AreSafeAndCsvCannotExecuteSpreadsheetFormula()
    {
        Assert.Equal("invoices/0001_Transaction_02.pdf",StatementFiles.AttachmentName(1,"../../",2,"application/pdf"));
        var csv=Encoding.UTF8.GetString(StatementFiles.Csv([new(1,Row with{Merchant="=HYPERLINK(1)",Description="@test"},[])]));
        Assert.Contains("'=HYPERLINK",csv); Assert.Contains("'@test",csv); Assert.Contains(",-12.34,",csv);
    }
    [Fact]
    public void Pdf_PaginatesLongMerchantsAndAttachmentNames()
    {
        var rows=Enumerable.Range(1,40).Select(i=>new StatementRow(i,Row with {Id=$"reference-{i}",Merchant="Laško Café - a long merchant name with a branch and street address"},
            Enumerable.Range(1,3).Select(n=>StatementFiles.AttachmentName(i,"Long merchant name including branch and address",n,"application/pdf")).ToArray())).ToArray();
        var bytes=StatementFiles.Pdf(2026,8,"Test account holder",rows,DateTimeOffset.UtcNow);
        using var pdf=PdfSharp.Pdf.IO.PdfReader.Open(new MemoryStream(bytes),PdfSharp.Pdf.IO.PdfDocumentOpenMode.Import);
        Assert.True(pdf.PageCount>3);
        var output=Environment.GetEnvironmentVariable("STATEMENT_LONG_PREVIEW_PDF");if(!string.IsNullOrWhiteSpace(output)) File.WriteAllBytes(output,bytes);
    }

    [MonthlyStatementPostgresFact]
    public async Task DurableWorker_ClaimsOnce_StoresZip_AndSurvivesNewScopes()
    {
        await using var fixture=await MonthlyExportTestDatabase.CreateAsync();
        await using(var db=fixture.Context()) { db.MonthlyStatementExports.Add(new(){CompanyInstallationId=fixture.CompanyId,OwnerUserId=fixture.OwnerId,ProviderUserId="test",Year=2026,Month=8}); await db.SaveChangesAsync(); }
        var blobs=new DocumentStorageTests.FakeBlobs(); var source=new FakeSource([Row]);
        var services=new ServiceCollection(); services.AddScoped(_=>fixture.Context()); services.AddSingleton<IPrivateDocumentBlobStore>(blobs); services.AddSingleton<IStatementTransactionSource>(source); services.AddScoped<MonthlyStatementBuilder>();
        await using var provider=services.BuildServiceProvider(); var worker=new MonthlyStatementWorker(provider.GetRequiredService<IServiceScopeFactory>(),NullLogger<MonthlyStatementWorker>.Instance);
        await Task.WhenAll(worker.RunNextAsync(default),worker.RunNextAsync(default));
        await using var read=fixture.Context(); var job=await read.MonthlyStatementExports.SingleAsync();
        Assert.Equal("ready",job.Status); Assert.Equal(1,job.Attempt); Assert.Equal(1,source.Calls); Assert.Single(blobs.Files);
        using var zip=new ZipArchive(new MemoryStream(blobs.Files[job.BlobKey])); Assert.Equal(2,zip.Entries.Count);
    }
    private sealed class FakeSource(IReadOnlyList<StatementTransaction> rows):IStatementTransactionSource
    { public int Calls; public Task<IReadOnlyList<StatementTransaction>> LoadAsync(string provider,int year,int month,CancellationToken ct){Interlocked.Increment(ref Calls);return Task.FromResult(rows);} }
    private sealed class FakeProxy:IProxyHoppaRequestUseCase
    {
        public int Calls;public bool Truncated;public List<IReadOnlyDictionary<string,string?>> Queries=[];
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> request,CancellationToken ct)
        {
            Calls++;Queries.Add(request.Query);
            var data=Truncated && Calls==2?Array.Empty<object>():new object[]{new{id=Calls,transactionDate=$"2026-08-{(Calls==1?20:10):D2}T12:00:00Z",merchantName="Cafe",amount=2.5m,currency="EUR",type="CARD_PAYMENT",status="completed"}};
            return Task.FromResult(ApplicationResult<JsonElement?>.Success(JsonSerializer.SerializeToElement(new{data,pagination=new{total=2}})));
        }
    }
}

public sealed class MonthlyStatementPostgresFactAttribute : FactAttribute
{
    public MonthlyStatementPostgresFactAttribute() { if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("DOCUMENT_TEST_POSTGRES"))) Skip="Set DOCUMENT_TEST_POSTGRES for isolated migration and worker checks."; }
}
internal sealed class MonthlyExportTestDatabase(string connectionString, string database, string admin) : IAsyncDisposable
{
    public Guid CompanyId { get; }=Guid.NewGuid();
    public Guid OwnerId { get; }=Guid.NewGuid();
    public NeoBankingDbContext Context()=>new(new DbContextOptionsBuilder<NeoBankingDbContext>().UseNpgsql(connectionString).Options);
    public static async Task<MonthlyExportTestDatabase> CreateAsync()
    {
        var admin=new NpgsqlConnectionStringBuilder(Environment.GetEnvironmentVariable("DOCUMENT_TEST_POSTGRES")!){Database="postgres",Pooling=false};
        var name=$"monthly_test_{Guid.NewGuid():N}";
        await using var connection=new NpgsqlConnection(admin.ConnectionString);await connection.OpenAsync();
        await using(var create=new NpgsqlCommand($"CREATE DATABASE \"{name}\"",connection)) await create.ExecuteNonQueryAsync();
        var test=new NpgsqlConnectionStringBuilder(admin.ConnectionString){Database=name};
        var fixture=new MonthlyExportTestDatabase(test.ConnectionString,name,admin.ConnectionString);
        try
        {
            await using var db=fixture.Context();await db.Database.MigrateAsync();Assert.False(db.Database.HasPendingModelChanges());
            db.CompanyInstallations.Add(new(){Id=fixture.CompanyId,Slug=name,LegalName="Test",DisplayName="Test",Status="active"});
            db.Users.Add(new(){Id=fixture.OwnerId,CompanyInstallationId=fixture.CompanyId,Email="test@example.test",EmailNormalized="TEST@EXAMPLE.TEST",Status="active"});
            await db.SaveChangesAsync();return fixture;
        }
        catch {await fixture.DisposeAsync();throw;}
    }
    public async ValueTask DisposeAsync()
    {
        await using var connection=new NpgsqlConnection(admin);await connection.OpenAsync();
        await using var drop=new NpgsqlCommand($"DROP DATABASE \"{database}\" WITH (FORCE)",connection);await drop.ExecuteNonQueryAsync();
    }
}
