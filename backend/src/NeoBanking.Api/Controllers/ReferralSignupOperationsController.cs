using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.Security;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy=AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/referrals/signup-attempts")]
public sealed class ReferralSignupOperationsController(NeoBankingDbContext db) : ApiControllerBase
{
    [HttpGet]
    public async Task<ActionResult<object>> List([FromQuery] string? state,[FromQuery] string? search,
        [FromQuery] int page=1,[FromQuery] int pageSize=50,CancellationToken ct=default)
    {
        if(!TryGetCompanyInstallationId(out var companyId))return Unauthorized();
        var query=db.ReferralSignupAttempts.AsNoTracking().Where(x=>x.CompanyInstallationId==companyId&&x.State!="QUOTED");
        if(!string.IsNullOrWhiteSpace(state))query=query.Where(x=>x.State==state);
        if(!string.IsNullOrWhiteSpace(search)){var term=search.Trim().ToUpperInvariant();query=query.Where(x=>x.EmailNormalized!=null&&x.EmailNormalized.Contains(term));}
        page=Math.Max(1,page);pageSize=Math.Clamp(pageSize,1,200);
        var total=await query.CountAsync(ct);
        var items=await query.OrderByDescending(x=>x.CreatedAt).ThenByDescending(x=>x.Id).Skip((page-1)*pageSize).Take(pageSize)
            .Select(x=>new{x.Id,x.State,x.EmailNormalized,x.LocalUserId,x.ProviderUserId,x.FailureReason,x.CreatedAt,x.UpdatedAt}).ToListAsync(ct);
        Response.Headers.CacheControl="no-store";
        return Ok(new{items,total,page,pageSize});
    }
    [HttpGet("{attemptId:guid}")]
    public async Task<ActionResult<object>> Detail(Guid attemptId,CancellationToken ct)
    {
        if(!TryGetCompanyInstallationId(out var companyId))return Unauthorized();
        var attempt=await db.ReferralSignupAttempts.AsNoTracking().Where(x=>x.Id==attemptId&&x.CompanyInstallationId==companyId)
            .Select(x=>new{x.Id,x.State,x.EmailNormalized,x.LocalUserId,x.ProviderUserId,x.FailureReason,x.CreatedAt,x.UpdatedAt}).SingleOrDefaultAsync(ct);
        if(attempt is null)return NotFound();
        var deliveries=await db.ReferralAttributionIntents.AsNoTracking().Where(x=>x.SignupAttemptId==attemptId&&x.CompanyInstallationId==companyId)
            .Select(x=>new{x.Id,x.Kind,x.State,x.Reason,x.Attempts,x.DueAt,x.CreatedAt,x.UpdatedAt}).ToListAsync(ct);
        Response.Headers.CacheControl="no-store";
        return Ok(new{attempt,deliveries});
    }
}
