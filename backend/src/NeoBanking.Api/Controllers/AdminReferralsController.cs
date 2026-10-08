using System.Text.Json;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/referrals")]
public sealed partial class AdminReferralsController(IProxyHoppaRequestUseCase proxy) : HoppaProxyControllerBase(proxy)
{
    [HttpGet("capabilities")]
    public Task<ActionResult<JsonElement?>> Capabilities(CancellationToken ct) => Forward(HttpMethod.Get, "capabilities", null, ct);
    [HttpPost("programs/{programId:guid}/simulate")]
    public Task<ActionResult<JsonElement?>> Simulate(Guid programId, [FromBody] JsonElement body, CancellationToken ct) => Forward(HttpMethod.Post, $"programs/{programId:D}/simulate", body, ct);
    [HttpGet("programs/{programId:guid}/versions")]
    public Task<ActionResult<JsonElement?>> Versions(Guid programId, CancellationToken ct) => Forward(HttpMethod.Get, $"programs/{programId:D}/versions", null, ct);
    [HttpPost("programs/{programId:guid}/drafts")]
    public Task<ActionResult<JsonElement?>> Draft(Guid programId, [FromBody] JsonElement body, CancellationToken ct) => Forward(HttpMethod.Post, $"programs/{programId:D}/drafts", body, ct);
    [HttpPut("programs/{programId:guid}/drafts/{draftId:guid}")]
    public Task<ActionResult<JsonElement?>> UpdateDraft(Guid programId, Guid draftId, [FromBody] JsonElement body, CancellationToken ct) => Forward(HttpMethod.Put, $"programs/{programId:D}/drafts/{draftId:D}", body, ct);
    [HttpPost("programs/{programId:guid}/drafts/{draftId:guid}/change-preview")]
    public Task<ActionResult<JsonElement?>> Preview(Guid programId, Guid draftId, [FromBody] JsonElement body, CancellationToken ct) => Forward(HttpMethod.Post, $"programs/{programId:D}/drafts/{draftId:D}/change-preview", body, ct);
    [HttpPost("programs/{programId:guid}/drafts/{draftId:guid}/publish")]
    public Task<ActionResult<JsonElement?>> Publish(Guid programId, Guid draftId, [FromBody] JsonElement body, CancellationToken ct) => Forward(HttpMethod.Post, $"programs/{programId:D}/drafts/{draftId:D}/publish", body, ct);
    [HttpGet("programs/{programId:guid}/team")]
    public Task<ActionResult<JsonElement?>> Team(Guid programId, CancellationToken ct) => Forward(HttpMethod.Get, $"programs/{programId:D}/team", null, ct);
    [HttpPut("programs/{programId:guid}/team/{childId:int:min(1)}/{parentId:int:min(1)}")]
    public Task<ActionResult<JsonElement?>> Parent(Guid programId, int childId, int parentId, CancellationToken ct) => Forward(HttpMethod.Put, $"programs/{programId:D}/team/{childId}/{parentId}", null, ct);

    [HttpGet("programs")]
    public Task<ActionResult<JsonElement?>> Programs(CancellationToken ct) => Forward(HttpMethod.Get, "programs", null, ct);
    [HttpGet("program")]
    public Task<ActionResult<JsonElement?>> Program([FromQuery] Guid? programId, CancellationToken ct) => Forward(HttpMethod.Get, "program", null, ct, programId);
    [HttpPut("program")]
    public Task<ActionResult<JsonElement?>> Update([FromQuery] Guid? programId, [FromBody] JsonElement request, CancellationToken ct) => Forward(HttpMethod.Put, "program", request, ct, programId);
    [HttpPost("programs")]
    public Task<ActionResult<JsonElement?>> Create([FromBody] JsonElement request, CancellationToken ct) => Forward(HttpMethod.Post, "programs", request, ct);
    [HttpGet("overview")]
    public Task<ActionResult<JsonElement?>> Overview([FromQuery] Guid? programId, CancellationToken ct) => Forward(HttpMethod.Get, "overview", null, ct, programId);
    [HttpGet("invite-benefits")]
    public Task<ActionResult<JsonElement?>> InviteBenefits([FromQuery] Guid? programId, CancellationToken ct) => Forward(HttpMethod.Get, "invite-benefits", null, ct, programId);
    [HttpPut("invite-benefits")]
    public Task<ActionResult<JsonElement?>> UpdateInviteBenefit([FromQuery] Guid? programId, [FromBody] JsonElement request, CancellationToken ct) => Forward(HttpMethod.Put, "invite-benefits", request, ct, programId);
    [HttpGet("programs/{programId:guid}/members")]
    public Task<ActionResult<JsonElement?>> Members(Guid programId, CancellationToken ct) => Forward(HttpMethod.Get, $"programs/{programId:D}/members", null, ct);
    [HttpPut("programs/{programId:guid}/members/{userId:int:min(1)}")]
    public Task<ActionResult<JsonElement?>> Member(Guid programId, int userId, [FromBody] JsonElement request, CancellationToken ct) => Forward(HttpMethod.Put, $"programs/{programId:D}/members/{userId}", request, ct);
    [HttpGet("options")]
    public Task<ActionResult<JsonElement?>> Options([FromQuery] string? search, CancellationToken ct) => Forward(HttpMethod.Get, "options", null, ct, search: search);

