using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Controllers;
using NeoBanking.Api.Documents;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Xunit;
namespace NeoBanking.Api.Tests;
public sealed class TransactionDocumentHttpTests
{
    internal static readonly Guid Company = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    internal static readonly Guid Owner = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    [Fact]
    public async Task ActualHttpPipeline_UploadsAttachesListsAndRejectsInvalidRequests()
    {
        var builder = WebApplication.CreateBuilder(); builder.Logging.ClearProviders();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        // Share one database between request scopes.
        var dbOptions = new DbContextOptionsBuilder<NeoBankingDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options;
        builder.Services.AddScoped(_ => new NeoBankingDbContext(dbOptions));
        builder.Services.AddSingleton<IPrivateDocumentBlobStore, DocumentStorageTests.FakeBlobs>();
        builder.Services.AddScoped<DocumentService>(); builder.Services.AddScoped<TransactionDocumentService>();
        builder.Services.AddControllers().AddApplicationPart(typeof(MobileTransactionDocumentsController).Assembly);
        builder.Services.AddAuthentication("invoice-test").AddScheme<AuthenticationSchemeOptions, InvoiceTestAuth>("invoice-test", _ => {});
        builder.Services.AddAuthorization(o => o.AddPolicy(AuthorizationPolicyNames.User, p => p.RequireAuthenticatedUser()));
        await using var app = builder.Build(); app.UseAuthentication(); app.UseAuthorization(); app.MapControllers();
        await using (var scope = app.Services.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<NeoBankingDbContext>();
            db.Users.Add(new ApplicationUser { Id = Owner, CompanyInstallationId = Company }); await db.SaveChangesAsync();
        }
        await app.StartAsync();
        try
        {
            var address = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single();
            using var client = new HttpClient { BaseAddress = new Uri(address) };
            const string endpoint = "/api/v1/mobile/transaction-documents";
            Assert.Equal(HttpStatusCode.Unauthorized,(await client.GetAsync(endpoint+"?transactionId=test")).StatusCode);
            client.DefaultRequestHeaders.Add("X-Invoice-Test", "owner");
            using var multipart = new MultipartFormDataContent();
            multipart.Add(new ByteArrayContent(Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aDfcAAAAASUVORK5CYII=")), "file", "invoice.png");
            var upload = await client.PostAsync("/api/v1/mobile/documents", multipart);
            Assert.Equal(HttpStatusCode.OK, upload.StatusCode);
            var document = await upload.Content.ReadFromJsonAsync<JsonElement>();
            var input = new { transactionId = "test-transaction", documentId = document.GetProperty("id").GetString() };
            var attached = await client.PostAsJsonAsync(endpoint, input);
            Assert.Equal(HttpStatusCode.OK, attached.StatusCode);
            Assert.Equal(HttpStatusCode.OK,(await client.PostAsJsonAsync(endpoint,input)).StatusCode);
            var rows = await client.GetFromJsonAsync<JsonElement>(endpoint+"?transactionId=test-transaction");
            Assert.Equal(1, rows.GetArrayLength());
            Assert.Equal("invoice.png", rows[0].GetProperty("document").GetProperty("fileName").GetString());
            Assert.Equal(HttpStatusCode.BadRequest,(await client.PostAsJsonAsync(endpoint, new { transactionId="", input.documentId })).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest,(await client.PostAsJsonAsync(endpoint, new { transactionId=new string('x',201), input.documentId })).StatusCode);
        }
        finally { await app.StopAsync(); }
    }
}
public sealed class InvoiceTestAuth(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync() => Task.FromResult(
        Request.Headers["X-Invoice-Test"] != "owner" ? AuthenticateResult.NoResult() :
        AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity(new[] {
            new Claim("company_installation_id", TransactionDocumentHttpTests.Company.ToString()),
            new Claim("local_user_id", TransactionDocumentHttpTests.Owner.ToString())
        }, Scheme.Name)), Scheme.Name)));
}
