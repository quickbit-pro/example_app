using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
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
using NeoBanking.Api.Statements;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Xunit;
namespace NeoBanking.Api.Tests;
public sealed class MonthlyStatementHttpTests
{
    internal static readonly Guid Company=Guid.NewGuid(), Owner=Guid.NewGuid(), Other=Guid.NewGuid();
    [Fact]
    public async Task HttpPipeline_QueuesWithTrustedIdentity_ProtectsStatus_AndDownloadsOnlySignedArchive()
    {
        var builder=WebApplication.CreateBuilder();builder.Logging.ClearProviders();builder.WebHost.UseUrls("http://127.0.0.1:0");
        var options=new DbContextOptionsBuilder<NeoBankingDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options;
        builder.Services.AddScoped(_=>new NeoBankingDbContext(options));
        var blobs=new DocumentStorageTests.FakeBlobs();builder.Services.AddSingleton<IPrivateDocumentBlobStore>(blobs);
        builder.Services.AddDataProtection();builder.Services.AddSingleton<StatementDownloadTokens>();builder.Services.AddScoped<MonthlyStatementService>();
        builder.Services.AddControllers().AddApplicationPart(typeof(MonthlyStatementsController).Assembly);
        builder.Services.AddAuthentication("statement-test").AddScheme<AuthenticationSchemeOptions,StatementTestAuth>("statement-test",_=>{});
        builder.Services.AddAuthorization(o=>o.AddPolicy(AuthorizationPolicyNames.User,p=>p.RequireAuthenticatedUser()));
        await using var app=builder.Build();app.UseAuthentication();app.UseAuthorization();app.MapControllers();
        await using(var scope=app.Services.CreateAsyncScope()) {var db=scope.ServiceProvider.GetRequiredService<NeoBankingDbContext>();db.Users.AddRange(new ApplicationUser{Id=Owner,CompanyInstallationId=Company},new ApplicationUser{Id=Other,CompanyInstallationId=Company});await db.SaveChangesAsync();}
        await app.StartAsync();
        try
        {
            using var client=new HttpClient{BaseAddress=new Uri(app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single())};
            const string path="/api/v1/mobile/monthly-statements";
            Assert.Equal(HttpStatusCode.Unauthorized,(await client.GetAsync(path)).StatusCode);
            client.DefaultRequestHeaders.Add("X-Statement-Test","owner");
            var input=new {id=Guid.NewGuid(),year=2026,month=8,providerUserId="forged-user"};
            var response=await client.PostAsJsonAsync(path,input);Assert.Equal(HttpStatusCode.OK,response.StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest,(await client.PostAsJsonAsync(path,new{id=Guid.NewGuid(),year=2026,month=13})).StatusCode);
            await using(var scope=app.Services.CreateAsyncScope())
            {
                var db=scope.ServiceProvider.GetRequiredService<NeoBankingDbContext>();var job=await db.MonthlyStatementExports.SingleAsync();
                Assert.Equal("trusted-provider",job.ProviderUserId);Assert.Equal(Owner,job.OwnerUserId);
                job.Status="ready";job.BlobKey="archive";blobs.Files["archive"]="zip-fixture"u8.ToArray();await db.SaveChangesAsync();
            }
            var ready=await client.GetFromJsonAsync<MonthlyStatementDto>(path+"/"+input.id);Assert.NotNull(ready!.DownloadPath);
            client.DefaultRequestHeaders.Remove("X-Statement-Test");client.DefaultRequestHeaders.Add("X-Statement-Test","other");
            Assert.Equal(HttpStatusCode.NotFound,(await client.GetAsync(path+"/"+input.id)).StatusCode);
            client.DefaultRequestHeaders.Remove("X-Statement-Test");
            var file=await client.GetAsync(ready.DownloadPath);Assert.Equal(HttpStatusCode.OK,file.StatusCode);Assert.Equal("application/zip",file.Content.Headers.ContentType!.MediaType);
            Assert.Equal("zip-fixture",await file.Content.ReadAsStringAsync());
            Assert.Equal(HttpStatusCode.Unauthorized,(await client.GetAsync("/api/v1/statement-download?token=invalid")).StatusCode);
            await using(var scope=app.Services.CreateAsyncScope()) {var db=scope.ServiceProvider.GetRequiredService<NeoBankingDbContext>();(await db.Users.SingleAsync(u=>u.Id==Owner)).LockedAt=DateTimeOffset.UtcNow;await db.SaveChangesAsync();}
            Assert.Equal(HttpStatusCode.NotFound,(await client.GetAsync(ready.DownloadPath)).StatusCode);
        }
        finally {await app.StopAsync();}
    }
}
public sealed class StatementTestAuth(IOptionsMonitor<AuthenticationSchemeOptions> options,ILoggerFactory logger,UrlEncoder encoder):AuthenticationHandler<AuthenticationSchemeOptions>(options,logger,encoder)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync()=>Task.FromResult(
        Request.Headers["X-Statement-Test"].Count==0?AuthenticateResult.NoResult():AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity(new[]{
            new Claim("company_installation_id",MonthlyStatementHttpTests.Company.ToString()),
            new Claim("local_user_id",(Request.Headers["X-Statement-Test"]=="owner"?MonthlyStatementHttpTests.Owner:MonthlyStatementHttpTests.Other).ToString()),new Claim("hoppa_user_id","trusted-provider")},Scheme.Name)),Scheme.Name)));
}
