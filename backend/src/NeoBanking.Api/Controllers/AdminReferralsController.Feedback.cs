using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.Interfaces;

namespace NeoBanking.Api.Controllers;

public sealed partial class AdminReferralsController
{
    [HttpGet("programs/{programId:guid}/risk-policy")]
    public Task<ActionResult<JsonElement?>> RiskPolicy(Guid programId,CancellationToken ct) => Forward(HttpMethod.Get,$"programs/{programId:D}/risk-policy",null,ct);
    [HttpPut("programs/{programId:guid}/risk-policy")]
    public Task<ActionResult<JsonElement?>> SaveRiskPolicy(Guid programId,[FromBody] JsonElement body,CancellationToken ct) => Forward(HttpMethod.Put,$"programs/{programId:D}/risk-policy",body,ct);
    [HttpGet("reviews")]
    public Task<ActionResult<JsonElement?>> Reviews([FromQuery] Guid? programId,[FromQuery] string? status,[FromQuery] int page=1,[FromQuery] int pageSize=50,CancellationToken ct=default) =>
        Forward(HttpMethod.Get,"reviews",null,ct,Query(("programId",programId),("status",status),("page",Math.Max(1,page)),("pageSize",Math.Clamp(pageSize,1,200))));
    [HttpGet("reviews/{reviewId:guid}")]
    public Task<ActionResult<JsonElement?>> Review(Guid reviewId,CancellationToken ct) => Forward(HttpMethod.Get,$"reviews/{reviewId:D}",null,ct);
    [HttpPost("reviews/{reviewId:guid}/decisions")]
    public Task<ActionResult<JsonElement?>> ReviewDecision(Guid reviewId,[FromBody] JsonElement body,CancellationToken ct) => Forward(HttpMethod.Post,$"reviews/{reviewId:D}/decisions",body,ct);
    [HttpGet("programs/{programId:guid}/geo-policy")]
    public Task<ActionResult<JsonElement?>> GeoPolicy(Guid programId,CancellationToken ct) => Forward(HttpMethod.Get,$"programs/{programId:D}/geo-policy",null,ct);
    [HttpPut("programs/{programId:guid}/geo-policy")]
    public Task<ActionResult<JsonElement?>> SaveGeoPolicy(Guid programId,[FromBody] JsonElement body,CancellationToken ct) => Forward(HttpMethod.Put,$"programs/{programId:D}/geo-policy",body,ct);
    [HttpGet("programs/{programId:guid}/localized-terms")]
    public Task<ActionResult<JsonElement?>> LocalizedTerms(Guid programId,[FromQuery] string? locale,CancellationToken ct) => Forward(HttpMethod.Get,$"programs/{programId:D}/localized-terms",null,ct,Query(("locale",locale)));
    [HttpPost("programs/{programId:guid}/bulk/preview")]
    [RequestSizeLimit(2097152)]
    public Task<ActionResult<JsonElement?>> BulkPreview(Guid programId,[FromBody] JsonElement body,CancellationToken ct) => Forward(HttpMethod.Post,$"programs/{programId:D}/bulk/preview",body,ct);
    [HttpPost("programs/{programId:guid}/bulk/{jobId:guid}/execute")]
    public Task<ActionResult<JsonElement?>> BulkExecute(Guid programId,Guid jobId,[FromBody] JsonElement body,CancellationToken ct) => Forward(HttpMethod.Post,$"programs/{programId:D}/bulk/{jobId:D}/execute",body,ct);
    [HttpGet("programs/{programId:guid}/bulk/{jobId:guid}")]
    public Task<ActionResult<JsonElement?>> BulkJob(Guid programId,Guid jobId,CancellationToken ct) => Forward(HttpMethod.Get,$"programs/{programId:D}/bulk/{jobId:D}",null,ct);
    [HttpGet("programs/{programId:guid}/bulk/{jobId:guid}/errors.csv")]
    public async Task<IActionResult> BulkErrors(Guid programId,Guid jobId,[FromServices] IHoppaClient client,CancellationToken ct)
    {
        var result=await client.DownloadAsync(new HoppaRequest<object?>
        { Method=HttpMethod.Get,Path=$"/api/v2/referrals/programs/{programId:D}/bulk/{jobId:D}/errors.csv",TrustedReferralActorId=AuthenticatedActorId() },ct);
        if(!result.IsSuccess) return ToActionResult(result).Result!;
        Response.Headers.CacheControl="no-store";
        Response.RegisterForDispose(result.Value!);
        return File(result.Value!.Content,"text/csv; charset=utf-8",$"referral-bulk-{jobId:D}-errors.csv");
    }
    [HttpPost("accounting/openings")]
    public Task<ActionResult<JsonElement?>> AccountingOpening([FromBody] JsonElement body,CancellationToken ct) => Forward(HttpMethod.Post,"accounting/openings",body,ct);

