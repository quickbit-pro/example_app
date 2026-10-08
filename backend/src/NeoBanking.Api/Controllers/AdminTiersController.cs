using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.DTOs.Tiers;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/tiers")]
public sealed class AdminTiersController : HoppaProxyControllerBase
{
    public AdminTiersController(IProxyHoppaRequestUseCase proxyHoppa)
        : base(proxyHoppa)
    {
    }

    [HttpGet]
    public async Task<ActionResult<JsonElement?>> ListTiers(CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            "tiers",
            null,
            "admin.tiers.list.failed",
            "Hoppa failed to list tiers.",
            cancellationToken));
    }

    [HttpPatch("{tierCode}")]
    public async Task<ActionResult<JsonElement?>> UpdateTier(
        string tierCode,
        [FromBody] UpdateTierRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = tierCode;
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "admin.tiers.update.unsupported",
            "Hoppa staging OpenAPI does not expose a tier update endpoint.");
    }

    [HttpPost("users/{userId}")]
    public async Task<ActionResult<JsonElement?>> ChangeUserTier(
        string userId,
        [FromBody] ChangeUserTierRequestDto request,
        CancellationToken cancellationToken)
    {
        if (request.TierId is null)
        {
            return BadRequest(new
            {
                code = "admin.tiers.tier_id_required",
                message = "Hoppa requires TierId when changing a user tier."
            });
        }

        return ToActionResult(await SendHoppaAsync(
            HttpMethod.Post,
            $"/api/v2/users/{Segment(userId)}/tier",
            new SetUserTierRequestDto
            {
                TierId = request.TierId.Value,
                TierCycle = request.TierCycle
            },
            "admin.tiers.users.change.failed",
            "Hoppa failed to change user tier.",
            cancellationToken));
    }
}
