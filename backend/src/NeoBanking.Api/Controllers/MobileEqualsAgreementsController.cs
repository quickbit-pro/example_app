using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Company;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/agreements/equals")]
public sealed class MobileEqualsAgreementsController(NeoBankingDbContext db,
    EqualsConsentService consent, IOptions<CompanyOptions> options) : ApiControllerBase
{
    private async Task<ApplicationUser?> CurrentUser(CancellationToken ct)
    {
        if (!TryGetLocalUserId(out var id) || !Guid.TryParse(id, out var userId) ||
            !TryGetCompanyInstallationId(out var companyId)) return null;
        return await db.Users.SingleOrDefaultAsync(x => x.Id == userId &&
            x.CompanyInstallationId == companyId, ct);
    }

    [HttpGet("status")]
    public async Task<IActionResult> Status(CancellationToken ct)
    {
        var user = await CurrentUser(ct);
        if (user is null) return Unauthorized();
        return Ok(await consent.StatusAsync(user, ct));
    }

    [HttpPost("accept")]
    public async Task<IActionResult> Accept([FromBody] AcceptEqualsAgreements request, CancellationToken ct)
    {
        var user = await CurrentUser(ct);
        if (user is null) return Unauthorized();
        var status = await consent.StatusAsync(user, ct);
        if (!status.Required) return Ok(status);
        var documents = status.Documents;
        if (!documents.Available)
            return StatusCode(503, new { code = "equals.documents_unavailable", message = "Equals Money terms are unavailable. Please contact support." });
        if (request.Version != documents.Version || request.TermsUrl != documents.TermsUrl || request.PrivacyUrl != documents.PrivacyUrl)
            return Conflict(new { code = "equals.documents_changed", message = "The documents changed. Review the current documents before continuing." });
        if (!request.TermsAccepted || !request.PrivacyAccepted || !request.TermsAccessed)
            return BadRequest(new { code = "equals.consent_required", message = "Open the terms and separately accept the terms and privacy policy." });
        if (status.RequiresAcceptance)
        {
            EqualsConsentService.AddEvidence(db, user, await consent.BrandingAsync(ct), DateTimeOffset.UtcNow, "mobile_reagreement");
            await db.SaveChangesAsync(ct);
        }
        return Ok(new EqualsConsentStatus(true, false, documents));
    }
}

public sealed record AcceptEqualsAgreements(string Version, string TermsUrl, string PrivacyUrl,
    bool TermsAccepted, bool PrivacyAccepted, bool TermsAccessed);