    [HttpGet("programs/{programId:guid}/boosts")]
    public Task<ActionResult<JsonElement?>> Boosts(Guid programId,CancellationToken ct) => Forward(HttpMethod.Get,$"programs/{programId:D}/boosts",null,ct);
    [HttpPost("programs/{programId:guid}/boosts")]
    public Task<ActionResult<JsonElement?>> SaveBoost(Guid programId,[FromBody] JsonElement body,CancellationToken ct) => Forward(HttpMethod.Post,$"programs/{programId:D}/boosts",body,ct);
    [HttpPost("programs/{programId:guid}/boosts/{boostId:guid}/activate")]
    public Task<ActionResult<JsonElement?>> ActivateBoost(Guid programId,Guid boostId,[FromBody] JsonElement body,CancellationToken ct) => Forward(HttpMethod.Post,$"programs/{programId:D}/boosts/{boostId:D}/activate",body,ct);
    [HttpPost("programs/{programId:guid}/boosts/{boostId:guid}/pause")]
    public Task<ActionResult<JsonElement?>> PauseBoost(Guid programId,Guid boostId,[FromBody] JsonElement body,CancellationToken ct) => Forward(HttpMethod.Post,$"programs/{programId:D}/boosts/{boostId:D}/pause",body,ct);
    [HttpGet("programs/{programId:guid}/boosts/capabilities")]
    public Task<ActionResult<JsonElement?>> BoostCapabilities(Guid programId,CancellationToken ct) => Forward(HttpMethod.Get,$"programs/{programId:D}/boosts/capabilities",null,ct);
    [HttpGet("programs/{programId:guid}/attribution-readiness")]
    public Task<ActionResult<JsonElement?>> AttributionReadiness(Guid programId,CancellationToken ct) => Forward(HttpMethod.Get,$"programs/{programId:D}/attribution-readiness",null,ct);

