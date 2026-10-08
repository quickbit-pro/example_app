using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.DTOs.Admin;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/cards")]
public sealed class AdminCardsController : HoppaProxyControllerBase
{
    public AdminCardsController(IProxyHoppaRequestUseCase proxyHoppa)
        : base(proxyHoppa)
    {
    }

    [HttpGet]
    public async Task<ActionResult<JsonElement?>> ListCards(
        [FromQuery] string? userId,
        [FromQuery] string? status,
        [FromQuery] int? limit,
        [FromQuery] string? cursor,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            "cards",
            null,
            "admin.cards.list.failed",
            "Hoppa failed to list cards.",
            cancellationToken,
            Query(("userId", userId), ("status", status), ("limit", limit), ("cursor", cursor))));
    }

    [HttpGet("{cardId}")]
    public async Task<ActionResult<JsonElement?>> GetCard(string cardId, CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            $"cards/{Segment(cardId)}",
            null,
            "admin.cards.get.failed",
            "Hoppa failed to load card.",
            cancellationToken));
    }

    [HttpPost("{cardId}/decisions")]
    public async Task<ActionResult<JsonElement?>> CreateDecision(
        string cardId,
        [FromBody] AdminCardDecisionRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = cardId;
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "admin.cards.decisions.unsupported",
            "Hoppa staging OpenAPI does not expose a card decision endpoint.");
    }

    [HttpPatch("{cardId}/status")]
    public async Task<ActionResult<JsonElement?>> UpdateStatus(
        string cardId,
        [FromBody] AdminStatusUpdateRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = cardId;
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "admin.cards.status.unsupported",
            "Hoppa staging OpenAPI exposes explicit card lifecycle actions, not a generic card status update endpoint.");
    }
}