    // Referral v2: partner report, level assignments, ledger, metrics, credits and reconciliation.
    [HttpGet("programs/{programId:guid}/members/{userId:int:min(1)}/report")]
    public Task<ActionResult<JsonElement?>> MemberReport(Guid programId, int userId, CancellationToken ct) => Forward(HttpMethod.Get, $"programs/{programId:D}/members/{userId}/report", null, ct);
    [HttpGet("programs/{programId:guid}/level-assignments")]
    public Task<ActionResult<JsonElement?>> LevelAssignments(Guid programId, CancellationToken ct) => Forward(HttpMethod.Get, $"programs/{programId:D}/level-assignments", null, ct);
    [HttpPut("programs/{programId:guid}/level-assignments/{userId:int:min(1)}")]
    public Task<ActionResult<JsonElement?>> LevelAssignment(Guid programId, int userId, [FromBody] JsonElement request, CancellationToken ct) => Forward(HttpMethod.Put, $"programs/{programId:D}/level-assignments/{userId}", request, ct);
    [HttpGet("rewards")]
    public Task<ActionResult<JsonElement?>> Rewards([FromQuery] Guid? programId, [FromQuery] string? status, [FromQuery] string? beneficiaryRole, [FromQuery] string? eventType,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 50, CancellationToken ct = default) =>
        Forward(HttpMethod.Get, "rewards", null, ct, Query(("programId", programId), ("status", status), ("beneficiaryRole", beneficiaryRole), ("eventType", eventType), ("page", Math.Max(1, page)), ("pageSize", Math.Clamp(pageSize, 1, 500))));
    [HttpGet("metrics")]
    public Task<ActionResult<JsonElement?>> Metrics([FromQuery] Guid? programId, [FromQuery] DateTimeOffset? from, [FromQuery] DateTimeOffset? to, CancellationToken ct) =>
        Forward(HttpMethod.Get, "metrics", null, ct, Query(("programId", programId), ("from", from), ("to", to)));
    // Business-intelligence view: funnel, leaderboard, cost, weekly series, program stats, exclusions, contribution.
    // Platform defaults are all programs, last 90 days, top 10; the platform caps top at 100.
    [HttpGet("analytics")]
    public Task<ActionResult<JsonElement?>> Analytics([FromQuery] Guid? programId, [FromQuery] DateTimeOffset? from, [FromQuery] DateTimeOffset? to, [FromQuery] int top = 10, CancellationToken ct = default) =>
        Forward(HttpMethod.Get, "analytics", null, ct, Query(("programId", programId), ("from", from), ("to", to), ("top", Math.Clamp(top, 1, 100))));
    [HttpGet("credits")]
    public Task<ActionResult<JsonElement?>> Credits([FromQuery] string? status, [FromQuery] int page = 1, [FromQuery] int pageSize = 50, CancellationToken ct = default) =>
        Forward(HttpMethod.Get, "credits", null, ct, Query(("status", status), ("page", Math.Max(1, page)), ("pageSize", Math.Clamp(pageSize, 1, 500))));
    [HttpPost("credits/{creditId:guid}/retry")]
    public Task<ActionResult<JsonElement?>> RetryCredit(Guid creditId, CancellationToken ct) => Forward(HttpMethod.Post, $"credits/{creditId:D}/retry", null, ct);
    [HttpPost("credits/{creditId:guid}/cancel")]
    public Task<ActionResult<JsonElement?>> CancelCredit(Guid creditId, [FromBody] JsonElement request, CancellationToken ct) => Forward(HttpMethod.Post, $"credits/{creditId:D}/cancel", request, ct);
    [HttpGet("reconciliation")]
    public Task<ActionResult<JsonElement?>> Reconciliation(CancellationToken ct) => Forward(HttpMethod.Get, "reconciliation", null, ct);

    // Campaign links (contract 2026-09-15): every member's links, and status changes only.
    [HttpGet("links")]
    public Task<ActionResult<JsonElement?>> Links([FromQuery] Guid? programId, [FromQuery] int? ownerUserId, [FromQuery] string? status, CancellationToken ct) =>
        Forward(HttpMethod.Get, "links", null, ct, Query(("programId", programId), ("ownerUserId", ownerUserId is > 0 ? ownerUserId : null), ("status", string.IsNullOrWhiteSpace(status) ? null : status.Trim().ToUpperInvariant())));
    [HttpPatch("links/{linkId:guid}")]
    public Task<ActionResult<JsonElement?>> UpdateLink(Guid linkId, [FromBody] JsonElement request, CancellationToken ct) => Forward(HttpMethod.Patch, $"links/{linkId:D}", request, ct);
    // Addendum A: one link's figures for a period (7d|30d|90d|month|all), any owner, company-scoped by the platform.
    [HttpGet("links/{linkId:guid}/performance")]
    public Task<ActionResult<JsonElement?>> LinkPerformance(Guid linkId, [FromQuery] string? range, CancellationToken ct) =>
        Forward(HttpMethod.Get, $"links/{linkId:D}/performance", null, ct, Query(("range", string.IsNullOrWhiteSpace(range) ? null : range.Trim().ToLowerInvariant())));

    private string? AuthenticatedActorId() => User.Identity?.IsAuthenticated == true
        ? User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub") : null;

    private Task<ActionResult<JsonElement?>> Forward(HttpMethod method, string resource, JsonElement? body,
        CancellationToken ct, Guid? programId = null, string? search = null) =>
        Forward(method, resource, body, ct, Query(("programId", programId), ("search", search)));

    private async Task<ActionResult<JsonElement?>> Forward(HttpMethod method, string resource, JsonElement? body,
        CancellationToken ct, IReadOnlyDictionary<string, string?> query)
    {
        // Only explicitly declared routes/queries reach the public API. Company scope and
        // credentials come from this installation's existing server-side Hoppa client.
        return ToActionResult(await SendHoppaAsync(method,$"/api/v2/referrals/{resource}",body,
            "admin.referrals.failed","Unable to load or save referral settings.",ct,query,AuthenticatedActorId()));
    }
}
