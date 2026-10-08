using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Auth;
using NeoBanking.Application.DTOs.Auth;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Api.Controllers;

public sealed partial class AuthController
{
    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    [HttpPost("~/api/v1/mobile/auth/referral-quote")]
    public async Task<ActionResult<object>> ReferralQuote([FromBody] ReferralSignupQuoteRequest request, CancellationToken ct)
    {
        if (!companyOptions.Value.Features.ReferralsEnabled) return NotFound();
        if (request.RegistrationAttemptId == Guid.Empty || string.IsNullOrWhiteSpace(request.ReferralCode))
            return BadRequest(new { code="auth.referral.quote_input_invalid" });
        var company = await dbContext.CompanyInstallations.SingleOrDefaultAsync(x=>x.Slug=="default",ct);
        if (company is null) return StatusCode(503);
        var existing = await dbContext.ReferralSignupAttempts.AsNoTracking().SingleOrDefaultAsync(x=>x.Id==request.RegistrationAttemptId,ct);
        var source=ReferralAttributionRules.NormalizeSource(request.Source);
        if (existing is not null)
        {
            if(existing.CompanyInstallationId!=company.Id || existing.State!="QUOTED" ||
                existing.ReferralCode!=request.ReferralCode.Trim() || existing.Source!=source)
                return Conflict(new {code="auth.referral.attempt_conflict"});
            // Return the identical offer; a caller must start a fresh consent attempt when it expires.
            return Ok(JsonSerializer.Deserialize<JsonElement>(existing.QuoteJson));
        }
        var quote = await proxyHoppa.ExecuteAsync(new ProxyHoppaRequestCommand<object>
        {
            Method=HttpMethod.Post, UpstreamPath="/api/v2/referral-attribution-quotes",
            Request=new { registrationAttemptId=request.RegistrationAttemptId, referralCode=request.ReferralCode.Trim(), source,
                invitationToken=request.InvitationToken, locale=request.Locale },
            FailureCode="auth.referral.quote_failed", FailureMessage="We could not load the referral terms."
        },ct);
        if(!quote.IsSuccess) return ToActionResult<object>(NeoBanking.Application.Common.ApplicationResult<object>.Failure(quote.Error!));
        if (quote.Value is not { } body || !Guid.TryParse(QuoteString(body,"quoteId"),out var quoteId) || quoteId==Guid.Empty ||
            string.IsNullOrWhiteSpace(QuoteString(body,"termsHash")) || string.IsNullOrWhiteSpace(QuoteString(body,"policyHash")) ||
            !DateTimeOffset.TryParse(QuoteString(body,"expiresAt"),out _))
            return StatusCode(502,new {code="auth.referral.quote_invalid_response"});
        dbContext.ReferralSignupAttempts.Add(new ReferralSignupAttempt
        {
            Id=request.RegistrationAttemptId, CompanyInstallationId=company.Id, QuoteId=quoteId,
            ReferralCode=request.ReferralCode.Trim(), Source=source, QuoteJson=body.GetRawText()
        });
        try { await dbContext.SaveChangesAsync(ct); }
        catch(DbUpdateException) { return Conflict(new {code="auth.referral.attempt_conflict"}); }
        return Ok(body);
    }

    [Authorize(Policy=AuthorizationPolicyNames.User)]
    [HttpGet("~/api/v1/mobile/auth/referral-attribution")]
    public async Task<ActionResult<object>> ReferralAttributionStatus(CancellationToken ct)
    {
        if(!TryGetCompanyInstallationId(out var companyId) || !TryGetLocalUserId(out var localId) || !Guid.TryParse(localId,out var userId)) return Unauthorized();
        var intent=await dbContext.ReferralAttributionIntents.AsNoTracking().Where(x=>x.CompanyInstallationId==companyId && x.UserId==userId && x.Kind=="ATTRIBUTION")
            .OrderByDescending(x=>x.CreatedAt).FirstOrDefaultAsync(ct);
        if(intent is null) return Ok(new {status="NOT_REQUESTED"});
        return Ok(new {status=intent.State,registrationAttemptId=intent.SignupAttemptId,referralCommandId=intent.Id,
            reason=intent.Reason,updatedAt=intent.UpdatedAt, result=intent.ResultJson is null ? (JsonElement?)null : JsonSerializer.Deserialize<JsonElement>(intent.ResultJson)});
    }

    private static bool ValidSignupQuote(ReferralSignupAttempt? attempt, SignupRequestDto request, string referralCode, DateTimeOffset receivedAt)
    {
        if(attempt?.QuoteId is null || request.ReferralQuoteId!=attempt.QuoteId || attempt.ReferralCode!=referralCode ||
            attempt.Source!=ReferralAttributionRules.NormalizeSource(request.ReferralSource)) return false;
        using var quote=JsonDocument.Parse(attempt.QuoteJson);
        var body=quote.RootElement;
        return !string.IsNullOrWhiteSpace(request.ReferralTermsHash) && !string.IsNullOrWhiteSpace(request.ReferralPolicyHash) &&
            QuoteString(body,"termsHash")==request.ReferralTermsHash &&
            QuoteString(body,"policyHash")==request.ReferralPolicyHash &&
            DateTimeOffset.TryParse(QuoteString(body,"expiresAt"),out var expiry) && expiry>receivedAt;
    }

    private ActionResult<object> SignupCreationUncertain(Guid attemptId) => StatusCode(409,new
    {
        code="auth.signup.creation_uncertain",status="CREATION_UNCERTAIN",registrationAttemptId=attemptId,
        message="Account creation needs reconciliation. Do not create another account; contact support with this reference."
    });

    private static string? QuoteString(JsonElement body,string name)
    {
        if(body.ValueKind!=JsonValueKind.Object)return null;
        foreach(var property in body.EnumerateObject())
            if(string.Equals(property.Name,name,StringComparison.OrdinalIgnoreCase))
                return property.Value.ValueKind==JsonValueKind.String ? property.Value.GetString() : property.Value.ToString();
        return null;
    }
}
