using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Company;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/onboarding/cdd")]
public sealed class MobileUnifiedCddController(IProxyHoppaRequestUseCase proxy, IOptions<CompanyOptions> company,
    NeoBankingDbContext db, EqualsConsentService consent) : ApiControllerBase
{
    [HttpGet("preferences")]
    public async Task<ActionResult<object>> Preferences(CancellationToken ct)
    {
        var selection = await Selection(ct);
        return Ok(new { enabled = selection.HasValue, cryptoCard = true,
            exchange = selection?.Exchange ?? false, banking = selection?.Banking ?? false });
    }
    [HttpGet]
    public Task<ActionResult<JsonElement?>> Get(CancellationToken ct) => Forward(HttpMethod.Get, "", null, ct);
    [HttpPost("session")]
    public Task<ActionResult<JsonElement?>> Start(CancellationToken ct) => Forward(HttpMethod.Post, "/session", null, ct);
    [HttpPut("answers")]
    public Task<ActionResult<JsonElement?>> Answers([FromBody] JsonElement request, CancellationToken ct) => Forward(HttpMethod.Put, "/answers", request, ct);
    [HttpPost("submit")]
    public Task<ActionResult<JsonElement?>> Submit(CancellationToken ct) => Forward(HttpMethod.Post, "/submit", null, ct);

    private async Task<(bool Exchange, bool Banking)?> Selection(CancellationToken ct)
    {
        if (!TryGetCompanyInstallationId(out var installation) ||
            !Guid.TryParse(User.FindFirstValue("local_user_id"), out var localUser)) return null;
        var user = await db.Users.AsNoTracking().SingleOrDefaultAsync(x => x.Id == localUser && x.CompanyInstallationId == installation, ct);
        if (string.IsNullOrWhiteSpace(user?.MetadataJson)) return null;
        using var metadata = JsonDocument.Parse(user.MetadataJson);
        if (!metadata.RootElement.TryGetProperty("unifiedCdd", out var selected) || selected.ValueKind != JsonValueKind.Object) return null;
        var exchange = selected.TryGetProperty("exchange", out var e) && e.ValueKind == JsonValueKind.True;
        var banking = selected.TryGetProperty("banking", out var b) && b.ValueKind == JsonValueKind.True;
        if ((exchange && !company.Value.Features.BoomFiExchangeEnabled) || (banking && !company.Value.Features.EqualsMoneyEnabled)) return null;
        return exchange || banking ? (exchange, banking) : null;
    }
    private async Task<ActionResult<JsonElement?>> Forward(HttpMethod method, string suffix, JsonElement? request, CancellationToken ct)
    {
        var selection = await Selection(ct);
        if (!selection.HasValue) return NotFound();
        if (!TryGetCurrentUserId(out var userId)) return MissingHoppaUser<JsonElement?>();
        if (selection.Value.Banking && method != HttpMethod.Get)
        {
            var localId = Guid.Parse(User.FindFirstValue("local_user_id")!);
            var installation = Guid.Parse(User.FindFirstValue("company_installation_id")!);
            var user = await db.Users.SingleAsync(x => x.Id == localId && x.CompanyInstallationId == installation, ct);
            if ((await consent.StatusAsync(user, ct)).RequiresAcceptance)
                return StatusCode(428, new { code = "equals.consent_required", message = "Accept the current Equals Money agreements before continuing." });
        }
        object? body = suffix == "/session" ? new { exchange = selection.Value.Exchange, banking = selection.Value.Banking }
            : request;
        var result = await proxy.ExecuteAsync(new ProxyHoppaRequestCommand<object?> {
            Method = method, UpstreamPath = "/api/v2/mobile-onboarding/cdd" + suffix,
            Query = Query(("userId", userId)), Request = body, SuppressPayloadLogging = true,
            FailureCode = "mobile.cdd.upstream_failed", FailureMessage = "We could not complete this onboarding step."
        }, ct);
        Response.Headers.CacheControl = "no-store";
        if (result.Error?.StatusCode == 404)
            return StatusCode(503, new { code = "mobile.cdd.unavailable",
                message = "Verification is temporarily unavailable. Please try again shortly." });
        return ToActionResult(result);
    }
}
