using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Admin;
using NeoBanking.Application.Security;

namespace NeoBanking.Api.Controllers;

/// <summary>AI briefing for the Overview; cached per installation and period.</summary>
[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/insights")]
public sealed class AdminInsightsController(AdminInsightsService insights) : ApiControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get([FromQuery] int? range, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        return Ok(await insights.GetAsync(companyId, Range(range), refresh: false, cancellationToken));
    }

    [HttpPost("refresh")]
    public async Task<IActionResult> Refresh([FromQuery] int? range, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        return Ok(await insights.GetAsync(companyId, Range(range), refresh: true, cancellationToken));
    }

    private static int Range(int? range) => range is 7 or 30 or 90 ? range.Value : 30;
}
