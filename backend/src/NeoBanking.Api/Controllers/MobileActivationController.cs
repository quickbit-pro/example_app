using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.Security;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/activation")]
public sealed class MobileActivationController(NeoBankingDbContext db) : ApiControllerBase
{
    // This only records presentation progress; it never grants banking/KYC eligibility.
    [HttpPost]
    public async Task<IActionResult> RecordProgress(ActivationProgressRequest request, CancellationToken ct)
    {
        if (!TryGetLocalUserId(out var id) || !Guid.TryParse(id, out var userId) ||
            !TryGetCompanyInstallationId(out var companyId)) return Unauthorized();
        var users = db.Users.Where(u => u.Id == userId && u.CompanyInstallationId == companyId);
        var now = DateTimeOffset.UtcNow;
        if (request.HasCompletedDeposit)
            await users.Where(u => u.FirstDepositObservedAt == null)
                .ExecuteUpdateAsync(s => s.SetProperty(u => u.FirstDepositObservedAt, now), ct);
        // Conditional update makes claiming the introduction atomic across devices.
        var showIntroduction = request.ClaimIntroduction && await users
            .Where(u => u.ActivationIntroShownAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.ActivationIntroShownAt, now), ct) == 1;
        var progress = await users.AsNoTracking().Select(u => new {
            HasCompletedDeposit = u.FirstDepositObservedAt != null,
            IntroductionSeen = u.ActivationIntroShownAt != null,
        }).SingleOrDefaultAsync(ct);
        if (progress is null) return NotFound();
        return Ok(new { progress.HasCompletedDeposit, progress.IntroductionSeen, ShowIntroduction = showIntroduction });
    }

    public sealed record ActivationProgressRequest(bool HasCompletedDeposit, bool ClaimIntroduction);
}
