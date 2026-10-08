using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Application.Common;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/rewards")]
public sealed partial class MobileRewardsController(
    IProxyHoppaRequestUseCase proxyHoppa,
    IOptions<CompanyOptions> options) : ApiControllerBase
{
    [HttpGet("referrals/geo-eligibility")]
    public Task<ActionResult<JsonElement?>> GeoEligibility(CancellationToken cancellationToken) =>
        SendReferralAsync(HttpMethod.Get, "geo-eligibility", null, cancellationToken);

    [HttpGet("referrals/level-lifecycle")]
    public Task<ActionResult<JsonElement?>> LevelLifecycle([FromQuery] Guid? programId, CancellationToken cancellationToken) =>
        SendReferralAsync(HttpMethod.Get, "level-lifecycle", null, cancellationToken, Query(("programId", programId)));

    [HttpGet("referrals/level-history")]
    public Task<ActionResult<JsonElement?>> LevelHistory([FromQuery] Guid? programId, [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50, CancellationToken cancellationToken = default) =>
        SendReferralAsync(HttpMethod.Get, "level-history", null, cancellationToken,
            Query(("programId", programId), ("page", Math.Max(1,page)), ("pageSize",Math.Clamp(pageSize,1,200))));

    [HttpGet("referrals/summary")]
    public Task<ActionResult<JsonElement?>> GetReferralSummary(CancellationToken cancellationToken) =>
        SendReferralAsync(HttpMethod.Get, "summary", null, cancellationToken);

    /// <summary>Reward ledger rows for the signed-in user (stage PENDING/READY/CREDITING/PAID/FAILED).</summary>
    [HttpGet("referrals/rewards")]
    public Task<ActionResult<JsonElement?>> GetReferralRewards(
        [FromQuery] Guid? programId = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 25,
        CancellationToken cancellationToken = default) =>
        SendReferralAsync(HttpMethod.Get, "rewards", null, cancellationToken, PagedQuery(programId, page, pageSize));

    /// <summary>Alias kept for app builds that still call the pre-v2 route; same upstream resource.</summary>
    [HttpGet("referrals/commissions")]
    public Task<ActionResult<JsonElement?>> GetReferralCommissions(
        [FromQuery] Guid? programId = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 25,
        CancellationToken cancellationToken = default) =>
        GetReferralRewards(programId, page, pageSize, cancellationToken);

    /// <summary>Referred friends with their qualification stage and what they earned the user.</summary>
    [HttpGet("referrals/friends")]
    public Task<ActionResult<JsonElement?>> GetReferralFriends(
        [FromQuery] Guid? programId = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 25,
        CancellationToken cancellationToken = default) =>
        SendReferralAsync(HttpMethod.Get, "friends", null, cancellationToken, PagedQuery(programId, page, pageSize));

    /// <summary>
    /// The signed-in user's referral analytics for a period: conversion journey, totals, weekly
    /// buckets and top friends. <paramref name="range"/> is <c>7d</c>, <c>30d</c>, <c>90d</c> or
    /// <c>month</c>; an explicit <paramref name="from"/>/<paramref name="to"/> (ISO 8601, UTC) wins
    /// over it. The platform validates the period and answers 404 while the resource is not served.
    /// </summary>
    [HttpGet("referrals/analytics")]
    public Task<ActionResult<JsonElement?>> GetReferralAnalytics(
        [FromQuery] Guid? programId = null,
        [FromQuery] string? range = null,
        [FromQuery] string? from = null,
        [FromQuery] string? to = null,
        CancellationToken cancellationToken = default) =>
        SendReferralAsync(
            HttpMethod.Get,
            "analytics",
            null,
            cancellationToken,
            AnalyticsQuery(programId, range, from, to));

    [HttpPost("referrals/terms-acceptance")]
    public Task<ActionResult<JsonElement?>> AcceptReferralTerms(
        [FromBody] ReferralTermsAcceptanceRequest request,
        CancellationToken cancellationToken)
    {
        if (request.TermsVersion is not > 0)
        {
            return Task.FromResult(ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.referrals.terms.invalid_version",
                "A terms version is required.",
                StatusCodes.Status400BadRequest))));
        }

        return SendReferralAsync(
            HttpMethod.Post,
            "terms-acceptance",
            new { TermsVersion = request.TermsVersion.Value },
            cancellationToken);
    }

    [HttpPost("referrals/invitations")]
    public Task<ActionResult<JsonElement?>> SendReferralInvitation(
        [FromBody] ReferralInvitationRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.RecipientEmail))
        {
            return Task.FromResult(ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.referrals.invitation.invalid_email",
                "A recipient email address is required.",
                StatusCodes.Status400BadRequest))));
        }

        return SendReferralAsync(
            HttpMethod.Post,
            "invitations",
            new
            {
                RecipientEmail = request.RecipientEmail.Trim(),
                RecipientName = string.IsNullOrWhiteSpace(request.RecipientName)
                    ? null
                    : request.RecipientName.Trim()
            },
            cancellationToken);
    }

    // ---- campaign links (contract 2026-09-15 §2): a member's own tracking links ----

    /// <summary>The signed-in member's campaign links, optionally by programme and status.</summary>
    [HttpGet("referrals/links")]
    public Task<ActionResult<JsonElement?>> GetCampaignLinks(
        [FromQuery] Guid? programId = null,
        [FromQuery] string? status = null,
        CancellationToken cancellationToken = default) =>
        SendReferralAsync(
            HttpMethod.Get,
            "links",
            null,
            cancellationToken,
            new Dictionary<string, string?>
            {
                ["programId"] = programId?.ToString("D"),
                ["status"] = Trimmed(status)?.ToUpperInvariant()
            });

    /// <summary>
    /// Creates a campaign link. Only the shape is checked here; the platform owns the code
    /// rules (length, reserved words, uniqueness), the channel list and the per-member limit.
    /// </summary>
    [HttpPost("referrals/links")]
    public Task<ActionResult<JsonElement?>> CreateCampaignLink(
        [FromBody] CampaignLinkCreateRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Name) || string.IsNullOrWhiteSpace(request.Channel))
        {
            return Task.FromResult(ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.referrals.links.invalid_request",
                "A campaign name and a channel are required.",
                StatusCodes.Status400BadRequest))));
        }

        return SendReferralAsync(
            HttpMethod.Post,
            "links",
            new
            {
                request.ProgramId,
                Name = request.Name.Trim(),
                Code = Trimmed(request.Code),
                Channel = request.Channel.Trim().ToLowerInvariant(),
                Locale = Trimmed(request.Locale),
                Destination = Trimmed(request.Destination),
                request.ExpiresAt
            },
            cancellationToken);
    }

    /// <summary>
    /// Renames, pauses, resumes, archives, re-dates or re-targets a link. The code is immutable;
    /// the destination may change to another allowlisted one (addendum A, 2026-09-15), which the
    /// platform validates.
    /// </summary>
    [HttpPatch("referrals/links/{linkId:guid}")]
    public Task<ActionResult<JsonElement?>> UpdateCampaignLink(
        Guid linkId,
        [FromBody] CampaignLinkUpdateRequest request,
        CancellationToken cancellationToken)
    {
        var name = Trimmed(request.Name);
        var status = Trimmed(request.Status)?.ToUpperInvariant();
        var destination = Trimmed(request.Destination)?.ToLowerInvariant();
        if (name is null && status is null && destination is null && !request.ExpiresAt.HasValue && !request.ClearExpiresAt)
        {
            return Task.FromResult(ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.referrals.links.invalid_request",
                "Nothing to change on this link.",
                StatusCodes.Status400BadRequest))));
        }

        return SendReferralAsync(
            HttpMethod.Patch,
            $"links/{linkId:D}",
            new
            {
                Name = name,
                Status = status,
                Destination = destination,
                ExpiresAt = request.ClearExpiresAt ? null : request.ExpiresAt,
                request.ClearExpiresAt
            },
            cancellationToken);
    }

    /// <summary>
    /// A visitor opened the sign-up page with a campaign code (addendum A). Anonymous like
    /// <c>check-referral</c>: the account does not exist yet. The app sends its per-install visitor
    /// id so the platform counts one unique click per visitor per day; the user agent goes along as a
    /// hint so the platform can skip crawlers and link previews. No IP is forwarded or stored. The
    /// answer is 204 whether or not anything was counted — a click is telemetry and never blocks a
    /// sign-up — and a platform that predates clicks (404) is answered the same way.
    /// </summary>
    [AllowAnonymous]
    [HttpPost("referrals/links/{code}/clicks")]
    public async Task<ActionResult<JsonElement?>> RecordCampaignLinkClick(
        string code,
        [FromBody] CampaignLinkClickRequest? request,
        CancellationToken cancellationToken)
    {
        var normalizedCode = Trimmed(code)?.ToUpperInvariant();
        if (normalizedCode is null || !CampaignCodePattern.IsMatch(normalizedCode))
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.referrals.links.invalid_code",
                "A campaign code is required.",
                StatusCodes.Status400BadRequest)));
        }

        if (!options.Value.Features.ReferralsEnabled)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.referrals.disabled",
                "Referrals are not enabled for this company.",
                StatusCodes.Status404NotFound)));
        }

        var visitorId = Trimmed(request?.VisitorId);
        var userAgent = Trimmed(Request.Headers.UserAgent.ToString());
        var result = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object?>
            {
                Method = HttpMethod.Post,
                UpstreamPath = $"/api/v2/referrals/links/{Segment(normalizedCode)}/clicks",
                Request = new
                {
                    VisitorId = visitorId is { Length: > MaxVisitorIdLength } ? visitorId[..MaxVisitorIdLength] : visitorId,
                    Locale = Trimmed(request?.Locale) is { } locale && locale.Length <= MaxLocaleLength ? locale : null,
                    UserAgentHint = userAgent is { Length: > MaxUserAgentHintLength } ? userAgent[..MaxUserAgentHintLength] : userAgent
                },
                FailureCode = "mobile.referrals.links.click_failed",
                FailureMessage = "We could not record the visit."
            },
            cancellationToken);

        if (result.IsSuccess || result.Error!.StatusCode == StatusCodes.Status404NotFound)
        {
            return NoContent();
        }

        return ToActionResult(result);
    }

    /// <summary>What one link brought in over a period (<c>7d</c>, <c>30d</c>, <c>90d</c>, <c>month</c>, <c>all</c>).</summary>
    [HttpGet("referrals/links/{linkId:guid}/performance")]
    public Task<ActionResult<JsonElement?>> GetCampaignLinkPerformance(
        Guid linkId,
        [FromQuery] string? range = null,
        CancellationToken cancellationToken = default) =>
        SendReferralAsync(
            HttpMethod.Get,
            $"links/{linkId:D}/performance",
            null,
            cancellationToken,
            new Dictionary<string, string?> { ["range"] = Trimmed(range)?.ToLowerInvariant() });

    [HttpGet("referrals/vouchers")]
    public Task<ActionResult<JsonElement?>> GetAssignedVouchers(CancellationToken cancellationToken) =>
        SendReferralAsync(HttpMethod.Get, "vouchers", null, cancellationToken, requireVouchers: true);

    [HttpPost("referrals/vouchers/{assignmentId:guid}/redeem")]
    public Task<ActionResult<JsonElement?>> RedeemAssignedVoucher(
        Guid assignmentId,
        CancellationToken cancellationToken) =>
        SendReferralAsync(
            HttpMethod.Post,
            $"vouchers/{assignmentId:D}/redeem",
            null,
            cancellationToken,
            requireVouchers: true);

    [HttpPost("referrals/vouchers/redeem-all")]
    public Task<ActionResult<JsonElement?>> RedeemAllAssignedVouchers(CancellationToken cancellationToken) =>
        SendReferralAsync(HttpMethod.Post, "vouchers/redeem-all", null, cancellationToken, requireVouchers: true);

    [HttpGet("vouchers/status")]
    public async Task<ActionResult<object>> GetVoucherStatus(CancellationToken cancellationToken)
    {
        if (!options.Value.Features.VouchersEnabled)
        {
            return Ok(new { enabled = false, shutdownMode = "template_disabled" });
        }

        var result = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object?>
            {
                Method = HttpMethod.Get,
                UpstreamPath = "/api/v2/vouchers/settings",
                FailureCode = "mobile.vouchers.status.failed",
                FailureMessage = "We could not load voucher availability."
            },
            cancellationToken);

        if (!result.IsSuccess)
        {
            // The company-scoped public API can permit voucher validation while
            // keeping the administrative settings endpoint private. Do not pass
            // that upstream 401/403 to the mobile client: it would be mistaken
            // for an expired app session and trigger an unnecessary token refresh.
            if (result.Error!.StatusCode is StatusCodes.Status401Unauthorized or StatusCodes.Status403Forbidden)
            {
                return Ok(new
                {
                    enabled = true,
                    shutdownMode = "status_unavailable"
                });
            }

            return ToActionResult<object>(ApplicationResult<object>.Failure(result.Error!));
        }

        var payload = result.Value;
        return Ok(new
        {
            enabled = GetBoolean(payload, "EffectiveEnabled", "effectiveEnabled"),
            shutdownMode = GetString(payload, "ShutdownMode", "shutdownMode") ?? "unknown"
        });
    }

    [HttpPost("vouchers/validate")]
    public Task<ActionResult<JsonElement?>> ValidateVoucher(
        [FromBody] VoucherCodeRequest request,
        CancellationToken cancellationToken) =>
        SendVoucherCodeAsync("/api/v2/vouchers/validate", request.Code, cancellationToken);

    [HttpPost("vouchers/redeem")]
    public Task<ActionResult<JsonElement?>> RedeemVoucher(
        [FromBody] VoucherCodeRequest request,
        CancellationToken cancellationToken) =>
        SendVoucherCodeAsync("/api/v2/vouchers/redemptions", request.Code, cancellationToken);

    /// <summary>The platform's code rule: 6–24 characters of letters, digits, `_` and `-`.</summary>
    private static readonly System.Text.RegularExpressions.Regex CampaignCodePattern =
        new("^[A-Za-z0-9_-]{6,24}$", System.Text.RegularExpressions.RegexOptions.Compiled);

    private const int MaxVisitorIdLength = 64;
    private const int MaxLocaleLength = 8;
    private const int MaxUserAgentHintLength = 256;

    private static string? Trimmed(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static Dictionary<string, string?> PagedQuery(Guid? programId, int page, int pageSize)
    {
        return new Dictionary<string, string?>
        {
            ["programId"] = programId?.ToString("D"),
            ["page"] = Math.Max(1, page).ToString(),
            ["pageSize"] = Math.Clamp(pageSize, 1, 100).ToString()
        };
    }

    /// <summary>
    /// Period parameters forwarded as the member typed them: the platform owns the range
    /// vocabulary and the date limits, so the facade only trims and lower-cases the range
    /// token and drops blanks (the client sends nothing rather than empty strings).
    /// </summary>
    private static Dictionary<string, string?> AnalyticsQuery(
        Guid? programId,
        string? range,
        string? from,
        string? to)
    {
        return new Dictionary<string, string?>
        {
            ["programId"] = programId?.ToString("D"),
            ["range"] = string.IsNullOrWhiteSpace(range) ? null : range.Trim().ToLowerInvariant(),
            ["from"] = string.IsNullOrWhiteSpace(from) ? null : from.Trim(),
            ["to"] = string.IsNullOrWhiteSpace(to) ? null : to.Trim()
        };
    }

    private async Task<ActionResult<JsonElement?>> SendReferralAsync(
        HttpMethod method,
        string relativePath,
        object? request,
        CancellationToken cancellationToken,
        IReadOnlyDictionary<string, string?>? query = null,
        bool requireVouchers = false)
    {
        var features = options.Value.Features;
        if (!features.ReferralsEnabled || (requireVouchers && !features.VouchersEnabled))
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                requireVouchers ? "mobile.vouchers.disabled" : "mobile.referrals.disabled",
                requireVouchers ? "Vouchers are not enabled for this company." : "Referrals are not enabled for this company.",
                StatusCodes.Status404NotFound)));
        }

        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var result = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object?>
            {
                Method = method,
                UpstreamPath = $"/api/v2/users/{Segment(userId)}/referrals/{relativePath}",
                Query = query ?? new Dictionary<string, string?>(),
                Request = request,
                FailureCode = "mobile.rewards.referrals.failed",
                FailureMessage = "We could not process the referral request."
            },
            cancellationToken);

        return ToActionResult(WithCampaignLinkError(result));
    }

    /// <summary>
    /// The platform answers campaign-link rule breaches as <c>{ message, code: "CAMPAIGN_…", status }</c>
    /// (name, code taken or reserved, channel, locale, expiry, the per-member limit, an archived link).
    /// Those messages are written for the member, so the facade surfaces them as the error's own
    /// title and code instead of the generic proxy failure; everything else passes through unchanged.
    /// </summary>
    private static ApplicationResult<JsonElement?> WithCampaignLinkError(ApplicationResult<JsonElement?> result)
    {
        if (result.IsSuccess || string.IsNullOrWhiteSpace(result.Error!.Detail))
        {
            return result;
        }

        try
        {
            using var document = JsonDocument.Parse(result.Error.Detail);
            var code = GetString(document.RootElement, "code", "Code");
            if (code is null || !code.StartsWith("CAMPAIGN_", StringComparison.OrdinalIgnoreCase))
            {
                return result;
            }

            var message = GetString(document.RootElement, "message", "Message", "title", "Title");
            return ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                $"mobile.referrals.links.{code.ToLowerInvariant()}",
                string.IsNullOrWhiteSpace(message) ? result.Error.Message : message,
                result.Error.StatusCode,
                code.ToUpperInvariant()));
        }
        catch (JsonException)
        {
            return result;
        }
    }

    private async Task<ActionResult<JsonElement?>> SendVoucherCodeAsync(
        string upstreamPath,
        string? code,
        CancellationToken cancellationToken)
    {
        if (!options.Value.Features.VouchersEnabled)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.vouchers.disabled",
                "Vouchers are not enabled for this company.",
                StatusCodes.Status404NotFound)));
        }

        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        if (!int.TryParse(userId, out var numericUserId) || string.IsNullOrWhiteSpace(code))
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.vouchers.invalid_request",
                "A valid voucher code is required.",
                StatusCodes.Status400BadRequest)));
        }

        var result = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object>
            {
                Method = HttpMethod.Post,
                UpstreamPath = upstreamPath,
                Request = new { UserId = numericUserId, Code = code.Trim() },
                FailureCode = "mobile.vouchers.request_failed",
                FailureMessage = "We could not process this voucher."
            },
            cancellationToken);

        return ToActionResult(result);
    }

    private static bool GetBoolean(JsonElement? payload, params string[] names)
    {
        if (payload is not { ValueKind: JsonValueKind.Object } value)
        {
            return false;
        }

        return names.Any(name =>
            value.TryGetProperty(name, out var property) &&
            property.ValueKind is JsonValueKind.True or JsonValueKind.False &&
            property.GetBoolean());
    }

    private static string? GetString(JsonElement? payload, params string[] names)
    {
        if (payload is not { ValueKind: JsonValueKind.Object } value)
        {
            return null;
        }

        foreach (var name in names)
        {
            if (value.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.String)
            {
                return property.GetString();
            }
        }

        return null;
    }

    public sealed class VoucherCodeRequest
    {
        public string? Code { get; init; }
    }

    public sealed class ReferralInvitationRequest
    {
        public string? RecipientEmail { get; init; }
        public string? RecipientName { get; init; }
    }

    public sealed class ReferralTermsAcceptanceRequest
    {
        public int? TermsVersion { get; init; }
    }

    public sealed class CampaignLinkClickRequest
    {
        /// <summary>The app's per-install visitor id (an opaque token, at most 64 characters).</summary>
        public string? VisitorId { get; init; }
        public string? Locale { get; init; }
    }

    public sealed class CampaignLinkCreateRequest
    {
        public Guid? ProgramId { get; init; }
        public string? Name { get; init; }
        public string? Code { get; init; }
        public string? Channel { get; init; }
        public string? Locale { get; init; }
        public string? Destination { get; init; }
        public DateTimeOffset? ExpiresAt { get; init; }
    }

    public sealed class CampaignLinkUpdateRequest
    {
        public string? Name { get; init; }
        public string? Status { get; init; }

        /// <summary>One of the platform's allowlist (`signup`, `home`, `cards`, `topup`, `rewards`).</summary>
        public string? Destination { get; init; }
        public DateTimeOffset? ExpiresAt { get; init; }

        /// <summary>True removes the expiry; a null <see cref="ExpiresAt"/> alone leaves it untouched.</summary>
        public bool ClearExpiresAt { get; init; }
    }
}
