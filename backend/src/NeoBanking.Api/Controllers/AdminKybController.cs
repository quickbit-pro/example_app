using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.DTOs.Admin;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/kyb")]
public sealed class AdminKybController : HoppaProxyControllerBase
{
    public AdminKybController(IProxyHoppaRequestUseCase proxyHoppa)
        : base(proxyHoppa)
    {
    }

    [HttpGet("cases")]
    public async Task<ActionResult<JsonElement?>> ListCases(
        [FromQuery] string? status,
        [FromQuery] int? limit,
        [FromQuery] string? cursor,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            "business/onboarding/application",
            null,
            "admin.kyb.cases.list.failed",
            "Hoppa failed to list KYB cases.",
            cancellationToken,
            Query(("status", status), ("limit", limit), ("cursor", cursor))));
    }

    [HttpGet("cases/{caseId}")]
    public async Task<ActionResult<JsonElement?>> GetCase(string caseId, CancellationToken cancellationToken)
    {
        _ = caseId;
        _ = cancellationToken;

        return NotImplementedProblem(
            "admin.kyb.cases.get.unsupported",
            "Hoppa staging OpenAPI does not expose a KYB case detail endpoint.");
    }

    [HttpPost("cases/{caseId}/decisions")]
    public async Task<ActionResult<JsonElement?>> CreateDecision(
        string caseId,
        [FromBody] AdminUserDecisionRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = caseId;
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "admin.kyb.cases.decisions.unsupported",
            "Hoppa staging OpenAPI does not expose a KYB decision endpoint.");
    }
}
