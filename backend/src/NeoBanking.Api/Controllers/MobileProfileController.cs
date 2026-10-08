using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Onboarding;
using NeoBanking.Application.Common;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;
using NeoBanking.Domain.Identity;
using NeoBanking.Infrastructure.Persistence;
using Npgsql;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
public sealed class MobileProfileController(
    NeoBankingDbContext dbContext,
    IProxyHoppaRequestUseCase proxyHoppa) : ApiControllerBase
{
    [HttpGet("api/v1/mobile/me")]
    public async Task<ActionResult<object>> GetCurrentUser(CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var userId) || !Guid.TryParse(userId, out var parsedUserId))
        {
            return MissingIdentity<object>();
        }

        var user = await dbContext.Users
            .AsNoTracking()
            .SingleOrDefaultAsync(candidate => candidate.Id == parsedUserId, cancellationToken);
        if (user is null)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(
                new ApplicationError(
                    "mobile.profile.not_found",
                    "Authenticated user was not found.",
                    StatusCodes.Status404NotFound)));
        }

        return Ok(await BuildProfileAsync(user, cancellationToken));
    }

    [HttpPut("api/v1/mobile/profile")]
    public async Task<ActionResult<object>> UpdateProfile(
        [FromBody] UpdateMobileProfileRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var userId) || !Guid.TryParse(userId, out var parsedUserId))
        {
            return MissingIdentity<object>();
        }

        var user = await dbContext.Users
            .Include(candidate => candidate.Identities)
            .SingleOrDefaultAsync(candidate => candidate.Id == parsedUserId, cancellationToken);
        if (user is null)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(
                new ApplicationError(
                    "mobile.profile.not_found",
                    "Authenticated user was not found.",
                    StatusCodes.Status404NotFound)));
        }

        // Null means omitted by an older client; blank explicitly removes a nickname.
        if (request.Nickname is not null)
        {
            var nickname = UserNickname.Normalize(request.Nickname);
            if (!string.IsNullOrWhiteSpace(request.Nickname) && !UserNickname.IsValid(nickname))
            {
                return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                    "mobile.profile.nickname_invalid", UserNickname.RulesMessage, StatusCodes.Status400BadRequest)));
            }
            if (nickname.Length > 0 && await dbContext.Users.AnyAsync(candidate =>
                    candidate.CompanyInstallationId == user.CompanyInstallationId &&
                    candidate.Id != user.Id && candidate.Nickname == nickname, cancellationToken))
            {
                return NicknameInUse();
            }
            user.Nickname = nickname.Length == 0 ? null : nickname;
        }

        if (!string.IsNullOrWhiteSpace(request.Name))
        {
            user.DisplayName = request.Name.Trim();
        }

        if (!string.IsNullOrWhiteSpace(request.Email))
        {
            var email = request.Email.Trim();
            var normalizedEmail = email.ToUpperInvariant();
            var emailInUse = await dbContext.Users.AnyAsync(
                candidate => candidate.CompanyInstallationId == user.CompanyInstallationId &&
                             candidate.Id != user.Id &&
                             candidate.EmailNormalized == normalizedEmail,
                cancellationToken);
            if (emailInUse)
            {
                return ToActionResult<object>(ApplicationResult<object>.Failure(
                    new ApplicationError(
                        "mobile.profile.email_in_use",
                        "Email address is already in use.",
                        StatusCodes.Status409Conflict)));
            }

            user.Email = email;
            user.EmailNormalized = normalizedEmail;

            var localIdentity = user.Identities.FirstOrDefault(identity => identity.Provider == "local" && identity.IsPrimary);
            if (localIdentity is not null)
            {
                localIdentity.Subject = normalizedEmail;
                localIdentity.EmailAtProvider = email;
                localIdentity.UpdatedAt = DateTimeOffset.UtcNow;
            }
        }

        user.UpdatedAt = DateTimeOffset.UtcNow;
        try
        {
            await dbContext.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException
               { SqlState: PostgresErrorCodes.UniqueViolation, ConstraintName: "IX_users_company_nickname" })
        {
            // The index also protects two simultaneous claims of the same nickname.
            return NicknameInUse();
        }

        return Ok(await BuildProfileAsync(user, cancellationToken));
    }

    private ActionResult<object> NicknameInUse() => ToActionResult<object>(ApplicationResult<object>.Failure(
        new ApplicationError("mobile.profile.nickname_in_use", "That nickname is already taken. Choose another.",
            StatusCodes.Status409Conflict)));

    private async Task<object> BuildProfileAsync(ApplicationUser user, CancellationToken cancellationToken)
    {
        // Both Hoppa lookups go out before the database is consulted, so the
        // response takes one upstream round trip instead of two in a row.
        var liveAccountTypeTask = GetLiveAccountTypeAsync(cancellationToken);
        var liveDetailedKycStatusTask = GetLiveDetailedKycStatusAsync(cancellationToken);

        var kycStatus = await dbContext.KycVerifications
            .AsNoTracking()
            .Where(verification => verification.UserId == user.Id)
            .OrderByDescending(verification => verification.CreatedAt)
            .Select(verification => verification.Status)
            .FirstOrDefaultAsync(cancellationToken);
        var application = await dbContext.OnboardingApplications
            .AsNoTracking()
            .Where(candidate => candidate.ApplicantUserId == user.Id)
            .OrderByDescending(candidate => candidate.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        var accountType = await liveAccountTypeTask ?? GetAccountType(user.MetadataJson);
        var liveDetailedKycStatus = await liveDetailedKycStatusTask;
        var liveKycStatus = liveDetailedKycStatus is null
            ? null
            : NormalizeKycStatus(liveDetailedKycStatus.Value);
        var liveBankingStatus = liveDetailedKycStatus is null
            ? null
            : NormalizeBankingStatus(liveDetailedKycStatus.Value);

        return new
        {
            id = user.Id,
            user.Email,
            user.Nickname,
            emailVerified = user.EmailVerifiedAt is not null,
            name = user.DisplayName ?? user.Email,
            user.Status,
            accountType,
            kycStatus = liveKycStatus ?? kycStatus ?? "not_started",
            // Identity approval and bank accounts do not authorize card issuance.
            interlaceKycApproved = liveDetailedKycStatus is { } detailedKyc &&
                IsInterlaceApproved(detailedKyc),
            businessStatus = accountType == "business" ? "not_started" : "not_applicable",
            onboardingStatus = liveBankingStatus ?? application?.Status ?? "not_started",
            // The same block GET onboarding/status returns, built from the
            // responses already in hand so Home does not request it again.
            onboarding = MobileOnboardingStatus.Compose(
                user.Id,
                accountType,
                application,
                liveDetailedKycStatus is null
                    ? null
                    : MobileOnboardingStatus.NormalizeBankingStatus(liveDetailedKycStatus.Value))
        };
    }

    private static string GetAccountType(string metadataJson)
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

    private async Task<string?> GetLiveAccountTypeAsync(CancellationToken cancellationToken)
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
                FailureCode = "mobile.profile.user.failed",
                FailureMessage = "We could not load user profile."
            },
            cancellationToken);

        if (!result.IsSuccess || result.Value is null)
        {
            return null;
        }

        return GetAccountTypeFromPayload(result.Value.Value);
    }

    private async Task<JsonElement?> GetLiveDetailedKycStatusAsync(CancellationToken cancellationToken)
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
                FailureCode = "mobile.profile.kyc_status.failed",
                FailureMessage = "We could not load KYC status."
            },
            cancellationToken);

        if (!result.IsSuccess || result.Value is null)
        {
            return null;
        }

        return result.Value.Value;
    }

    private static bool IsInterlaceApproved(JsonElement payload)
    {
        var approved = GetNestedBoolean(payload, "interlace", "approved") ??
            GetNestedBoolean(payload, "Interlace", "Approved");
        var status = GetNestedString(payload, "interlace", "status") ??
            GetNestedString(payload, "Interlace", "Status");
        var action = GetNestedString(payload, "interlace", "requiredAction") ??
            GetNestedString(payload, "Interlace", "RequiredAction");
        return string.IsNullOrWhiteSpace(action) && approved != false &&
            string.Equals(status, "approved", StringComparison.OrdinalIgnoreCase);
    }

    private static string? NormalizeKycStatus(JsonElement payload)
    {
        if (GetBoolean(payload, "HoppaCardKycApproved", "hoppaCardKycApproved") == true ||
            GetNestedBoolean(payload, "Interlace", "Approved") == true ||
            GetNestedBoolean(payload, "interlace", "approved") == true)
        {
            return "approved";
        }

        var status = GetNestedString(payload, "Interlace", "Status") ??
            GetNestedString(payload, "interlace", "status") ??
            GetString(payload, "KycStatus", "kycStatus");

        return string.IsNullOrWhiteSpace(status) ? null : status;
    }

    private static string? NormalizeBankingStatus(JsonElement payload)
    {
        if (IsEqualsMoneyApproved(payload) == true ||
            HasEqualsMoneyAccount(payload))
        {
            return "completed";
        }

        var status = GetNestedString(payload, "EqualsMoney", "ApplicationStatus") ??
            GetNestedString(payload, "equalsMoney", "applicationStatus") ??
            GetNestedString(payload, "EqualsMoney", "Status") ??
            GetNestedString(payload, "equalsMoney", "status");

        return string.IsNullOrWhiteSpace(status) ? null : status;
    }

    private static bool HasEqualsMoneyAccount(JsonElement payload)
    {
        return !string.IsNullOrWhiteSpace(
            GetNestedString(payload, "EqualsMoney", "AccountId") ??
            GetNestedString(payload, "equalsMoney", "accountId"));
    }

    private static bool? IsEqualsMoneyApproved(JsonElement payload)
    {
        return GetNestedBoolean(payload, "EqualsMoney", "Approved") ??
            GetNestedBoolean(payload, "equalsMoney", "approved");
    }

    private static bool? GetBoolean(JsonElement payload, params string[] propertyNames)
    {
        foreach (var propertyName in propertyNames)
        {
            if (payload.ValueKind == JsonValueKind.Object &&
                payload.TryGetProperty(propertyName, out var property))
            {
                if (property.ValueKind is JsonValueKind.True or JsonValueKind.False)
                {
                    return property.GetBoolean();
                }

                if (property.ValueKind == JsonValueKind.String &&
                    bool.TryParse(property.GetString(), out var value))
                {
                    return value;
                }
            }
        }

        return null;
    }

    private static bool? GetNestedBoolean(JsonElement payload, string objectName, string propertyName)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty(objectName, out var nested))
        {
            return null;
        }

        return GetBoolean(nested, propertyName);
    }

    private static string? GetString(JsonElement payload, params string[] propertyNames)
    {
        foreach (var propertyName in propertyNames)
        {
            if (payload.ValueKind == JsonValueKind.Object &&
                payload.TryGetProperty(propertyName, out var property) &&
                property.ValueKind == JsonValueKind.String)
            {
                return property.GetString();
            }
        }

        return null;
    }

    private static string? GetAccountTypeFromPayload(JsonElement payload)
    {
        var userPayload = UnwrapPayload(payload);
        var accountType = GetString(userPayload, "AccountType", "accountType");

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

    private static string? GetNestedString(JsonElement payload, string objectName, string propertyName)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty(objectName, out var nested))
        {
            return null;
        }

        return GetString(nested, propertyName);
    }
}

public sealed class UpdateMobileProfileRequest
{
    public string? Nickname { get; init; }

    public string? Name { get; init; }

    public string? Email { get; init; }
}
