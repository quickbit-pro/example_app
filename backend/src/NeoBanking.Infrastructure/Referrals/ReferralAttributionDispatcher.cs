using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using NeoBanking.Application.Common;
using NeoBanking.Application.Interfaces;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Infrastructure.Referrals;

/// <summary>At-least-once delivery after local commit, with a database lease and an engine command receipt.</summary>
public sealed class ReferralAttributionDispatcher(IServiceScopeFactory scopes, ILogger<ReferralAttributionDispatcher> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while(!stoppingToken.IsCancellationRequested)
        {
            try { await DispatchDueAsync(stoppingToken); }
            catch(OperationCanceledException) when(stoppingToken.IsCancellationRequested) { break; }
            catch(Exception exception) { logger.LogError(exception,"Referral attribution delivery pass failed."); }
            await Task.Delay(TimeSpan.FromSeconds(10),stoppingToken);
        }
    }

    public async Task DispatchDueAsync(CancellationToken ct)
    {
        using var scope=scopes.CreateScope();
        var db=scope.ServiceProvider.GetRequiredService<NeoBankingDbContext>();
        var client=scope.ServiceProvider.GetRequiredService<IHoppaClient>();
        var now=DateTimeOffset.UtcNow;
        var companyId=await db.CompanyInstallations.Where(x=>x.Slug=="default").Select(x=>(Guid?)x.Id).SingleOrDefaultAsync(ct);
        if(companyId is null) return;
        var uncertainCutoff=now.AddMinutes(-5);
        await db.ReferralSignupAttempts.Where(x=>x.CompanyInstallationId==companyId && x.State=="CREATING" && x.UpdatedAt<uncertainCutoff)
            .ExecuteUpdateAsync(u=>u.SetProperty(x=>x.State,"CREATION_UNCERTAIN")
                .SetProperty(x=>x.FailureReason,"UPSTREAM_CREATE_OUTCOME_UNKNOWN").SetProperty(x=>x.UpdatedAt,now),ct);
        var quoteRetentionCutoff=now.AddDays(-1);
        await db.ReferralSignupAttempts.Where(x=>x.CompanyInstallationId==companyId && x.State=="QUOTED" && x.CreatedAt<quoteRetentionCutoff)
            .ExecuteDeleteAsync(ct);
        var ids=await db.ReferralAttributionIntents.AsNoTracking().Where(x=>x.CompanyInstallationId==companyId && x.State=="PENDING" &&
            x.DueAt<=now && (x.LeaseUntil==null || x.LeaseUntil<now)).OrderByDescending(x=>x.Kind=="SIGNUP_SIGNALS").ThenBy(x=>x.DueAt).Select(x=>x.Id).Take(25).ToListAsync(ct);
        foreach(var id in ids)
        {
            var lease=Guid.NewGuid(); var claimTime=DateTimeOffset.UtcNow;
            var claimed=await db.ReferralAttributionIntents.Where(x=>x.Id==id && x.CompanyInstallationId==companyId && x.State=="PENDING" && x.DueAt<=claimTime &&
                (x.LeaseUntil==null || x.LeaseUntil<claimTime)).ExecuteUpdateAsync(update=>update
                .SetProperty(x=>x.LeaseToken,lease).SetProperty(x=>x.LeaseUntil,claimTime.AddMinutes(5)),ct);
            if(claimed!=1) continue;
            var intent=await db.ReferralAttributionIntents.AsNoTracking().SingleAsync(x=>x.Id==id,ct);
            if(intent.Kind=="SIGNUP_SIGNALS" && intent.CreatedAt<DateTimeOffset.UtcNow.AddDays(-1))
            {
                await db.ReferralAttributionIntents.Where(x=>x.Id==id&&x.LeaseToken==lease).ExecuteUpdateAsync(u=>u
                    .SetProperty(x=>x.State,"UNAVAILABLE").SetProperty(x=>x.Reason,"SIGNAL_DELIVERY_EXPIRED")
                    .SetProperty(x=>x.PayloadJson,"{}").SetProperty(x=>x.LeaseToken,(Guid?)null).SetProperty(x=>x.LeaseUntil,(DateTimeOffset?)null),ct);
                continue;
            }
            var result=intent.Kind=="SIGNUP_SIGNALS"
                ? await client.SendAsync<JsonElement,JsonElement?>(new HoppaRequest<JsonElement>
                    {Method=HttpMethod.Post,Path="/api/v2/referrals/signup-signals",Body=JsonSerializer.Deserialize<JsonElement>(intent.PayloadJson),FailureCode="referral.signals.failed"},ct)
                : await LookupOrDeliverAsync(client,intent,ct);
            var state="PENDING"; string? reason=result.Error?.Code; string? receipt=null;
            if(result.IsSuccess && result.Value is {} body)
            {
                receipt=body.GetRawText();
                state=intent.Kind=="SIGNUP_SIGNALS" ? Read(body,"status") switch
                {"RECORDED"=>"APPLIED","CONFIGURATION_REQUIRED"=>"PENDING","NO_OBSERVATIONS"=>"NOT_AVAILABLE",_=>"PENDING"} : Outcome(Read(body,"status"));
                reason=intent.Kind=="SIGNUP_SIGNALS" ? Read(body,"status") : Read(body,"reason");
                if(state=="PENDING" && reason!="CONFIGURATION_REQUIRED") reason="UNRECOGNIZED_ENGINE_RESULT";
            }
            else if(result.Error?.StatusCode is 400 or 403 or 409 or 422)
            {
                state="NEEDS_REVIEW"; reason=result.Error.Code;
            }
            var payload=intent.Kind=="SIGNUP_SIGNALS" && state!="PENDING" ? "{}" : intent.PayloadJson;
            var next=DateTimeOffset.UtcNow.AddSeconds(Math.Min(3600,10*Math.Pow(2,Math.Min(intent.Attempts,8))));
            await db.ReferralAttributionIntents.Where(x=>x.Id==id && x.LeaseToken==lease).ExecuteUpdateAsync(update=>update
                .SetProperty(x=>x.State,state).SetProperty(x=>x.Reason,reason).SetProperty(x=>x.ResultJson,receipt).SetProperty(x=>x.PayloadJson,payload)
                .SetProperty(x=>x.Attempts,x=>x.Attempts+1).SetProperty(x=>x.DueAt,next)
                .SetProperty(x=>x.LeaseToken,(Guid?)null).SetProperty(x=>x.LeaseUntil,(DateTimeOffset?)null)
                .SetProperty(x=>x.UpdatedAt,DateTimeOffset.UtcNow),ct);
        }
    }

    public static async Task<ApplicationResult<JsonElement?>> LookupOrDeliverAsync(IHoppaClient client,ReferralAttributionIntent intent,CancellationToken ct)
    {
        var path=$"/api/v2/users/{Uri.EscapeDataString(intent.ProviderUserId)}/referrals/attribution-commands";
        var receipt=await client.SendAsync<object?,JsonElement?>(new HoppaRequest<object?>
        {
            Method=HttpMethod.Get,Path=$"{path}/{intent.Id:D}",FailureCode="referral.receipt_lookup_failed"
        },ct);
        // Transport/auth failures do not justify another post. Missing receipt is the only delivery signal.
        if(receipt.IsSuccess || receipt.Error?.StatusCode!=404) return receipt;
        return await client.SendAsync<JsonElement,JsonElement?>(new HoppaRequest<JsonElement>
        {
            Method=HttpMethod.Post,Path=path,Body=JsonSerializer.Deserialize<JsonElement>(intent.PayloadJson),
            FailureCode="referral.command_delivery_failed"
        },ct);
    }

    public static string Outcome(string? status) => status?.ToUpperInvariant() switch
    {
        "COMMITTED"=>"APPLIED", "REJECTED"=>"REJECTED", "NEEDS_REVIEW"=>"NEEDS_REVIEW", _=>"PENDING"
    };
    private static string? Read(JsonElement value,string name) => value.EnumerateObject()
        .Where(x=>string.Equals(x.Name,name,StringComparison.OrdinalIgnoreCase)).Select(x=>x.Value.ToString()).FirstOrDefault();
}
