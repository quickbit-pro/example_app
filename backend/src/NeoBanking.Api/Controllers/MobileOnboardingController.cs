using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Onboarding;
using NeoBanking.Application.DTOs.Onboarding;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/onboarding")]
public sealed class MobileOnboardingController(
    NeoBankingDbContext dbContext,
    IProxyHoppaRequestUseCase proxyHoppa) : ApiControllerBase
{
    [HttpGet("status")]
    public async Task<ActionResult<object>> GetStatus(CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var userId) || !Guid.TryParse(userId, out var parsedUserId))
        {
            return MissingIdentity<object>();
        }

        return Ok(await BuildStatusAsync(parsedUserId, cancellationToken));
    }

    [HttpPost("start")]
    public async Task<ActionResult<object>> Start(
        [FromBody] StartOnboardingRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var userId) || !Guid.TryParse(userId, out var parsedUserId))
        {
            return MissingIdentity<object>();
        }

        var user = await dbContext.Users
            .SingleOrDefaultAsync(candidate => candidate.Id == parsedUserId, cancellationToken);
        if (user is null)
        {
            return NotFound();
        }

        var accountType = await GetResolvedAccountTypeAsync(user.MetadataJson, cancellationToken);
        var application = await GetLatestApplicationAsync(parsedUserId, cancellationToken);
        if (application is null)
        {
            application = new OnboardingApplication
            {
                CompanyInstallationId = user.CompanyInstallationId,
                ApplicantUserId = parsedUserId,
                Kind = accountType == "business"
                    ? "business"
                    : "individual",
                Status = "started",
                CurrentStep = "profile",
                FormDataJson = JsonSerializer.Serialize(request),
                CreatedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow
            };
            dbContext.OnboardingApplications.Add(application);
        }
        else
        {
            application.Kind = accountType == "business" ? "business" : "individual";
            application.Status = application.Status == "completed" ? application.Status : "started";
            application.CurrentStep = application.CurrentStep == "start" ? "profile" : application.CurrentStep;
            application.FormDataJson = JsonSerializer.Serialize(request);
            application.UpdatedAt = DateTimeOffset.UtcNow;
        }

        await dbContext.SaveChangesAsync(cancellationToken);

        return Ok(await BuildStatusAsync(parsedUserId, cancellationToken));
    }

    [HttpPatch("steps")]
    public async Task<ActionResult<object>> UpdateStep(
        [FromBody] UpdateOnboardingStepRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var userId) || !Guid.TryParse(userId, out var parsedUserId))
        {
            return MissingIdentity<object>();
        }

        var application = await GetLatestApplicationAsync(parsedUserId, cancellationToken);
        if (application is null)
        {
            return NotFound();
        }

        if (!string.IsNullOrWhiteSpace(request.Step))
        {
            application.CurrentStep = request.Step.Trim();
        }

        if (!string.IsNullOrWhiteSpace(request.Status))
        {
            application.Status = request.Status.Trim();
            if (string.Equals(application.Status, "completed", StringComparison.OrdinalIgnoreCase))
            {
                application.CompletedAt = DateTimeOffset.UtcNow;
            }
        }

        application.MetadataJson = JsonSerializer.Serialize(new { request.Notes });
        application.UpdatedAt = DateTimeOffset.UtcNow;
        await dbContext.SaveChangesAsync(cancellationToken);

        return Ok(await BuildStatusAsync(parsedUserId, cancellationToken));
    }

    private Task<OnboardingApplication?> GetLatestApplicationAsync(Guid userId, CancellationToken cancellationToken)
    {
        return dbContext.OnboardingApplications
            .Where(application => application.ApplicantUserId == userId)
            .OrderByDescending(application => application.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);
    }

    private async Task<object> BuildStatusAsync(Guid userId, CancellationToken cancellationToken)
    {
        // Both Hoppa lookups go out before the database is consulted, so the
        // response takes one upstream round trip instead of two in a row.
        var liveAccountTypeTask = GetLiveHoppaAccountTypeAsync(cancellationToken);
        var liveBankingStatusTask = GetLiveBankingStatusAsync(cancellationToken);

        var user = await dbContext.Users
            .AsNoTracking()
            .Where(candidate => candidate.Id == userId)
            .Select(candidate => new { candidate.MetadataJson })
            .SingleOrDefaultAsync(cancellationToken);
        var application = await dbContext.OnboardingApplications
            .AsNoTracking()
            .Where(candidate => candidate.ApplicantUserId == userId)
            .OrderByDescending(candidate => candidate.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        var accountType = await liveAccountTypeTask ?? GetAccountType(user?.MetadataJson);
        var liveBankingStatus = await liveBankingStatusTask;

        return MobileOnboardingStatus.Compose(userId, accountType, application, liveBankingStatus);
    }

    private async Task<string> GetResolvedAccountTypeAsync(string? metadataJson, CancellationToken cancellationToken)
    {
        var localAccountType = GetAccountType(metadataJson);
        var liveAccountType = await GetLiveHoppaAccountTypeAsync(cancellationToken);

        return liveAccountType ?? localAccountType;
    }

    private async Task<string?> GetLiveHoppaAccountTypeAsync(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var hoppaUserId))
        {
            return null;
        }

        var result = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object?>
            {
                Method = HttpMethod.Get,
                UpstreamPath = $"/api/v2/users/{Segment(hoppaUserId)}",
                FailureCode = "mobile.onboarding.user.failed",
                FailureMessage = "We could not load user account type."
            },
            cancellationToken);

        if (!result.IsSuccess || result.Value is null)
        {
            return null;
        }

        return GetAccountTypeFromPayload(result.Value.Value);
    }

    private async Task<string?> GetLiveBankingStatusAsync(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var hoppaUserId))
        {
            return null;
        }

        var result = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object?>
            {
                Method = HttpMethod.Get,
                UpstreamPath = $"/api/v2/users/{Segment(hoppaUserId)}/kyc/detailed-status",
                FailureCode = "mobile.onboarding.banking_status.failed",
                FailureMessage = "We could not load banking status."
            },
            cancellationToken);

        if (!result.IsSuccess || result.Value is null)
        {
            return null;
        }

        return MobileOnboardingStatus.NormalizeBankingStatus(result.Value.Value);
    }

    private static string GetAccountType(string? metadataJson)
    {
        if (string.IsNullOrWhiteSpace(metadataJson))
        {
            return "personal";
        }

        try
        {
            using var document = JsonDocument.Parse(metadataJson);
            if (document.RootElement.TryGetProperty("accountType", out var value) &&
                value.ValueKind == JsonValueKind.String)
            {
                return NormalizeAccountType(value.GetString());
            }
        }
        catch (JsonException)
        {
            return "personal";
        }

        return "personal";
    }

    private static string? GetAccountTypeFromPayload(JsonElement payload)
    {
        var userPayload = UnwrapPayload(payload);
        var accountType = MobileOnboardingStatus.GetString(userPayload, "AccountType", "accountType");

        return string.IsNullOrWhiteSpace(accountType) ? null : NormalizeAccountType(accountType);
    }

    private static JsonElement UnwrapPayload(JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object)
        {
            return payload;
        }

        foreach (var propertyName in new[] { "Data", "data", "User", "user" })
        {
            if (payload.TryGetProperty(propertyName, out var nested) &&
                nested.ValueKind == JsonValueKind.Object)
            {
                return nested;
            }
        }

        return payload;
    }

    private static string NormalizeAccountType(string? accountType)
    {
        return string.Equals(accountType?.Trim(), "business", StringComparison.OrdinalIgnoreCase)
            ? "business"
            : "personal";
    }
}
