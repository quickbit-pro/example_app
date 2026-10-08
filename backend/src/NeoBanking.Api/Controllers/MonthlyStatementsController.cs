using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Documents;
using NeoBanking.Api.Statements;
using NeoBanking.Application.Security;
using NeoBanking.Infrastructure.Persistence;
namespace NeoBanking.Api.Controllers;
[Authorize(Policy=AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/monthly-statements")]
public sealed class MonthlyStatementsController(MonthlyStatementService service) : ApiControllerBase
{
    [HttpPost, EnableRateLimiting(RateLimitPolicies.PeerSensitive)]
    public async Task<ActionResult<MonthlyStatementDto>> Create(CreateMonthlyStatementDto input,CancellationToken ct) =>
        Scope(out var company,out var owner) && TryGetCurrentUserId(out var provider) ? ToActionResult(await service.CreateAsync(company,owner,provider,input,ct)) : MissingIdentity<MonthlyStatementDto>();
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<MonthlyStatementDto>>> List(CancellationToken ct) =>
        Scope(out var company,out var owner) && await service.Active(company,owner,ct) ? Ok(await service.ListAsync(company,owner,ct)) : Unauthorized();
    [HttpGet("{id:guid}")]
    public async Task<ActionResult<MonthlyStatementDto>> Get(Guid id,CancellationToken ct)
    {
        if(!Scope(out var company,out var owner) || !await service.Active(company,owner,ct)) return Unauthorized();
        var result=await service.GetAsync(company,owner,id,ct); return result is null ? NotFound() : Ok(result);
    }
    private bool Scope(out Guid company,out Guid owner)
    { owner=Guid.Empty; return TryGetCompanyInstallationId(out company) && company!=Guid.Empty && TryGetLocalUserId(out var raw) && Guid.TryParse(raw,out owner) && owner!=Guid.Empty; }
}
[AllowAnonymous]
public sealed class StatementDownloadController(NeoBankingDbContext db,IPrivateDocumentBlobStore blobs,StatementDownloadTokens tokens) : ControllerBase
{
    [HttpGet("api/v1/statement-download")]
    public async Task<IActionResult> Download([FromQuery] string token,CancellationToken ct)
    {
        Response.Headers.CacheControl="private, no-store"; Response.Headers.XContentTypeOptions="nosniff"; Response.Headers["Referrer-Policy"]="no-referrer";
        var identity=tokens.Read(token); if(identity is null) return Unauthorized(); var (company,owner,id)=identity.Value;
        var job=await db.MonthlyStatementExports.AsNoTracking().SingleOrDefaultAsync(j=>j.Id==id && j.CompanyInstallationId==company && j.OwnerUserId==owner && j.Status=="ready" &&
            db.Users.Any(u=>u.Id==owner && u.CompanyInstallationId==company && u.LockedAt==null),ct);
        if(job is null) return NotFound();
        try { return File(await blobs.ReadAsync(job.BlobKey,ct),"application/zip",$"statement-{job.Year:D4}-{job.Month:D2}.zip"); }
        catch(Azure.RequestFailedException e) when(e.Status==404) { return NotFound(); }
    }
}
