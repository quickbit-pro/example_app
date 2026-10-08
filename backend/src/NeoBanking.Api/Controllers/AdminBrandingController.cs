using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.DTOs.Branding;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/branding")]
public sealed class AdminBrandingController : HoppaProxyControllerBase
{
    public AdminBrandingController(IProxyHoppaRequestUseCase proxyHoppa)
        : base(proxyHoppa)
    {
    }

    [HttpGet]
    public async Task<ActionResult<JsonElement?>> GetBranding(CancellationToken cancellationToken)
    {
        _ = cancellationToken;

        return NotImplementedProblem(
            "admin.branding.get.unsupported",
            "Hoppa staging OpenAPI does not expose an admin branding endpoint.");
    }

    [HttpPut]
    public async Task<ActionResult<JsonElement?>> UpdateBranding(
        [FromBody] UpdateCompanyBrandingRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "admin.branding.update.unsupported",
            "Hoppa staging OpenAPI does not expose an admin branding endpoint.");
    }
}