    [HttpGet("relationships")]
    public Task<ActionResult<JsonElement?>> Relationships([FromQuery] Guid? programId, [FromQuery] string? search,
        [FromQuery] string? stage, [FromQuery] string? source, [FromQuery] int? inviterUserId, [FromQuery] int? friendUserId,
        [FromQuery] long? afterId, [FromQuery] int pageSize = 50, CancellationToken ct = default) =>
        Forward(HttpMethod.Get, "relationships", null, ct, Query(("programId",programId),("search",search),("stage",stage),("source",source),
            ("inviterUserId",inviterUserId),("friendUserId",friendUserId),("afterId",afterId),("pageSize",Math.Clamp(pageSize,1,200))));
    [HttpGet("relationships/{relationshipId:guid}")]
    public Task<ActionResult<JsonElement?>> Relationship(Guid relationshipId, CancellationToken ct) =>
        Forward(HttpMethod.Get, $"relationships/{relationshipId:D}", null, ct);
    [HttpGet("users/{userId:int:min(1)}/relationships")]
    public Task<ActionResult<JsonElement?>> UserRelationships(int userId, [FromQuery] string? direction,
        [FromQuery] long? afterId, [FromQuery] int pageSize = 50, CancellationToken ct = default) =>
        Forward(HttpMethod.Get, $"users/{userId}/relationships", null, ct,
            Query(("direction",direction),("afterId",afterId),("pageSize",Math.Clamp(pageSize,1,200))));
    [HttpPost("programs/{programId:guid}/qualification-scenarios")]
    public Task<ActionResult<JsonElement?>> QualificationScenario(Guid programId, [FromBody] JsonElement body, CancellationToken ct) =>
        Forward(HttpMethod.Post, $"programs/{programId:D}/qualification-scenarios", body, ct);
    [HttpGet("programs/{programId:guid}/members/{userId:int:min(1)}/level-lifecycle")]
    public Task<ActionResult<JsonElement?>> LevelLifecycle(Guid programId, int userId, CancellationToken ct) =>
        Forward(HttpMethod.Get, $"programs/{programId:D}/members/{userId}/level-lifecycle", null, ct);
    [HttpGet("programs/{programId:guid}/members/{userId:int:min(1)}/level-history")]
    public Task<ActionResult<JsonElement?>> LevelHistory(Guid programId, int userId, [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50, CancellationToken ct = default) =>
        Forward(HttpMethod.Get, $"programs/{programId:D}/members/{userId}/level-history", null, ct,
            Query(("page",Math.Max(1,page)),("pageSize",Math.Clamp(pageSize,1,200))));
    [HttpGet("audit")]
    public Task<ActionResult<JsonElement?>> Audit([FromQuery] Guid? programId, [FromQuery] string? actorId,
        [FromQuery] string? action, [FromQuery] DateTimeOffset? from, [FromQuery] DateTimeOffset? to,
        [FromQuery] long? beforeId, [FromQuery] int pageSize = 50, CancellationToken ct = default) =>
        Forward(HttpMethod.Get, "audit", null, ct, Query(("programId",programId),("actorId",actorId),("action",action),
            ("from",from),("to",to),("beforeId",beforeId),("pageSize",Math.Clamp(pageSize,1,200))));
    [HttpGet("alert-settings")]
    public Task<ActionResult<JsonElement?>> AlertSettings(CancellationToken ct) => Forward(HttpMethod.Get,"alert-settings",null,ct);
    [HttpPut("alert-settings")]
    public Task<ActionResult<JsonElement?>> SaveAlertSettings([FromBody] JsonElement body, CancellationToken ct) => Forward(HttpMethod.Put,"alert-settings",body,ct);
    [HttpGet("alert-incidents")]
    public Task<ActionResult<JsonElement?>> AlertIncidents([FromQuery] Guid? programId, [FromQuery] string? status,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 50, CancellationToken ct = default) =>
        Forward(HttpMethod.Get,"alert-incidents",null,ct,Query(("programId",programId),("status",status),("page",Math.Max(1,page)),("pageSize",Math.Clamp(pageSize,1,200))));
    [HttpGet("alert-delivery-health")]
    public Task<ActionResult<JsonElement?>> AlertDeliveryHealth(CancellationToken ct) => Forward(HttpMethod.Get,"alert-delivery-health",null,ct);
    [HttpGet("accounting/monthly")]
    public Task<ActionResult<JsonElement?>> MonthlyAccounting([FromQuery] string month, [FromQuery] string currency,
        [FromQuery] Guid? programId, [FromQuery] DateTimeOffset? asOf, CancellationToken ct) => Forward(HttpMethod.Get,"accounting/monthly",null,ct,
            Query(("month",month),("currency",currency),("programId",programId),("asOf",asOf)));
    [HttpGet("exports/{kind}")]
    public async Task<IActionResult> Export(string kind, [FromServices] IHoppaClient client, [FromQuery] Guid? programId,
        [FromQuery] string? status, [FromQuery] string? currency, [FromQuery] string? beneficiaryRole, [FromQuery] string? eventType,
        [FromQuery] int? userId, [FromQuery] DateTimeOffset? from, [FromQuery] DateTimeOffset? to, CancellationToken ct)
    {
        if (kind is not ("ledger" or "credits" or "relationships")) return BadRequest(new { code="export.kind.invalid" });
        var result = await client.DownloadAsync(new HoppaRequest<object?>
        {
            Method=HttpMethod.Get, Path=$"/api/v2/referrals/exports/{kind}", TrustedReferralActorId=AuthenticatedActorId(),
            Query=Query(("programId",programId),("status",status),("currency",currency),("beneficiaryRole",beneficiaryRole),
                ("eventType",eventType),("userId",userId),("from",from),("to",to)),
            FailureCode="admin.referrals.export_failed", FailureMessage="Unable to export referral records."
        },ct);
        if (!result.IsSuccess) return ToActionResult(result).Result!;
        Response.Headers.CacheControl = "no-store";
        Response.RegisterForDispose(result.Value!);
        return File(result.Value!.Content, "text/csv; charset=utf-8", $"referrals-{kind}.csv");
    }
}
