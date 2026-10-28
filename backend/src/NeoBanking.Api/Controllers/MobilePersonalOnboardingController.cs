using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/onboarding")]
public sealed class MobilePersonalOnboardingController(IProxyHoppaRequestUseCase proxy,
    NeoBankingDbContext db, IOptions<CompanyOptions> company) : ApiControllerBase
{
    // Keep the existing /status contract used by banking clients separate.
    [HttpGet("requirements")]
    public Task<ActionResult<JsonElement?>> Status(CancellationToken ct) => Forward(HttpMethod.Get, "status", null, ct);
    [HttpGet("fees")]
    public Task<ActionResult<JsonElement?>> Fees(CancellationToken ct) => Forward(HttpMethod.Get, "fees", null, ct);
    [HttpPost("tier")]
    public Task<ActionResult<JsonElement?>> Tier([FromBody] SelectTier request, CancellationToken ct) => Forward(HttpMethod.Post, "tier", request, ct);
    public sealed record SelectTier(int TierId);
    [HttpGet("invite")]
    public Task<ActionResult<JsonElement?>> Invite(CancellationToken ct) => Forward(HttpMethod.Get, "invite", null, ct);
    [HttpPost("invite/request")]
    public Task<ActionResult<JsonElement?>> RequestInvite(CancellationToken ct) => Forward(HttpMethod.Post, "invite/request", null, ct);
    [HttpPost("invite/verify")]
    public Task<ActionResult<JsonElement?>> VerifyInvite([FromBody] InviteCode request, CancellationToken ct) => Forward(HttpMethod.Post, "invite/verify", request, ct);
    [HttpPost("gates/{gateNumber:int}/checkout")]
    public Task<ActionResult<JsonElement?>> Checkout(int gateNumber, [FromBody] CheckoutTerms request, CancellationToken ct) =>
        Forward(HttpMethod.Post, $"gates/{gateNumber}/checkout", request, ct);
    public sealed record InviteCode(string Code);
    public sealed record CheckoutTerms(bool TermsAccepted);

    private async Task<ActionResult<JsonElement?>> Forward(HttpMethod method, string path, object? body, CancellationToken ct)
    {
        if (!TryGetCurrentUserId(out var userId)) return MissingHoppaUser<JsonElement?>();
        if (!TryGetCompanyInstallationId(out var installation) ||
            !Guid.TryParse(User.FindFirstValue("local_user_id"), out var localUser) ||
            !await db.Users.AsNoTracking().AnyAsync(x => x.Id == localUser && x.CompanyInstallationId == installation, ct))
            return NotFound();
        if (path.StartsWith("invite", StringComparison.Ordinal) && !company.Value.Features.EqualsMoneyEnabled) return NotFound();
        Response.Headers.CacheControl = "no-store";
        var result = await proxy.ExecuteAsync(new ProxyHoppaRequestCommand<object?> {
            Method = method, UpstreamPath = "/api/v2/mobile-onboarding/" + path,
            Query = Query(("userId", userId)), Request = body, SuppressPayloadLogging = true,
            FailureCode = "mobile.onboarding.requirements_failed",
            FailureMessage = "We could not complete this onboarding step. Please try again."
        }, ct);
        // Preserve the explicit terms challenge; never accept terms on the customer's behalf.
        if (result.Error?.StatusCode == 428 && result.Error.Detail is string details)
        {
            try {
                using var doc = JsonDocument.Parse(details);
                if (doc.RootElement.TryGetProperty("error", out var error) && error.GetString() == "PAYMENT_TERMS_REQUIRED")
                    return StatusCode(428, doc.RootElement.Clone());
            } catch (JsonException) { }
        }
        return ToActionResult(result);
    }
}
