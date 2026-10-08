using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Company;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Auth;
using NeoBanking.Application.Interfaces;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Email;
using NeoBanking.Infrastructure.Persistence;
using NeoBanking.Infrastructure.Referrals;
using Npgsql;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class ReferralPostgresFactAttribute : FactAttribute
{
    public ReferralPostgresFactAttribute()
    {
        if(string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("REFERRAL_FACADE_TEST_POSTGRES")))
            Skip="Set REFERRAL_FACADE_TEST_POSTGRES to a local disposable PostgreSQL server; this test creates/drops its own database.";
    }
}

public class ReferralPostgresTests
{
    [ReferralPostgresFact]
    public Task MigrationRepeated_CompetingSignupCreatesOnce_CompetingWorkersDeliverOnce()=>RunScenario(false);
    [ReferralPostgresFact]
    public Task CompetingRequestsForSameQuotedAttemptClaimCreationOnce()=>RunScenario(true);

    private async Task RunScenario(bool sharedAttempt)
    {
        var source=Environment.GetEnvironmentVariable("REFERRAL_FACADE_TEST_POSTGRES")!;
        var name=$"referral_facade_{Guid.NewGuid():N}";
        await using var admin=new NpgsqlConnection(source);await admin.OpenAsync();
        await using(var create=new NpgsqlCommand($"CREATE DATABASE \"{name}\"",admin))await create.ExecuteNonQueryAsync();
        var builder=new NpgsqlConnectionStringBuilder(source){Database=name};var cs=builder.ConnectionString;
        try
        {
            await using(var db=Db(cs))
            {
                await db.Database.MigrateAsync();await db.Database.MigrateAsync();
                Assert.True(await db.CompanyInstallations.AnyAsync(x=>x.Slug=="default"));
            }
            Guid? attemptKey=null;
            if(sharedAttempt)
            {
                await using var db=Db(cs); var company=await db.CompanyInstallations.SingleAsync(x=>x.Slug=="default");
                attemptKey=Guid.NewGuid();db.ReferralSignupAttempts.Add(new(){Id=attemptKey.Value,CompanyInstallationId=company.Id,State="QUOTED"});
                await db.SaveChangesAsync();
            }
            var creates=0;var journalObserved=false;
            var proxy=new Proxy(async path=>
            {
                if(path!="/api/v2/users")return;
                Interlocked.Increment(ref creates);
                await using var db=Db(cs);
                journalObserved=await db.ReferralSignupAttempts.AnyAsync(x=>x.State=="CREATING");
                await Task.Delay(80);
            });
            await using(var first=Db(cs)) await using(var second=Db(cs))
            {
                var request=new SignupRequestDto{RegistrationAttemptId=attemptKey,Email="concurrent@example.test",Password="Safe-test-password!27",ReferralCode="FRIEND1",ReferralAccepted=true};
                var replies=await Task.WhenAll(Controller(first,proxy).Signup(request,default),Controller(second,proxy).Signup(request,default));
                Assert.Contains(replies,r=>(r.Result as ObjectResult)?.StatusCode==201);
                Assert.Equal(1,creates);Assert.True(journalObserved);
            }
            Guid userId;Guid companyId;Guid attemptId;
            await using(var db=Db(cs))
            {
                var user=await db.Users.SingleAsync(x=>x.EmailNormalized=="CONCURRENT@EXAMPLE.TEST");userId=user.Id;companyId=user.CompanyInstallationId;
                var attempt=await db.ReferralSignupAttempts.SingleAsync();attemptId=attempt.Id;
                var intent=await db.ReferralAttributionIntents.SingleAsync(x=>x.Kind=="ATTRIBUTION");
                Assert.Equal("NEEDS_REVIEW",intent.State);
                intent.State="PENDING";intent.PayloadJson=JsonSerializer.Serialize(new{commandId=intent.Id,quoteId=Guid.NewGuid(),accepted=true});
                await db.SaveChangesAsync();
            }
            var client=new Client();var services=new ServiceCollection();
            services.AddDbContext<NeoBankingDbContext>(o=>o.UseNpgsql(cs));services.AddSingleton<IHoppaClient>(client);
            await using var provider=services.BuildServiceProvider();var scopes=provider.GetRequiredService<IServiceScopeFactory>();
            var one=new ReferralAttributionDispatcher(scopes,NullLogger<ReferralAttributionDispatcher>.Instance);
            var two=new ReferralAttributionDispatcher(scopes,NullLogger<ReferralAttributionDispatcher>.Instance);
            await Task.WhenAll(one.DispatchDueAsync(default),two.DispatchDueAsync(default));
            await one.DispatchDueAsync(default);
            Assert.Equal(1,client.CommandPosts);
            await using(var db=Db(cs))
            {
                var intent=await db.ReferralAttributionIntents.SingleAsync(x=>x.Kind=="ATTRIBUTION");
                Assert.Equal("APPLIED",intent.State);Assert.Null(intent.LeaseToken);Assert.Equal(1,intent.Attempts);
                var signal=await db.ReferralAttributionIntents.SingleAsync(x=>x.Kind=="SIGNUP_SIGNALS");
                Assert.Equal("APPLIED",signal.State);Assert.Equal("{}",signal.PayloadJson);
            }
        }
        finally
        {
            NpgsqlConnection.ClearAllPools();
            await using var drop=new NpgsqlCommand($"DROP DATABASE \"{name}\" WITH (FORCE)",admin);await drop.ExecuteNonQueryAsync();
        }
    }
    private static NeoBankingDbContext Db(string cs)=>new(new DbContextOptionsBuilder<NeoBankingDbContext>().UseNpgsql(cs).Options);
    private static AuthController Controller(NeoBankingDbContext db,IProxyHoppaRequestUseCase proxy)=>new(db,new PasswordHasher<ApplicationUser>(),proxy,
        Options.Create(new JwtOptions{Issuer="test",Audience="test",SigningKey=new string('t',40)}),
        Options.Create(new CompanyOptions{Features=new CompanyFeatureOptions{ReferralsEnabled=true}}),Options.Create(new EmailOptions()),null!,new LoginAttemptTracker(),NullLogger<AuthController>.Instance)
        {ControllerContext=new(){HttpContext=new DefaultHttpContext()}};
    private sealed class Proxy(Func<string,Task> before):IProxyHoppaRequestUseCase
    {
        public async Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command,CancellationToken ct)
        {
            await before(command.UpstreamPath);
            return ApplicationResult<JsonElement?>.Success(JsonSerializer.Deserialize<JsonElement>(command.UpstreamPath=="/api/v2/users"?"{\"id\":777}":"{\"valid\":true}"));
        }
    }
    private sealed class Client:IHoppaClient
    {
        public int CommandPosts;
        public async Task<ApplicationResult<TResponse>> SendAsync<TRequest,TResponse>(HoppaRequest<TRequest> request,CancellationToken ct)
        {
            if(request.Method==HttpMethod.Get)return ApplicationResult<TResponse>.Failure(new("missing","not found",404));
            if(request.Path.EndsWith("attribution-commands")){Interlocked.Increment(ref CommandPosts);await Task.Delay(80,ct);}
            return ApplicationResult<TResponse>.Success(JsonSerializer.Deserialize<TResponse>(request.Path.EndsWith("signup-signals")?"{\"status\":\"RECORDED\"}":"{\"status\":\"COMMITTED\"}")!);
        }
    }
}
