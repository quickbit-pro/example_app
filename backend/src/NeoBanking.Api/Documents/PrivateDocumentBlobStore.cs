using Azure;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Microsoft.Extensions.Options;

namespace NeoBanking.Api.Documents;
public sealed class DocumentStorageOptions
{
    public string ConnectionString { get; set; } = string.Empty;
    public string Container { get; set; } = string.Empty;
}
public interface IPrivateDocumentBlobStore
{
    bool Configured { get; }
    Task UploadAsync(string key, byte[] bytes, string contentType, CancellationToken ct);
    Task<Stream> ReadAsync(string key, CancellationToken ct);
}
public sealed class PrivateDocumentBlobStore(IOptions<DocumentStorageOptions> options) : IPrivateDocumentBlobStore
{
    private readonly DocumentStorageOptions settings = options.Value;
    private BlobContainerClient? container;
    public bool Configured => !string.IsNullOrWhiteSpace(settings.ConnectionString) && !string.IsNullOrWhiteSpace(settings.Container);
    private BlobContainerClient Container => container ??= new BlobContainerClient(settings.ConnectionString, settings.Container,
        new BlobClientOptions { Retry = { MaxRetries = 2, NetworkTimeout = TimeSpan.FromSeconds(30) } });
    private async Task EnsurePrivateAsync(CancellationToken ct)
    {
        if (!Configured) throw new InvalidOperationException("Document storage is not configured.");
        await Container.CreateIfNotExistsAsync(PublicAccessType.None, cancellationToken: ct);
        if ((await Container.GetAccessPolicyAsync(cancellationToken: ct)).Value.BlobPublicAccess != PublicAccessType.None)
            throw new InvalidOperationException("Document storage must be private.");
    }
    public async Task UploadAsync(string key, byte[] bytes, string contentType, CancellationToken ct)
    {
        await EnsurePrivateAsync(ct);
        try
        {
            await Container.GetBlobClient(key).UploadAsync(new BinaryData(bytes), new BlobUploadOptions
            {
                Conditions = new BlobRequestConditions { IfNoneMatch = ETag.All },
                HttpHeaders = new BlobHttpHeaders { ContentType = contentType, ContentDisposition = "attachment", CacheControl = "private, no-store" }
            }, ct);
        }
        catch (RequestFailedException e) when (e.Status == 409 && e.ErrorCode == "BlobAlreadyExists" || e.Status == 412 && e.ErrorCode == "ConditionNotMet")
        { /* Same owner and SHA-256: an idempotent upload never replaces bytes. */ }
    }
    public async Task<Stream> ReadAsync(string key, CancellationToken ct) =>
        (await Container.GetBlobClient(key).DownloadStreamingAsync(cancellationToken: ct)).Value.Content;
}
public static class DocumentServices
{
    public static void Add(IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<DocumentStorageOptions>(configuration.GetSection("DocumentStorage"));
        services.AddSingleton<IPrivateDocumentBlobStore, PrivateDocumentBlobStore>();
        services.AddScoped<DocumentService>();
        services.AddScoped<TransactionDocumentService>();
        services.AddDataProtection();
        services.AddSingleton<NeoBanking.Api.Statements.StatementDownloadTokens>();
        services.AddScoped<NeoBanking.Api.Statements.MonthlyStatementService>();
        services.AddScoped<NeoBanking.Api.Statements.IStatementTransactionSource, NeoBanking.Api.Statements.StatementTransactionSource>();
        services.AddScoped<NeoBanking.Api.Statements.MonthlyStatementBuilder>();
        services.AddHostedService<NeoBanking.Api.Statements.MonthlyStatementWorker>();
    }
}
