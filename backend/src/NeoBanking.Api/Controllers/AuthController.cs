using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Company;
using NeoBanking.Api.Email;
using NeoBanking.Infrastructure.Email;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Auth;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;
using NeoBanking.Domain.Security;
using NeoBanking.Infrastructure.Persistence;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace NeoBanking.Api.Controllers;

[Route("api/v1/auth")]
public sealed partial class AuthController(
    NeoBankingDbContext dbContext,
    PasswordHasher<ApplicationUser> passwordHasher,
    IProxyHoppaRequestUseCase proxyHoppa,
    IOptions<JwtOptions> jwtOptions,
    IOptions<CompanyOptions> companyOptions,
    IOptions<EmailOptions> emailOptions,
    AuthEmailNotifier emailNotifier,
    LoginAttemptTracker loginAttempts,
    ILogger<AuthController> logger) : ApiControllerBase
{
    // Two days: the PWA re-verifies biometrics on launch and refreshes the pair anyway.
    private const int AccessTokenSeconds = 48 * 3600;

    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    [HttpPost("login")]
    [HttpPost("~/api/v1/mobile/auth/login")]
    public async Task<ActionResult<AuthTokenResponseDto>> Login([FromBody] LoginRequestDto request, CancellationToken cancellationToken)
    {
        var normalizedEmail = request.Email?.Trim().ToUpperInvariant();
        if (string.IsNullOrWhiteSpace(normalizedEmail) || string.IsNullOrWhiteSpace(request.Password))
        {
            return ToActionResult(AuthTokenResponseDtoFailure(
                "auth.credentials_required",
                "Email and password are required.",
                StatusCodes.Status400BadRequest));
        }

        if (loginAttempts.LockedFor(normalizedEmail) is { } lockedFor)
        {
            return ToActionResult(AuthTokenResponseDtoFailure(
                "auth.locked_out",
                $"Too many failed sign-in attempts. Try again in {Math.Max(1, (int)Math.Ceiling(lockedFor.TotalMinutes))} minutes.",
                StatusCodes.Status429TooManyRequests));
        }

        var identity = await dbContext.UserIdentities
            .Include(userIdentity => userIdentity.User)
            .ThenInclude(user => user!.AdminProfile)
            .SingleOrDefaultAsync(
                userIdentity => userIdentity.Provider == "local" && userIdentity.Subject == normalizedEmail,
                cancellationToken);

        if (identity?.User is null || string.IsNullOrWhiteSpace(identity.PasswordHash))
        {
            loginAttempts.RecordFailure(normalizedEmail);
            return Unauthorized();
        }

        // A duress password looks like a sign-in but locks the account and ends
        // every session; an admin can lift the lock after the cooling-off period.
        if (!string.IsNullOrWhiteSpace(identity.User.DuressPasswordHash) &&
            passwordHasher.VerifyHashedPassword(identity.User, identity.User.DuressPasswordHash, request.Password) != PasswordVerificationResult.Failed)
        {
            await LockAccountAsync(identity.User, "duress", cancellationToken);
            logger.LogWarning("Duress password used for user {UserId}; account locked.", identity.User.Id);
            return ToActionResult(AuthTokenResponseDtoFailure("auth.account_locked", LockedMessage, StatusCodes.Status423Locked));
        }

        var passwordResult = passwordHasher.VerifyHashedPassword(identity.User, identity.PasswordHash, request.Password);
        if (passwordResult == PasswordVerificationResult.Failed)
        {
            loginAttempts.RecordFailure(normalizedEmail);
            return Unauthorized();
        }
        loginAttempts.Reset(normalizedEmail);

        if (identity.User.LockedAt is not null)
        {
            return ToActionResult(AuthTokenResponseDtoFailure("auth.account_locked", LockedMessage, StatusCodes.Status423Locked));
        }

        if (emailOptions.Value.RequireVerifiedEmailForLogin &&
            identity.User.EmailVerifiedAt is null &&
            identity.User.AdminProfile is null)
        {
            return ToActionResult(AuthTokenResponseDtoFailure(
                "auth.email_not_verified",
                "Confirm your email address before signing in. Use the code we emailed you, or request a new one.",
                StatusCodes.Status403Forbidden));
        }

        if (identity.User.TwoFactorEnabled && !string.IsNullOrWhiteSpace(identity.User.TwoFactorSecret))
        {
            return Ok(new AuthTokenResponseDto
            {
                RequiresTwoFactor = true,
                ChallengeToken = CreateChallengeToken(identity.User.Id, request.DeviceName, request.DeviceId),
                Email = identity.User.Email
            });
        }

        return Ok(await IssueTokensAsync(identity, request.DeviceName, request.DeviceId, cancellationToken));
    }

    /// <summary>Second step of sign-in for accounts with 2FA: the challenge from login plus a TOTP or recovery code.</summary>
    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    [HttpPost("login/2fa")]
    [HttpPost("~/api/v1/mobile/auth/login/2fa")]
    public async Task<ActionResult<AuthTokenResponseDto>> CompleteTwoFactorLogin(
        [FromBody] TwoFactorLoginRequestDto request,
        CancellationToken cancellationToken)
    {
        var challenge = ReadChallengeToken(request.ChallengeToken);
        if (challenge is null)
        {
            return ToActionResult(AuthTokenResponseDtoFailure(
                "auth.two_factor_challenge_invalid",
                "The sign-in challenge expired. Enter your password again.",
                StatusCodes.Status401Unauthorized));
        }

        var identity = await dbContext.UserIdentities
            .Include(userIdentity => userIdentity.User)
            .ThenInclude(user => user!.AdminProfile)
            .SingleOrDefaultAsync(
                userIdentity => userIdentity.Provider == "local" && userIdentity.UserId == challenge.Value.UserId,
                cancellationToken);
        if (identity?.User is null)
        {
            return Unauthorized();
        }
        if (identity.User.LockedAt is not null)
        {
            return ToActionResult(AuthTokenResponseDtoFailure("auth.account_locked", LockedMessage, StatusCodes.Status423Locked));
        }

        var attemptKey = $"2fa:{identity.User.EmailNormalized}";
        if (loginAttempts.LockedFor(attemptKey) is { } lockedFor)
        {
            return ToActionResult(AuthTokenResponseDtoFailure(
                "auth.locked_out",
                $"Too many incorrect codes. Try again in {Math.Max(1, (int)Math.Ceiling(lockedFor.TotalMinutes))} minutes.",
                StatusCodes.Status429TooManyRequests));
        }

        if (!await VerifySecondFactorAsync(identity.User, request.Code, cancellationToken))
        {
            loginAttempts.RecordFailure(attemptKey);
            return ToActionResult(AuthTokenResponseDtoFailure(
                "auth.two_factor_invalid",
                "That code is not valid. Enter the current code from your authenticator app or a recovery code.",
                StatusCodes.Status401Unauthorized));
        }
        loginAttempts.Reset(attemptKey);

        return Ok(await IssueTokensAsync(identity, challenge.Value.DeviceName, challenge.Value.DeviceId, cancellationToken));
    }

    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    [HttpPost("~/api/v1/mobile/auth/signup")]
    public async Task<ActionResult<object>> Signup([FromBody] SignupRequestDto request, CancellationToken cancellationToken)
    {
        var email = request.Email?.Trim();
        var normalizedEmail = email?.ToUpperInvariant();
        var accountType = NormalizeAccountType(request.AccountType);
        if (string.IsNullOrWhiteSpace(email) ||
            string.IsNullOrWhiteSpace(normalizedEmail) ||
            string.IsNullOrWhiteSpace(request.Password))
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(
                new ApplicationError(
                    "auth.signup_required_fields",
                    "Email and password are required.",
                    StatusCodes.Status400BadRequest)));
        }

        var passwordError = ValidatePassword(request.Password);
        if (passwordError is not null)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(passwordError));
        }

        if (accountType == "business" && !companyOptions.Value.Features.BusinessOnboardingEnabled)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.signup.business_disabled",
                "Business accounts are not available. Create a personal account instead.",
                StatusCodes.Status400BadRequest)));
        }

        var consentReceivedAt = DateTimeOffset.UtcNow;
        var referralCode = request.ReferralCode?.Trim();
        var referralFeatures = companyOptions.Value.Features;
        var referralRequired = referralFeatures.ReferralsEnabled &&
            string.Equals(
                referralFeatures.ReferralRegistrationMode?.Trim(),
                "required",
                StringComparison.OrdinalIgnoreCase);

        if (referralRequired && string.IsNullOrWhiteSpace(referralCode))
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.referral.required",
                "A valid referral code is required to create an account.",
                StatusCodes.Status400BadRequest)));
        }

        if (!string.IsNullOrWhiteSpace(referralCode))
        {
            if (!referralFeatures.ReferralsEnabled)
            {
                return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                    "auth.referral.disabled",
                    "Referral codes are not enabled for this company.",
                    StatusCodes.Status400BadRequest)));
            }

            var referralCheck = await CheckReferralAsync(referralCode, cancellationToken);
            if (!referralCheck.IsSuccess)
            {
                return ToActionResult<object>(ApplicationResult<object>.Failure(referralCheck.Error!));
            }

            if (!IsValidReferral(referralCheck.Value))
            {
                return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                    "auth.referral.invalid",
                    "The referral code is invalid or no longer available.",
                    StatusCodes.Status400BadRequest)));
            }
        }

        var company = await dbContext.CompanyInstallations
            .SingleOrDefaultAsync(
                installation => installation.Slug == "default",
                cancellationToken);
        if (company is null)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(
                new ApplicationError(
                    "auth.default_company_missing",
                    "Default company installation is not seeded.",
                    StatusCodes.Status500InternalServerError)));
        }

        var existingUser = await dbContext.Users
            .SingleOrDefaultAsync(
                user => user.CompanyInstallationId == company.Id &&
                        user.EmailNormalized == normalizedEmail,
                cancellationToken);
        if (existingUser is not null)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.signup.account_exists",
                "An account with this email already exists. Sign in instead.",
                StatusCodes.Status409Conflict)));
        }

        var attemptId = request.RegistrationAttemptId is { } suppliedAttempt && suppliedAttempt!=Guid.Empty ? suppliedAttempt : Guid.NewGuid();
        var attempt = await dbContext.ReferralSignupAttempts.SingleOrDefaultAsync(x => x.Id == attemptId && x.CompanyInstallationId == company.Id, cancellationToken);
        var emailAttempt = await dbContext.ReferralSignupAttempts.AsNoTracking().SingleOrDefaultAsync(x =>
            x.CompanyInstallationId == company.Id && x.EmailNormalized == normalizedEmail, cancellationToken);
        if (emailAttempt is not null || (attempt is not null && attempt.State != "QUOTED"))
            return SignupCreationUncertain(attemptId);

        var acceptedReferral = !string.IsNullOrWhiteSpace(referralCode) && request.ReferralAccepted == true;
        var referralRequested = !string.IsNullOrWhiteSpace(referralCode) && (acceptedReferral || request.ReferralNeedsReview);
        var validReferralQuote = acceptedReferral && ValidSignupQuote(attempt,request,referralCode!,consentReceivedAt);
        if(attempt is null && await dbContext.ReferralSignupAttempts.AnyAsync(x=>x.Id==attemptId,cancellationToken))
            attemptId=Guid.NewGuid(); // Never adopt a different installation's correlation or quote.
        if (attempt is null)
        {
            attempt = new ReferralSignupAttempt { Id=attemptId, CompanyInstallationId=company.Id };
            dbContext.ReferralSignupAttempts.Add(attempt);
        }
        attempt.EmailNormalized=normalizedEmail; attempt.State="CREATING";
        attempt.ConsentReceivedAt=acceptedReferral ? consentReceivedAt : null;
        // A unique company/email journal prevents concurrent attempts from creating duplicate upstream accounts.
        try { await dbContext.SaveChangesAsync(cancellationToken); }
        catch (DbUpdateException) { return SignupCreationUncertain(attemptId); }

        var now = DateTimeOffset.UtcNow;
        var displayName = GetDisplayName(request);
        var user = new ApplicationUser
        {
            CompanyInstallationId = company.Id,
            Email = email,
            EmailNormalized = normalizedEmail,
            DisplayName = displayName,
            PhoneNumber = request.Phone?.Trim(),
            Status = "active",
            Locale = "en-US",
            MetadataJson = JsonSerializer.Serialize(new { accountType, legalAgreements = request.LegalAgreements }),
            CreatedAt = now,
            UpdatedAt = now
        };

        ApplicationResult<JsonElement?> hoppaUserResult;
        try
        {
        hoppaUserResult = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object>
            {
                Method = HttpMethod.Post,
                UpstreamPath = "/api/v2/users",
                Request = CreateHoppaUserRequest(user, request),
                FailureCode = "auth.signup.hoppa_user_failed",
                FailureMessage = "We could not create the upstream user."
            },
            cancellationToken);
        }
        catch (Exception exception)
        {
            attempt.State="CREATION_UNCERTAIN"; attempt.FailureReason="UPSTREAM_RESPONSE_LOST";
            await dbContext.SaveChangesAsync(CancellationToken.None);
            logger.LogWarning(exception,"Signup attempt {AttemptId} needs account-creation reconciliation.",attempt.Id);
            return SignupCreationUncertain(attempt.Id);
        }
        if (!hoppaUserResult.IsSuccess)
        {
            // The provider could not open the upstream account. Tell the customer
            // plainly (with the provider's reason when it gives one) and use 502 so
            // clients can distinguish it from our own failures.
            var upstream = hoppaUserResult.Error!;
            attempt.State = upstream.StatusCode >= 500 ? "CREATION_UNCERTAIN" : "REJECTED";
            attempt.FailureReason = upstream.Code;
            await dbContext.SaveChangesAsync(CancellationToken.None);
            if (attempt.State == "CREATION_UNCERTAIN") return SignupCreationUncertain(attempt.Id);
            var providerReason = ExtractProviderMessage(upstream.Detail);
            if (upstream.StatusCode == StatusCodes.Status409Conflict ||
                (providerReason?.Contains("already", StringComparison.OrdinalIgnoreCase) ?? false))
            {
                return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                    "auth.signup.provider_account_exists",
                    "An account with this email already exists with our provider. Sign in, or use Connect account to link it to this app.",
                    StatusCodes.Status409Conflict,
                    providerReason)));
            }

            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.signup.provider_unavailable",
                "Our account provider could not create your account right now. Please try again in a few minutes. If you already have an account, sign in or use Connect account instead.",
                StatusCodes.Status502BadGateway,
                providerReason)));
        }

        var hoppaUserId = GetHoppaUserId(hoppaUserResult.Value);
        if (string.IsNullOrWhiteSpace(hoppaUserId))
        {
            attempt.State="CREATION_UNCERTAIN"; attempt.FailureReason="UPSTREAM_ID_MISSING";
            await dbContext.SaveChangesAsync(CancellationToken.None);
            return ToActionResult<object>(ApplicationResult<object>.Failure(
                new ApplicationError(
                    "auth.signup.hoppa_user_missing_id",
                    "The account provider returned an incomplete response.",
                    StatusCodes.Status502BadGateway)));
        }

        user.Identities.Add(new UserIdentity
        {
            CompanyInstallationId = company.Id,
            Provider = "local",
            Subject = normalizedEmail,
            EmailAtProvider = email,
            IsPrimary = true,
            ClaimsJson = JsonSerializer.Serialize(new { role = "User", accountType }),
            PasswordHash = passwordHasher.HashPassword(user, request.Password),
            CreatedAt = now,
            UpdatedAt = now
        });

        dbContext.Users.Add(user);
        dbContext.ProviderMappings.Add(new ProviderMapping
        {
            CompanyInstallationId = company.Id,
            Provider = "hoppa",
            ProviderEntityType = "user",
            ProviderEntityId = hoppaUserId,
            InternalEntityType = "user",
            InternalEntityId = user.Id,
            ExternalStatus = "created",
            LastSyncedAt = now,
            SyncStateJson = hoppaUserResult.Value?.GetRawText() ?? "{}",
            CreatedAt = now,
            UpdatedAt = now
        });
        // Mapping, local identity, signup completion and attribution intent are one local commit.
        attempt.State="ACCOUNT_CREATED"; attempt.ProviderUserId=hoppaUserId; attempt.LocalUserId=user.Id;
        ReferralAttributionIntent? referralIntent = null;
        if (referralRequested)
        {
            using var quote = JsonDocument.Parse(attempt.QuoteJson);
            referralIntent = new ReferralAttributionIntent
            {
                CompanyInstallationId=company.Id, SignupAttemptId=attempt.Id, UserId=user.Id, ProviderUserId=hoppaUserId,
                State=validReferralQuote ? "PENDING" : "NEEDS_REVIEW",
                Reason=validReferralQuote ? null : "QUOTE_CONFIRMATION_REQUIRED"
            };
            if(validReferralQuote) referralIntent.PayloadJson=JsonSerializer.Serialize(new
            {
                commandId=referralIntent.Id, quoteId=attempt.QuoteId, accepted=true,
                termsHash=QuoteString(quote.RootElement,"termsHash"), policyHash=QuoteString(quote.RootElement,"policyHash"),
                // The engine binds DateTime and requires UTC (Z), not a
                // DateTimeOffset string (+00:00) that deserializes as Local.
                consentReceivedAt=attempt.ConsentReceivedAt?.UtcDateTime,
                provenance=attempt.Source == "EMAIL_INVITATION" ? "EMAIL_INVITATION" : "SIGNUP"
            });
            dbContext.ReferralAttributionIntents.Add(referralIntent);
        }
        if(referralFeatures.ReferralsEnabled && int.TryParse(hoppaUserId,out var signalUserId))
        {
            dbContext.ReferralAttributionIntents.Add(new ReferralAttributionIntent
            {
                Kind="SIGNUP_SIGNALS",CompanyInstallationId=company.Id,SignupAttemptId=attempt.Id,UserId=user.Id,ProviderUserId=hoppaUserId,
                PayloadJson=JsonSerializer.Serialize(new
                {
                    userId=signalUserId,sourceEventKey=$"signup:{attempt.Id:D}",
                    // Use the same loopback-only nginx trust boundary as the upstream HTTP client.
                    serverObservedIp=NeoBanking.Infrastructure.Hoppa.TrustedClientAddress.Resolve(HttpContext)?.ToString(),installationToken=request.InstallationToken
                })
            });
        }
        await dbContext.SaveChangesAsync(cancellationToken);

        var verificationEmailSent = false;
        try
        {
            verificationEmailSent = await emailNotifier.SendEmailVerificationAsync(user, cancellationToken);
            await dbContext.SaveChangesAsync(cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            // The account exists; the customer can request a new code from the app.
            logger.LogError(exception, "Verification email could not be queued for new user {UserId}.", user.Id);
            verificationEmailSent = false;
        }

        // Attribution is delivered durably by the worker. Account success is independent of engine admission.
        var referralAttributed = false;
        var referralAttributionReason = !string.IsNullOrWhiteSpace(referralCode) && !acceptedReferral
            ? ReferralAttributionRules.NotAcceptedReason : referralIntent?.Reason;

        return StatusCode(StatusCodes.Status201Created, new
        {
            message = verificationEmailSent
                ? "Account created. Check your email for a confirmation code, then sign in."
                : "Account created. Sign in.",
            userId = user.Id,
            email = user.Email,
            accountType,
            referralAttributed,
            referralAttributionReason,
            registrationAttemptId=attempt.Id,
            referralCommandId=referralIntent?.Id,
            referralAttributionStatus=referralIntent?.State ?? "NOT_REQUESTED",
            emailVerificationRequired = emailOptions.Value.RequireVerifiedEmailForLogin,
            verificationEmailSent
        });
    }

    /// <summary>
    /// Lets the sign-up screen show the friend's welcome offer and the terms version behind a
    /// referral code before the account exists. Passes through what the platform returns.
    /// </summary>
    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    [HttpGet("~/api/v1/mobile/auth/check-referral")]
    public async Task<ActionResult<object>> CheckReferral([FromQuery] string? referralCode, CancellationToken cancellationToken)
    {
        var code = referralCode?.Trim();
        if (string.IsNullOrWhiteSpace(code))
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.referral.code_required",
                "A referral code is required.",
                StatusCodes.Status400BadRequest)));
        }

        if (!companyOptions.Value.Features.ReferralsEnabled)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.referral.disabled",
                "Referral codes are not enabled for this company.",
                StatusCodes.Status400BadRequest)));
        }

        var referralCheck = await CheckReferralAsync(code, cancellationToken);
        if (!referralCheck.IsSuccess)
        {
            // A paused, expired or archived campaign link is a clear answer, not a validation
            // failure: the sign-up page tells the customer and carries on without the code.
            if (IsInactiveCampaignLink(referralCheck.Error!))
            {
                return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                    CampaignLinkInactiveCode,
                    "This invitation link is no longer active.",
                    StatusCodes.Status400BadRequest,
                    "CAMPAIGN_LINK_INACTIVE")));
            }

            return ToActionResult<object>(ApplicationResult<object>.Failure(referralCheck.Error!));
        }

        return Ok(ToReferralCheckPayload(referralCheck.Value));
    }

    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    [HttpPost("~/api/v1/mobile/auth/account-claim/challenges")]
    [HttpPost("account-claim/challenges")]
    public async Task<ActionResult<AccountClaimChallengeResponseDto>> CreateAccountClaimChallenge(
        [FromBody] AccountClaimChallengeRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!companyOptions.Value.Features.ExistingAccountClaimEnabled)
        {
            return NotFound();
        }

        var email = request.Email?.Trim();
        if (string.IsNullOrWhiteSpace(email))
        {
            return ToActionResult<AccountClaimChallengeResponseDto>(ApplicationResult<AccountClaimChallengeResponseDto>.Failure(
                new ApplicationError(
                    "auth.account_claim.email_required",
                    "Email is required.",
                    StatusCodes.Status400BadRequest)));
        }

        var result = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object>
            {
                Method = HttpMethod.Post,
                UpstreamPath = "/api/v2/users/account-claim/challenges",
                Request = new { Email = email },
                FailureCode = "auth.account_claim.request_failed",
                FailureMessage = "Account verification could not be started."
            },
            cancellationToken);
        if (!result.IsSuccess)
        {
            return ToActionResult<AccountClaimChallengeResponseDto>(
                ApplicationResult<AccountClaimChallengeResponseDto>.Failure(result.Error!));
        }

        var challengeIdText = GetJsonValue(result.Value, "challengeId", "ChallengeId");
        var expiresAtText = GetJsonValue(result.Value, "expiresAt", "ExpiresAt");
        if (!Guid.TryParse(challengeIdText, out var challengeId) ||
            !DateTimeOffset.TryParse(expiresAtText, out var expiresAt))
        {
            return ToActionResult<AccountClaimChallengeResponseDto>(ApplicationResult<AccountClaimChallengeResponseDto>.Failure(
                new ApplicationError(
                    "auth.account_claim.invalid_response",
                    "The account provider returned an invalid verification response.",
                    StatusCodes.Status502BadGateway)));
        }

        return Accepted(new AccountClaimChallengeResponseDto
        {
            ChallengeId = challengeId,
            ExpiresAt = expiresAt,
            Message = "If this email belongs to an existing account, a verification code has been sent."
        });
    }

    [AllowAnonymous]
    [HttpPost("~/api/v1/mobile/auth/account-claim/complete")]
    [HttpPost("account-claim/complete")]
    public async Task<ActionResult<object>> CompleteAccountClaim(
        [FromBody] CompleteAccountClaimRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!companyOptions.Value.Features.ExistingAccountClaimEnabled)
        {
            return NotFound();
        }

        var email = request.Email?.Trim();
        var normalizedEmail = email?.ToUpperInvariant();
        if (string.IsNullOrWhiteSpace(email) ||
            string.IsNullOrWhiteSpace(normalizedEmail) ||
            request.ChallengeId == Guid.Empty ||
            string.IsNullOrWhiteSpace(request.Code) ||
            string.IsNullOrWhiteSpace(request.Password))
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.account_claim.required_fields",
                "Email, verification code, challenge ID, and password are required.",
                StatusCodes.Status400BadRequest)));
        }

        if (request.Code.Length != 6 || request.Code.Any(character => !char.IsDigit(character)))
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.account_claim.invalid_code",
                "Enter the six-digit verification code.",
                StatusCodes.Status400BadRequest)));
        }

        var passwordError = ValidatePassword(request.Password);
        if (passwordError is not null)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(passwordError));
        }

        var company = await dbContext.CompanyInstallations
            .SingleOrDefaultAsync(installation => installation.Slug == "default", cancellationToken);
        if (company is null)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.default_company_missing",
                "Default company installation is not seeded.",
                StatusCodes.Status500InternalServerError)));
        }

        var localIdentityExists = await dbContext.UserIdentities.AsNoTracking()
            .AnyAsync(identity => identity.CompanyInstallationId == company.Id &&
                                  identity.Provider == "local" &&
                                  identity.Subject == normalizedEmail,
                cancellationToken);
        if (localIdentityExists)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.account_claim.account_exists",
                "This account is already connected. Sign in instead.",
                StatusCodes.Status409Conflict)));
        }

        var verificationResult = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object>
            {
                Method = HttpMethod.Post,
                UpstreamPath = "/api/v2/users/account-claim/challenges/verify",
                Request = new
                {
                    ChallengeId = request.ChallengeId,
                    Code = request.Code
                },
                FailureCode = "auth.account_claim.verification_failed",
                FailureMessage = "The verification code is invalid or expired."
            },
            cancellationToken);
        if (!verificationResult.IsSuccess)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(verificationResult.Error!));
        }

        return await ConnectVerifiedHoppaIdentityAsync(
            verificationResult.Value,
            request.Password,
            normalizedEmail,
            "hoppa_account_claim",
            cancellationToken);
    }

    [AllowAnonymous]
    [HttpPost("~/api/v1/mobile/auth/account-link/scan")]
    public async Task<ActionResult<AccountLinkStatusResponseDto>> ScanAccountLink(
        [FromBody] ScanAccountLinkRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!companyOptions.Value.Features.ExistingAccountClaimEnabled)
        {
            return NotFound();
        }

        var token = ExtractAccountLinkToken(request.QrPayload);
        if (string.IsNullOrWhiteSpace(token))
        {
            return ToActionResult<AccountLinkStatusResponseDto>(
                ApplicationResult<AccountLinkStatusResponseDto>.Failure(new ApplicationError(
                    "auth.account_link.invalid_qr",
                    "This is not a valid account-transfer QR code.",
                    StatusCodes.Status400BadRequest)));
        }

        var result = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object>
            {
                Method = HttpMethod.Post,
                UpstreamPath = "/api/v2/users/account-links/scan",
                Request = new
                {
                    Token = token,
                    ApplicationName = companyOptions.Value.BrandName,
                    DeviceName = string.IsNullOrWhiteSpace(request.DeviceName)
                        ? null
                        : request.DeviceName.Trim()[..Math.Min(request.DeviceName.Trim().Length, 160)]
                },
                FailureCode = "auth.account_link.scan_failed",
                FailureMessage = "This account-transfer QR code is invalid or expired."
            },
            cancellationToken);

        return ToAccountLinkStatusResult(result);
    }

    [AllowAnonymous]
    [HttpPost("~/api/v1/mobile/auth/account-link/status")]
    public async Task<ActionResult<AccountLinkStatusResponseDto>> GetAccountLinkStatus(
        [FromBody] AccountLinkTokenRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!companyOptions.Value.Features.ExistingAccountClaimEnabled)
        {
            return NotFound();
        }

        if (string.IsNullOrWhiteSpace(request.Token))
        {
            return ToActionResult<AccountLinkStatusResponseDto>(
                ApplicationResult<AccountLinkStatusResponseDto>.Failure(new ApplicationError(
                    "auth.account_link.token_required",
                    "Account-transfer token is required.",
                    StatusCodes.Status400BadRequest)));
        }

        var result = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object>
            {
                Method = HttpMethod.Post,
                UpstreamPath = "/api/v2/users/account-links/status",
                Request = new { Token = request.Token.Trim() },
                FailureCode = "auth.account_link.status_failed",
                FailureMessage = "The account-transfer request is no longer available."
            },
            cancellationToken);

        return ToAccountLinkStatusResult(result);
    }

    [AllowAnonymous]
    [HttpPost("~/api/v1/mobile/auth/account-link/complete")]
    public async Task<ActionResult<object>> CompleteAccountLink(
        [FromBody] CompleteAccountLinkRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!companyOptions.Value.Features.ExistingAccountClaimEnabled)
        {
            return NotFound();
        }

        if (string.IsNullOrWhiteSpace(request.Token) || string.IsNullOrWhiteSpace(request.Password))
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.account_link.required_fields",
                "Account-transfer token and password are required.",
                StatusCodes.Status400BadRequest)));
        }

        var passwordError = ValidatePassword(request.Password);
        if (passwordError is not null)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(passwordError));
        }

        var exchangeResult = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object>
            {
                Method = HttpMethod.Post,
                UpstreamPath = "/api/v2/users/account-links/exchange",
                Request = new { Token = request.Token.Trim() },
                FailureCode = "auth.account_link.exchange_failed",
                FailureMessage = "Approve the account transfer in your existing account's Security page before continuing."
            },
            cancellationToken);
        if (!exchangeResult.IsSuccess)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(exchangeResult.Error!));
        }

        return await ConnectVerifiedHoppaIdentityAsync(
            exchangeResult.Value,
            request.Password,
            expectedNormalizedEmail: null,
            source: "hoppa_account_link",
            cancellationToken);
    }

    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    [HttpPost("refresh")]
    [HttpPost("~/api/v1/mobile/auth/refresh")]
    public async Task<ActionResult<AuthTokenResponseDto>> Refresh(
        [FromBody] RefreshTokenRequestDto request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.RefreshToken))
        {
            return ToActionResult(AuthTokenResponseDtoFailure(
                "auth.refresh_token_required",
                "Refresh token is required.",
                StatusCodes.Status400BadRequest));
        }

        var refreshHash = HashToken(request.RefreshToken);
        var session = await dbContext.RefreshSessions
            .Include(refreshSession => refreshSession.User)
            .ThenInclude(user => user!.AdminProfile)
            .SingleOrDefaultAsync(
                refreshSession => refreshSession.TokenHash == refreshHash,
                cancellationToken);

        if (session is { RevokedAt: not null, RevocationReason: "rotated" })
        {
            // A rotated token came back: either a replayed copy or a stolen one.
            // Revoke every live session for the user so the thief is cut off too.
            var reuseNow = DateTimeOffset.UtcNow;
            var liveSessions = await dbContext.RefreshSessions
                .Where(candidate => candidate.UserId == session.UserId && candidate.RevokedAt == null)
                .ToListAsync(cancellationToken);
            foreach (var live in liveSessions)
            {
                live.RevokedAt = reuseNow;
                live.RevocationReason = "reuse-detected";
                live.UpdatedAt = reuseNow;
            }
            await dbContext.SaveChangesAsync(cancellationToken);
            logger.LogWarning("Refresh token reuse detected for user {UserId}; all sessions revoked.", session.UserId);
            return Unauthorized();
        }

        if (session?.User is null || session.RevokedAt is not null || session.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            return Unauthorized();
        }
        if (session.User.LockedAt is not null)
        {
            return ToActionResult(AuthTokenResponseDtoFailure("auth.account_locked", LockedMessage, StatusCodes.Status423Locked));
        }

        var roles = session.User.AdminProfile is not null
            ? new[] { ApplicationRoles.Admin }
            : new[] { ApplicationRoles.User };
        var hoppaUserId = await GetHoppaUserIdAsync(session.User.Id, session.User.CompanyInstallationId, cancellationToken);
        var newRefreshToken = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
        var now = DateTimeOffset.UtcNow;

        session.LastUsedAt = now;
        session.UpdatedAt = now;
        // Single use: the presented token dies with this rotation.
        session.RevokedAt = now;
        session.RevocationReason = "rotated";

        var rotated = new RefreshSession
        {
            CompanyInstallationId = session.CompanyInstallationId,
            UserId = session.UserId,
            TokenHash = HashToken(newRefreshToken),
            RotatedFromTokenHash = refreshHash,
            DeviceId = session.DeviceId,
            DeviceName = session.DeviceName,
            IpAddress = GetClientIpAddress() ?? HttpContext.Connection.RemoteIpAddress?.ToString(),
            UserAgent = Truncate(Request.Headers.UserAgent.ToString(), 512),
            // Keep the original sign-in time so the device list shows when the
            // device was first trusted, not the last silent rotation.
            CreatedAt = session.CreatedAt,
            ExpiresAt = now.AddDays(30),
            UpdatedAt = now
        };
        dbContext.RefreshSessions.Add(rotated);
        var accessToken = CreateJwt(session.User, roles, hoppaUserId, rotated.Id);

        await dbContext.SaveChangesAsync(cancellationToken);

        return Ok(new AuthTokenResponseDto
        {
            AccessToken = accessToken,
            RefreshToken = newRefreshToken,
            ExpiresInSeconds = AccessTokenSeconds,
            Roles = roles,
            UserName = session.User.DisplayName ?? session.User.Email,
            Email = session.User.Email
        });
    }

    private const string LockedMessage = "This account is temporarily locked. Contact support to restore access.";

    [Authorize(Policy = AuthorizationPolicyNames.AuthenticatedUser)]
    [HttpGet("security")]
    [HttpGet("~/api/v1/mobile/auth/security")]
    public async Task<ActionResult<AccountSecurityDto>> GetSecurity(CancellationToken cancellationToken)
    {
        var identity = await GetCurrentLocalIdentityAsync(cancellationToken);
        if (identity?.User is null)
        {
            return Unauthorized();
        }
        return Ok(ToSecurityDto(identity.User));
    }

    /// <summary>Starts 2FA enrolment: returns a fresh secret to scan. Nothing is enforced until enable confirms a code.</summary>
    [Authorize(Policy = AuthorizationPolicyNames.AuthenticatedUser)]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    [HttpPost("2fa/setup")]
    [HttpPost("~/api/v1/mobile/auth/2fa/setup")]
    public async Task<ActionResult<TwoFactorSetupResponseDto>> SetupTwoFactor(
        [FromBody] PasswordConfirmRequestDto request,
        CancellationToken cancellationToken)
    {
        var identity = await GetCurrentLocalIdentityAsync(cancellationToken);
        if (identity?.User is null)
        {
            return Unauthorized();
        }
        if (!VerifyCurrentPassword(identity, request.CurrentPassword))
        {
            return Problem("auth.password_incorrect", "Your current password is incorrect.", StatusCodes.Status401Unauthorized);
        }
        if (identity.User.TwoFactorEnabled)
        {
            return Problem("auth.two_factor_already_enabled", "Two-factor authentication is already on. Turn it off before setting it up again.", StatusCodes.Status409Conflict);
        }

        var secret = Totp.GenerateSecret();
        identity.User.TwoFactorSecret = secret;
        identity.User.UpdatedAt = DateTimeOffset.UtcNow;
        await dbContext.SaveChangesAsync(cancellationToken);

        var issuer = string.IsNullOrWhiteSpace(companyOptions.Value.BrandName) ? companyOptions.Value.Name : companyOptions.Value.BrandName;
        return Ok(new TwoFactorSetupResponseDto
        {
            Secret = secret,
            OtpauthUri = Totp.BuildUri(issuer, identity.User.Email, secret)
        });
    }

    /// <summary>Confirms enrolment with a code from the authenticator and returns the one-time recovery codes.</summary>
    [Authorize(Policy = AuthorizationPolicyNames.AuthenticatedUser)]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    [HttpPost("2fa/enable")]
    [HttpPost("~/api/v1/mobile/auth/2fa/enable")]
    public async Task<ActionResult<TwoFactorEnableResponseDto>> EnableTwoFactor(
        [FromBody] TwoFactorCodeRequestDto request,
        CancellationToken cancellationToken)
    {
        var identity = await GetCurrentLocalIdentityAsync(cancellationToken);
        if (identity?.User is null)
        {
            return Unauthorized();
        }
        var user = identity.User;
        if (string.IsNullOrWhiteSpace(user.TwoFactorSecret))
        {
            return Problem("auth.two_factor_not_started", "Start two-factor setup first.", StatusCodes.Status409Conflict);
        }
        if (!Totp.Verify(user.TwoFactorSecret, request.Code))
        {
            return Problem("auth.two_factor_invalid", "That code is not valid. Check the authenticator app and try again.", StatusCodes.Status400BadRequest);
        }

        var codes = RecoveryCodes.Generate();
        var now = DateTimeOffset.UtcNow;
        user.TwoFactorEnabled = true;
        user.TwoFactorEnabledAt = now;
        user.RecoveryCodesJson = JsonSerializer.Serialize(codes.Select(RecoveryCodes.Hash).ToList());
        user.UpdatedAt = now;
        await dbContext.SaveChangesAsync(cancellationToken);

        return Ok(new TwoFactorEnableResponseDto { RecoveryCodes = codes });
    }

    /// <summary>Turns 2FA off; needs a current code or a recovery code so a hijacked session cannot do it alone.</summary>
    [Authorize(Policy = AuthorizationPolicyNames.AuthenticatedUser)]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    [HttpPost("2fa/disable")]
    [HttpPost("~/api/v1/mobile/auth/2fa/disable")]
    public async Task<ActionResult<AccountSecurityDto>> DisableTwoFactor(
        [FromBody] TwoFactorCodeRequestDto request,
        CancellationToken cancellationToken)
    {
        var identity = await GetCurrentLocalIdentityAsync(cancellationToken);
        if (identity?.User is null)
        {
            return Unauthorized();
        }
        var user = identity.User;
        if (!user.TwoFactorEnabled)
        {
            return Ok(ToSecurityDto(user));
        }
        if (!await VerifySecondFactorAsync(user, request.Code, cancellationToken))
        {
            return Problem("auth.two_factor_invalid", "That code is not valid. Enter the current code from your authenticator app or a recovery code.", StatusCodes.Status400BadRequest);
        }

        user.TwoFactorEnabled = false;
        user.TwoFactorSecret = null;
        user.TwoFactorEnabledAt = null;
        user.RecoveryCodesJson = "[]";
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await dbContext.SaveChangesAsync(cancellationToken);
        return Ok(ToSecurityDto(user));
    }

    [Authorize(Policy = AuthorizationPolicyNames.AuthenticatedUser)]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    [HttpPost("password/change")]
    [HttpPost("~/api/v1/mobile/auth/password/change")]
    public async Task<ActionResult<AccountSecurityDto>> ChangePassword(
        [FromBody] ChangePasswordRequestDto request,
        CancellationToken cancellationToken)
    {
        var identity = await GetCurrentLocalIdentityAsync(cancellationToken);
        if (identity?.User is null)
        {
            return Unauthorized();
        }
        if (!VerifyCurrentPassword(identity, request.CurrentPassword))
        {
            return Problem("auth.password_incorrect", "Your current password is incorrect.", StatusCodes.Status401Unauthorized);
        }
        var newPassword = request.NewPassword ?? string.Empty;
        var validation = ValidatePassword(newPassword);
        if (validation is not null)
        {
            return ToActionResult(ApplicationResult<AccountSecurityDto>.Failure(validation));
        }
        if (newPassword == request.CurrentPassword)
        {
            return Problem("auth.password_unchanged", "Choose a password you have not used as your current password.", StatusCodes.Status400BadRequest);
        }
        if (!string.IsNullOrWhiteSpace(identity.User.DuressPasswordHash) &&
            passwordHasher.VerifyHashedPassword(identity.User, identity.User.DuressPasswordHash, newPassword) != PasswordVerificationResult.Failed)
        {
            return Problem("auth.password_matches_duress", "Your password cannot be the same as your duress password.", StatusCodes.Status400BadRequest);
        }

        var now = DateTimeOffset.UtcNow;
        identity.PasswordHash = passwordHasher.HashPassword(identity.User, newPassword);
        identity.User.PasswordChangedAt = now;
        identity.User.UpdatedAt = now;

        // Other devices must sign in again with the new password.
        var currentSessionId = CurrentSessionId();
        var others = await dbContext.RefreshSessions
            .Where(session => session.UserId == identity.UserId && session.RevokedAt == null && session.Id != currentSessionId)
            .ToListAsync(cancellationToken);
        foreach (var session in others)
        {
            session.RevokedAt = now;
            session.RevocationReason = "password-changed";
            session.UpdatedAt = now;
        }
        await dbContext.SaveChangesAsync(cancellationToken);
        return Ok(ToSecurityDto(identity.User));
    }

    /// <summary>Sets the duress password. It must differ from the real password so it cannot lock the customer out by mistake.</summary>
    [Authorize(Policy = AuthorizationPolicyNames.AuthenticatedUser)]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    [HttpPost("duress")]
    [HttpPost("~/api/v1/mobile/auth/duress")]
    public async Task<ActionResult<AccountSecurityDto>> SetDuressPassword(
        [FromBody] DuressPasswordRequestDto request,
        CancellationToken cancellationToken)
    {
        var identity = await GetCurrentLocalIdentityAsync(cancellationToken);
        if (identity?.User is null)
        {
            return Unauthorized();
        }
        if (!VerifyCurrentPassword(identity, request.CurrentPassword))
        {
            return Problem("auth.password_incorrect", "Your current password is incorrect.", StatusCodes.Status401Unauthorized);
        }
        var duress = request.DuressPassword ?? string.Empty;
        if (duress.Length < 8)
        {
            return Problem("auth.duress_too_short", "The duress password must be at least 8 characters.", StatusCodes.Status400BadRequest);
        }
        if (duress == request.CurrentPassword ||
            passwordHasher.VerifyHashedPassword(identity.User, identity.PasswordHash ?? string.Empty, duress) != PasswordVerificationResult.Failed)
        {
            return Problem("auth.duress_matches_password", "The duress password must be different from your sign-in password.", StatusCodes.Status400BadRequest);
        }

        identity.User.DuressPasswordHash = passwordHasher.HashPassword(identity.User, duress);
        identity.User.UpdatedAt = DateTimeOffset.UtcNow;
        await dbContext.SaveChangesAsync(cancellationToken);
        return Ok(ToSecurityDto(identity.User));
    }

    [Authorize(Policy = AuthorizationPolicyNames.AuthenticatedUser)]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    [HttpDelete("duress")]
    [HttpDelete("~/api/v1/mobile/auth/duress")]
    [HttpPost("duress/remove")]
    [HttpPost("~/api/v1/mobile/auth/duress/remove")]
    public async Task<ActionResult<AccountSecurityDto>> RemoveDuressPassword(
        [FromBody] PasswordConfirmRequestDto request,
        CancellationToken cancellationToken)
    {
        var identity = await GetCurrentLocalIdentityAsync(cancellationToken);
        if (identity?.User is null)
        {
            return Unauthorized();
        }
        if (!VerifyCurrentPassword(identity, request.CurrentPassword))
        {
            return Problem("auth.password_incorrect", "Your current password is incorrect.", StatusCodes.Status401Unauthorized);
        }
        identity.User.DuressPasswordHash = null;
        identity.User.UpdatedAt = DateTimeOffset.UtcNow;
        await dbContext.SaveChangesAsync(cancellationToken);
        return Ok(ToSecurityDto(identity.User));
    }

    private async Task<AuthTokenResponseDto> IssueTokensAsync(
        UserIdentity identity,
        string? deviceName,
        string? deviceId,
        CancellationToken cancellationToken)
    {
        var user = identity.User!;
        var roles = user.AdminProfile is not null
            ? new[] { ApplicationRoles.Admin }
            : new[] { ApplicationRoles.User };
        var hoppaUserId = await GetHoppaUserIdAsync(user.Id, user.CompanyInstallationId, cancellationToken);
        var refreshToken = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
        var now = DateTimeOffset.UtcNow;

        var refreshSession = new RefreshSession
        {
            CompanyInstallationId = identity.CompanyInstallationId,
            UserId = identity.UserId,
            TokenHash = HashToken(refreshToken),
            DeviceId = Truncate(deviceId, 120),
            DeviceName = Truncate(deviceName, 160),
            IpAddress = GetClientIpAddress() ?? HttpContext.Connection.RemoteIpAddress?.ToString(),
            UserAgent = Truncate(Request.Headers.UserAgent.ToString(), 512),
            ExpiresAt = now.AddDays(30),
            CreatedAt = now,
            UpdatedAt = now
        };
        dbContext.RefreshSessions.Add(refreshSession);
        var accessToken = CreateJwt(user, roles, hoppaUserId, refreshSession.Id);

        identity.LastAuthenticatedAt = now;
        user.LastLoginAt = now;
        await dbContext.SaveChangesAsync(cancellationToken);

        return new AuthTokenResponseDto
        {
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            ExpiresInSeconds = AccessTokenSeconds,
            Roles = roles,
            UserName = user.DisplayName ?? user.Email,
            Email = user.Email
        };
    }

    private async Task LockAccountAsync(ApplicationUser user, string reason, CancellationToken cancellationToken)
    {
        var now = DateTimeOffset.UtcNow;
        user.LockedAt = now;
        user.LockReason = reason;
        user.Status = "locked";
        user.UpdatedAt = now;
        var sessions = await dbContext.RefreshSessions
            .Where(session => session.UserId == user.Id && session.RevokedAt == null)
            .ToListAsync(cancellationToken);
        foreach (var session in sessions)
        {
            session.RevokedAt = now;
            session.RevocationReason = "account-locked";
            session.UpdatedAt = now;
        }
        await dbContext.SaveChangesAsync(cancellationToken);
    }

    private async Task<UserIdentity?> GetCurrentLocalIdentityAsync(CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var userId))
        {
            return null;
        }
        return await dbContext.UserIdentities
            .Include(identity => identity.User)
            .ThenInclude(user => user!.AdminProfile)
            .SingleOrDefaultAsync(identity => identity.Provider == "local" && identity.UserId == userId, cancellationToken);
    }

    private bool VerifyCurrentPassword(UserIdentity identity, string? password) =>
        !string.IsNullOrWhiteSpace(password) &&
        !string.IsNullOrWhiteSpace(identity.PasswordHash) &&
        passwordHasher.VerifyHashedPassword(identity.User!, identity.PasswordHash, password) != PasswordVerificationResult.Failed;

    /// <summary>TOTP first; otherwise an unused recovery code, which is consumed.</summary>
    private async Task<bool> VerifySecondFactorAsync(ApplicationUser user, string? code, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(code))
        {
            return false;
        }
        if (!string.IsNullOrWhiteSpace(user.TwoFactorSecret) && Totp.Verify(user.TwoFactorSecret, code))
        {
            return true;
        }
        List<string> hashes;
        try
        {
            hashes = JsonSerializer.Deserialize<List<string>>(user.RecoveryCodesJson) ?? new();
        }
        catch (JsonException)
        {
            hashes = new();
        }
        var presented = RecoveryCodes.Hash(code);
        var index = hashes.FindIndex(hash => string.Equals(hash, presented, StringComparison.OrdinalIgnoreCase));
        if (index < 0)
        {
            return false;
        }
        hashes.RemoveAt(index);
        user.RecoveryCodesJson = JsonSerializer.Serialize(hashes);
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await dbContext.SaveChangesAsync(cancellationToken);
        return true;
    }

    private static AccountSecurityDto ToSecurityDto(ApplicationUser user)
    {
        int remaining;
        try
        {
            remaining = JsonSerializer.Deserialize<List<string>>(user.RecoveryCodesJson)?.Count ?? 0;
        }
        catch (JsonException)
        {
            remaining = 0;
        }
        return new AccountSecurityDto
        {
            TwoFactorEnabled = user.TwoFactorEnabled,
            TwoFactorEnabledAt = user.TwoFactorEnabledAt,
            RecoveryCodesRemaining = user.TwoFactorEnabled ? remaining : 0,
            DuressPasswordSet = !string.IsNullOrWhiteSpace(user.DuressPasswordHash),
            PasswordChangedAt = user.PasswordChangedAt
        };
    }

    private ActionResult<T> Problem<T>(string code, string message, int status) =>
        ToActionResult(ApplicationResult<T>.Failure(new ApplicationError(code, message, status)));

    private ObjectResult Problem(string code, string message, int status) =>
        StatusCode(status, new { code, message });

    // ---- 2FA challenge token: signed, five minutes, bound to the user ----

    private readonly record struct TwoFactorChallenge(Guid UserId, string? DeviceName, string? DeviceId);

    private string CreateChallengeToken(Guid userId, string? deviceName, string? deviceId)
    {
        var payload = Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(new
        {
            purpose = "2fa",
            uid = userId,
            dev = deviceName,
            did = deviceId,
            exp = DateTimeOffset.UtcNow.AddMinutes(5).ToUnixTimeSeconds(),
            nonce = Convert.ToHexString(RandomNumberGenerator.GetBytes(8))
        }));
        return $"{payload}.{Sign(payload, jwtOptions.Value.SigningKey)}";
    }

    private TwoFactorChallenge? ReadChallengeToken(string? token)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            return null;
        }
        var parts = token.Split('.');
        if (parts.Length != 2)
        {
            return null;
        }
        var expected = Sign(parts[0], jwtOptions.Value.SigningKey);
        if (!CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(expected), Encoding.ASCII.GetBytes(parts[1])))
        {
            return null;
        }
        try
        {
            using var document = JsonDocument.Parse(Base64UrlDecode(parts[0]));
            var root = document.RootElement;
            if (root.GetProperty("purpose").GetString() != "2fa" ||
                root.GetProperty("exp").GetInt64() < DateTimeOffset.UtcNow.ToUnixTimeSeconds())
            {
                return null;
            }
            return new TwoFactorChallenge(
                root.GetProperty("uid").GetGuid(),
                root.TryGetProperty("dev", out var dev) ? dev.GetString() : null,
                root.TryGetProperty("did", out var did) ? did.GetString() : null);
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static byte[] Base64UrlDecode(string value)
    {
        var padded = value.Replace('-', '+').Replace('_', '/');
        padded = padded.PadRight(padded.Length + (4 - padded.Length % 4) % 4, '=');
        return Convert.FromBase64String(padded);
    }

    /// <summary>Live sessions (devices) for the signed-in user, newest activity first.</summary>
    [Authorize(Policy = AuthorizationPolicyNames.AuthenticatedUser)]
    [HttpGet("sessions")]
    [HttpGet("~/api/v1/mobile/auth/sessions")]
    public async Task<ActionResult<IReadOnlyList<AuthSessionDto>>> ListSessions(CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var userId))
        {
            return Unauthorized();
        }

        var currentSessionId = CurrentSessionId();
        var now = DateTimeOffset.UtcNow;
        var sessions = await dbContext.RefreshSessions
            .AsNoTracking()
            .Where(session => session.UserId == userId && session.RevokedAt == null && session.ExpiresAt > now)
            .OrderByDescending(session => session.LastUsedAt ?? session.CreatedAt)
            .ToListAsync(cancellationToken);

        return Ok(sessions.Select(session => new AuthSessionDto
        {
            Id = session.Id,
            DeviceName = DescribeDevice(session),
            UserAgent = session.UserAgent,
            IpAddress = session.IpAddress,
            CreatedAt = session.CreatedAt,
            LastUsedAt = session.LastUsedAt,
            ExpiresAt = session.ExpiresAt,
            IsCurrent = currentSessionId == session.Id
        }).ToList());
    }

    /// <summary>Signs out one device. The current session may be revoked too; the client then clears its tokens.</summary>
    [Authorize(Policy = AuthorizationPolicyNames.AuthenticatedUser)]
    [HttpDelete("sessions/{sessionId:guid}")]
    [HttpDelete("~/api/v1/mobile/auth/sessions/{sessionId:guid}")]
    public async Task<IActionResult> RevokeSession(Guid sessionId, CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var userId))
        {
            return Unauthorized();
        }

        var session = await dbContext.RefreshSessions
            .SingleOrDefaultAsync(candidate => candidate.Id == sessionId && candidate.UserId == userId, cancellationToken);
        if (session is null)
        {
            return NotFound();
        }
        if (session.RevokedAt is null)
        {
            var now = DateTimeOffset.UtcNow;
            session.RevokedAt = now;
            session.RevocationReason = "revoked-by-user";
            session.UpdatedAt = now;
            await dbContext.SaveChangesAsync(cancellationToken);
        }

        return NoContent();
    }

    /// <summary>Signs out every device except the one making the request.</summary>
    [Authorize(Policy = AuthorizationPolicyNames.AuthenticatedUser)]
    [HttpPost("sessions/revoke-others")]
    [HttpPost("~/api/v1/mobile/auth/sessions/revoke-others")]
    public async Task<IActionResult> RevokeOtherSessions(CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var userId))
        {
            return Unauthorized();
        }

        var currentSessionId = CurrentSessionId();
        var now = DateTimeOffset.UtcNow;
        var others = await dbContext.RefreshSessions
            .Where(session => session.UserId == userId && session.RevokedAt == null && session.Id != currentSessionId)
            .ToListAsync(cancellationToken);
        foreach (var session in others)
        {
            session.RevokedAt = now;
            session.RevocationReason = "revoked-by-user";
            session.UpdatedAt = now;
        }
        if (others.Count > 0)
        {
            await dbContext.SaveChangesAsync(cancellationToken);
        }

        return Ok(new { revoked = others.Count });
    }

    private Guid? CurrentSessionId()
    {
        var raw = User.FindFirst("sid")?.Value;
        return Guid.TryParse(raw, out var id) ? id : null;
    }

    private static string? Truncate(string? value, int max)
    {
        var trimmed = value?.Trim();
        if (string.IsNullOrEmpty(trimmed)) return null;
        return trimmed.Length <= max ? trimmed : trimmed[..max];
    }

    /// <summary>Client-supplied name first, then a readable guess from the user agent.</summary>
    private static string DescribeDevice(RefreshSession session)
    {
        if (!string.IsNullOrWhiteSpace(session.DeviceName))
        {
            return session.DeviceName;
        }
        var ua = session.UserAgent ?? string.Empty;
        string os =
            ua.Contains("iPhone", StringComparison.OrdinalIgnoreCase) ? "iPhone" :
            ua.Contains("iPad", StringComparison.OrdinalIgnoreCase) ? "iPad" :
            ua.Contains("Android", StringComparison.OrdinalIgnoreCase) ? "Android" :
            ua.Contains("Macintosh", StringComparison.OrdinalIgnoreCase) ? "Mac" :
            ua.Contains("Windows", StringComparison.OrdinalIgnoreCase) ? "Windows" :
            ua.Contains("Linux", StringComparison.OrdinalIgnoreCase) ? "Linux" :
            ua.Contains("Dart", StringComparison.OrdinalIgnoreCase) ? "Mobile app" : "Unknown device";
        string browser =
            ua.Contains("Edg/", StringComparison.OrdinalIgnoreCase) ? "Edge" :
            ua.Contains("Chrome/", StringComparison.OrdinalIgnoreCase) ? "Chrome" :
            ua.Contains("Firefox/", StringComparison.OrdinalIgnoreCase) ? "Firefox" :
            ua.Contains("Safari/", StringComparison.OrdinalIgnoreCase) ? "Safari" : string.Empty;
        return string.IsNullOrEmpty(browser) ? os : $"{os} · {browser}";
    }

    /// <summary>
    /// Revokes the caller's refresh session. With a refresh token in the body only
    /// that session ends; without one every live session for the user is revoked.
    /// </summary>
    [Authorize(Policy = AuthorizationPolicyNames.AuthenticatedUser)]
    [HttpPost("logout")]
    [HttpPost("~/api/v1/mobile/auth/logout")]
    public async Task<IActionResult> Logout([FromBody] RefreshTokenRequestDto? request, CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var userId))
        {
            return NoContent();
        }

        var now = DateTimeOffset.UtcNow;
        var query = dbContext.RefreshSessions.Where(session => session.UserId == userId && session.RevokedAt == null);
        if (!string.IsNullOrWhiteSpace(request?.RefreshToken))
        {
            var hash = HashToken(request.RefreshToken);
            query = query.Where(session => session.TokenHash == hash);
        }

        var sessions = await query.ToListAsync(cancellationToken);
        foreach (var session in sessions)
        {
            session.RevokedAt = now;
            session.RevocationReason = "logout";
            session.UpdatedAt = now;
        }
        if (sessions.Count > 0)
        {
            await dbContext.SaveChangesAsync(cancellationToken);
        }

        return NoContent();
    }

    private string CreateJwt(ApplicationUser user, IReadOnlyList<string> roles, string? hoppaUserId, Guid? sessionId = null)
    {
        var options = jwtOptions.Value;
        var now = DateTimeOffset.UtcNow;
        var payload = new Dictionary<string, object?>
        {
            ["iss"] = options.Issuer,
            ["sid"] = sessionId?.ToString(),
            ["aud"] = options.Audience,
            ["sub"] = hoppaUserId ?? user.Id.ToString(),
            ["local_user_id"] = user.Id.ToString(),
            ["company_installation_id"] = user.CompanyInstallationId.ToString(),
            ["hoppa_user_id"] = hoppaUserId,
            ["name"] = user.DisplayName ?? user.Email,
            ["email"] = user.Email,
            ["role"] = roles,
            ["iat"] = now.ToUnixTimeSeconds(),
            ["nbf"] = now.ToUnixTimeSeconds(),
            ["exp"] = now.AddSeconds(AccessTokenSeconds).ToUnixTimeSeconds()
        };

        var header = Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(new { alg = "HS256", typ = "JWT" }));
        var body = Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(payload));
        var signature = Sign($"{header}.{body}", options.SigningKey);

        return $"{header}.{body}.{signature}";
    }

    private async Task<string?> GetHoppaUserIdAsync(
        Guid userId,
        Guid companyInstallationId,
        CancellationToken cancellationToken)
    {
        return await dbContext.ProviderMappings
            .AsNoTracking()
            .Where(mapping => mapping.CompanyInstallationId == companyInstallationId &&
                              mapping.InternalEntityType == "user" &&
                              mapping.InternalEntityId == userId &&
                              mapping.Provider == "hoppa" &&
                              mapping.ProviderEntityType == "user")
            .OrderByDescending(mapping => mapping.UpdatedAt)
            .Select(mapping => mapping.ProviderEntityId)
            .FirstOrDefaultAsync(cancellationToken);
    }

    private static object CreateHoppaUserRequest(ApplicationUser user, SignupRequestDto request)
    {
        var (firstName, lastName) = GetFirstAndLastName(request, user.Email);
        var accountType = NormalizeAccountType(request.AccountType);
        return new
        {
            Email = user.Email,
            FirstName = firstName,
            LastName = lastName,
            Phone = string.IsNullOrWhiteSpace(request.Phone) ? null : request.Phone.Trim(),
            ExternalUserId = user.Id.ToString(),
            AccountType = accountType,
            Metadata = new
            {
                source = "hoppa_demo_app",
                localUserId = user.Id
            }
        };
    }

    private async Task<ActionResult<object>> ConnectVerifiedHoppaIdentityAsync(
        JsonElement? verifiedIdentity,
        string password,
        string? expectedNormalizedEmail,
        string source,
        CancellationToken cancellationToken)
    {
        var verifiedEmail = GetJsonValue(verifiedIdentity, "email", "Email")?.Trim();
        var normalizedEmail = verifiedEmail?.ToUpperInvariant();
        var hoppaUserId = GetJsonValue(verifiedIdentity, "userId", "UserId", "id", "Id");
        var firstName = GetJsonValue(verifiedIdentity, "firstName", "FirstName")?.Trim();
        var lastName = GetJsonValue(verifiedIdentity, "lastName", "LastName")?.Trim();
        var accountType = NormalizeAccountType(GetJsonValue(verifiedIdentity, "accountType", "AccountType"));
        var upstreamStatus = GetJsonValue(verifiedIdentity, "status", "Status") ?? "unknown";

        if (string.IsNullOrWhiteSpace(verifiedEmail) ||
            string.IsNullOrWhiteSpace(normalizedEmail) ||
            string.IsNullOrWhiteSpace(hoppaUserId) ||
            (expectedNormalizedEmail is not null &&
             !string.Equals(normalizedEmail, expectedNormalizedEmail, StringComparison.Ordinal)))
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.account_claim.identity_mismatch",
                "The account provider returned an invalid or mismatched identity.",
                StatusCodes.Status400BadRequest)));
        }

        if (!string.Equals(upstreamStatus, "active", StringComparison.OrdinalIgnoreCase))
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.account_claim.account_inactive",
                "This account is not active. Contact support before connecting it.",
                StatusCodes.Status403Forbidden)));
        }

        var company = await dbContext.CompanyInstallations
            .SingleOrDefaultAsync(installation => installation.Slug == "default", cancellationToken);
        if (company is null)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.default_company_missing",
                "Default company installation is not seeded.",
                StatusCodes.Status500InternalServerError)));
        }

        var providerPhone = await FetchHoppaProfilePhoneAsync(hoppaUserId, cancellationToken);

        var existingByEmail = await dbContext.Users
            .Include(user => user.Identities)
            .SingleOrDefaultAsync(user => user.CompanyInstallationId == company.Id &&
                                          user.EmailNormalized == normalizedEmail,
                cancellationToken);
        var mapping = await dbContext.ProviderMappings
            .SingleOrDefaultAsync(candidate => candidate.CompanyInstallationId == company.Id &&
                                               candidate.Provider == "hoppa" &&
                                               candidate.ProviderEntityType == "user" &&
                                               candidate.ProviderEntityId == hoppaUserId,
                cancellationToken);
        ApplicationUser? mappedUser = null;
        if (mapping is not null)
        {
            mappedUser = await dbContext.Users
                .Include(user => user.Identities)
                .SingleOrDefaultAsync(user => user.Id == mapping.InternalEntityId &&
                                              user.CompanyInstallationId == company.Id,
                    cancellationToken);
        }

        if (mappedUser is not null && existingByEmail is not null && mappedUser.Id != existingByEmail.Id)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.account_claim.mapping_conflict",
                "This account is already linked to another profile.",
                StatusCodes.Status409Conflict)));
        }

        var now = DateTimeOffset.UtcNow;
        var user = mappedUser ?? existingByEmail;
        if (user is null)
        {
            user = new ApplicationUser
            {
                CompanyInstallationId = company.Id,
                Email = verifiedEmail,
                EmailNormalized = normalizedEmail,
                DisplayName = string.Join(' ', new[] { firstName, lastName }
                    .Where(value => !string.IsNullOrWhiteSpace(value))),
                PhoneNumber = providerPhone,
                Status = "active",
                Locale = "en-US",
                MetadataJson = JsonSerializer.Serialize(new { accountType, source }),
                CreatedAt = now,
                UpdatedAt = now
            };
            dbContext.Users.Add(user);
        }
        else
        {
            if (user.Identities.Any(identity => identity.Provider == "local"))
            {
                return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                    "auth.account_claim.account_exists",
                    "This account is already connected. Sign in instead.",
                    StatusCodes.Status409Conflict)));
            }

            user.Email = verifiedEmail;
            user.EmailNormalized = normalizedEmail;
            user.Status = "active";
            user.UpdatedAt = now;
            user.MetadataJson = JsonSerializer.Serialize(new { accountType, source });
            if (string.IsNullOrWhiteSpace(user.DisplayName))
            {
                user.DisplayName = string.Join(' ', new[] { firstName, lastName }
                    .Where(value => !string.IsNullOrWhiteSpace(value)));
            }

            if (string.IsNullOrWhiteSpace(user.PhoneNumber))
            {
                user.PhoneNumber = providerPhone;
            }
        }

        user.Identities.Add(new UserIdentity
        {
            CompanyInstallationId = company.Id,
            Provider = "local",
            Subject = normalizedEmail,
            EmailAtProvider = verifiedEmail,
            IsPrimary = true,
            ClaimsJson = JsonSerializer.Serialize(new { role = "User", accountType, hoppaUserId }),
            PasswordHash = passwordHasher.HashPassword(user, password),
            CreatedAt = now,
            UpdatedAt = now
        });

        if (mapping is null)
        {
            mapping = new ProviderMapping
            {
                CompanyInstallationId = company.Id,
                Provider = "hoppa",
                ProviderEntityType = "user",
                ProviderEntityId = hoppaUserId,
                InternalEntityType = "user",
                InternalEntityId = user.Id,
                CreatedAt = now
            };
            dbContext.ProviderMappings.Add(mapping);
        }
        else
        {
            mapping.InternalEntityId = user.Id;
        }

        mapping.ExternalStatus = upstreamStatus.ToLowerInvariant();
        mapping.LastSyncedAt = now;
        mapping.SyncStateJson = verifiedIdentity?.GetRawText() ?? "{}";
        mapping.UpdatedAt = now;

        try
        {
            await dbContext.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "auth.account_claim.account_exists",
                "This account was connected by another request. Sign in instead.",
                StatusCodes.Status409Conflict)));
        }

        try
        {
            // Hoppa already verified the address (email code or approved QR transfer).
            user.EmailVerifiedAt ??= now;
            await emailNotifier.SendAccountConnectedAsync(
                user,
                source == "hoppa_account_link" ? "a QR account transfer" : "an email verification code",
                now,
                cancellationToken);
            await dbContext.SaveChangesAsync(cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            logger.LogError(exception, "Account connected email could not be queued for user {UserId}.", user.Id);
        }

        return StatusCode(StatusCodes.Status201Created, new
        {
            message = "Existing account connected. Sign in with your new password.",
            userId = user.Id,
            email = user.Email,
            accountType
        });
    }

    /// <summary>
    /// The verified identity carries no phone number, but the card issuer
    /// needs one for every order. It is copied from the Hoppa profile when
    /// the account is connected; failing to read it must not block the
    /// connection, the card order falls back to the profile again.
    /// </summary>
    private async Task<string?> FetchHoppaProfilePhoneAsync(string hoppaUserId, CancellationToken cancellationToken)
    {
        try
        {
            var result = await proxyHoppa.ExecuteAsync(
                new ProxyHoppaRequestCommand<object>
                {
                    Method = HttpMethod.Get,
                    UpstreamPath = $"/api/v2/users/{Uri.EscapeDataString(hoppaUserId)}",
                    FailureCode = "auth.account_claim.profile_failed",
                    FailureMessage = "The account provider could not load the profile."
                },
                cancellationToken);
            if (!result.IsSuccess)
            {
                logger.LogWarning(
                    "Hoppa profile for user {HoppaUserId} could not be loaded while connecting the account: {Code}.",
                    hoppaUserId,
                    result.Error?.Code);
                return null;
            }

            var phone = GetJsonValue(result.Value, "phone", "Phone", "phoneNumber", "PhoneNumber")?.Trim();
            return string.IsNullOrWhiteSpace(phone) ? null : phone;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            logger.LogWarning(exception, "Hoppa profile for user {HoppaUserId} could not be loaded while connecting the account.", hoppaUserId);
            return null;
        }
    }

    private ActionResult<AccountLinkStatusResponseDto> ToAccountLinkStatusResult(
        ApplicationResult<JsonElement?> result)
    {
        if (!result.IsSuccess)
        {
            return ToActionResult<AccountLinkStatusResponseDto>(
                ApplicationResult<AccountLinkStatusResponseDto>.Failure(result.Error!));
        }

        var challengeIdText = GetJsonValue(result.Value, "challengeId", "ChallengeId");
        var expiresAtText = GetJsonValue(result.Value, "expiresAt", "ExpiresAt");
        var status = GetJsonValue(result.Value, "status", "Status")?.Trim().ToUpperInvariant();
        if (!Guid.TryParse(challengeIdText, out var challengeId) ||
            !DateTimeOffset.TryParse(expiresAtText, out var expiresAt) ||
            string.IsNullOrWhiteSpace(status))
        {
            return ToActionResult<AccountLinkStatusResponseDto>(
                ApplicationResult<AccountLinkStatusResponseDto>.Failure(new ApplicationError(
                    "auth.account_link.invalid_response",
                    "The account provider returned an invalid account-transfer response.",
                    StatusCodes.Status502BadGateway)));
        }

        return Ok(new AccountLinkStatusResponseDto
        {
            ChallengeId = challengeId,
            ExpiresAt = expiresAt,
            Status = status
        });
    }

    private static string? ExtractAccountLinkToken(string? qrPayload)
    {
        if (string.IsNullOrWhiteSpace(qrPayload) || qrPayload.Length > 2048 ||
            !Uri.TryCreate(qrPayload.Trim(), UriKind.Absolute, out var uri))
        {
            return null;
        }

        if (!string.Equals(uri.Scheme, "hoppa", StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(uri.Host, "account-transfer", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var query = QueryHelpers.ParseQuery(uri.Query);
        var token = query.TryGetValue("token", out var tokenValues)
            ? tokenValues.FirstOrDefault()?.Trim()
            : null;
        return token is { Length: >= 32 and <= 512 } ? token : null;
    }

    private static string NormalizeAccountType(string? accountType)
    {
        return string.Equals(accountType?.Trim(), "business", StringComparison.OrdinalIgnoreCase)
            ? "business"
            : "personal";
    }

    /// <summary>Error code the app matches when a campaign link no longer attributes.</summary>
    public const string CampaignLinkInactiveCode = "auth.referral.campaign_link_inactive";

    /// <summary>
    /// The platform answers 400 with <c>CAMPAIGN_LINK_INACTIVE</c> for a paused, expired or
    /// archived link; the proxy keeps that body as the error detail.
    /// </summary>
    private static bool IsInactiveCampaignLink(ApplicationError error) =>
        error.StatusCode == StatusCodes.Status400BadRequest &&
        (error.Detail?.Contains("CAMPAIGN_LINK_INACTIVE", StringComparison.OrdinalIgnoreCase) == true ||
         error.Code.Equals("CAMPAIGN_LINK_INACTIVE", StringComparison.OrdinalIgnoreCase));

    private async Task<ApplicationResult<JsonElement?>> CheckReferralAsync(
        string referralCode,
        CancellationToken cancellationToken)
    {
        return await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object?>
            {
                Method = HttpMethod.Get,
                UpstreamPath = "/api/v2/users/check-referral",
                Query = new Dictionary<string, string?>
                {
                    ["referralCode"] = referralCode
                },
                FailureCode = "auth.referral.validation_failed",
                FailureMessage = "We could not validate the referral code."
            },
            cancellationToken);
    }

    private static bool IsValidReferral(JsonElement? response)
    {
        if (response is not { ValueKind: JsonValueKind.Object } value)
        {
            return false;
        }

        foreach (var propertyName in new[] { "Valid", "valid" })
        {
            if (value.TryGetProperty(propertyName, out var property) &&
                property.ValueKind is JsonValueKind.True or JsonValueKind.False)
            {
                return property.GetBoolean();
            }
        }

        return false;
    }

    /// <summary>
    /// The app only needs the validity, the kind, the inviter, the friend's offer and the link's
    /// destination. Field names are normalised to camelCase whatever casing the platform used.
    /// </summary>
    private static object ToReferralCheckPayload(JsonElement? response)
    {
        return new
        {
            valid = IsValidReferral(response),
            kind = GetJsonValue(response, "Kind", "kind"),
            inviterDisplayName = GetJsonValue(response, "InviterDisplayName", "inviterDisplayName"),
            welcomeAmount = GetJsonDecimal(response, "WelcomeAmount", "welcomeAmount"),
            welcomeCurrency = GetJsonValue(response, "WelcomeCurrency", "welcomeCurrency"),
            termsVersion = GetJsonInt32(response, "TermsVersion", "termsVersion"),
            // Addendum A: where a campaign link sends the friend after sign-up (an allowlisted
            // word such as `cards`); null for a personal code or a platform that predates it.
            destination = GetJsonValue(response, "Destination", "destination")?.Trim().ToLowerInvariant()
        };
    }

    private static decimal? GetJsonDecimal(JsonElement? response, params string[] propertyNames)
    {
        if (response is not { ValueKind: JsonValueKind.Object } value)
        {
            return null;
        }

        foreach (var propertyName in propertyNames)
        {
            if (!value.TryGetProperty(propertyName, out var property))
            {
                continue;
            }

            if (property.ValueKind == JsonValueKind.Number && property.TryGetDecimal(out var number))
            {
                return number;
            }

            if (property.ValueKind == JsonValueKind.String &&
                decimal.TryParse(property.GetString(), System.Globalization.NumberStyles.Number, System.Globalization.CultureInfo.InvariantCulture, out var parsed))
            {
                return parsed;
            }
        }

        return null;
    }

    private static int? GetJsonInt32(JsonElement? response, params string[] propertyNames)
    {
        if (response is not { ValueKind: JsonValueKind.Object } value)
        {
            return null;
        }

        foreach (var propertyName in propertyNames)
        {
            if (value.TryGetProperty(propertyName, out var property) &&
                property.ValueKind == JsonValueKind.Number &&
                property.TryGetInt32(out var number))
            {
                return number;
            }
        }

        return null;
    }

    /// <summary>Pulls a human message out of a Hoppa error body; null when there is none.</summary>
    private static string? ExtractProviderMessage(string? detail)
    {
        if (string.IsNullOrWhiteSpace(detail))
        {
            return null;
        }

        var trimmed = detail.Trim();
        if (!trimmed.StartsWith('{'))
        {
            return trimmed.Length <= 200 ? trimmed : null;
        }

        try
        {
            using var document = JsonDocument.Parse(trimmed);
            var message = GetJsonValue(document.RootElement, "message", "Message", "error", "Error", "title", "Title");
            return string.IsNullOrWhiteSpace(message) || message.Length > 200 ? null : message.Trim();
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static ApplicationError? ValidatePassword(string password)
    {
        return PasswordPolicy.Validate(password);
    }

    private static string GetAccountType(ApplicationUser user)
    {
        if (string.IsNullOrWhiteSpace(user.MetadataJson))
        {
            return "personal";
        }

        try
        {
            using var document = JsonDocument.Parse(user.MetadataJson);
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

    private static string GetDisplayName(SignupRequestDto request)
    {
        if (!string.IsNullOrWhiteSpace(request.FirstName) || !string.IsNullOrWhiteSpace(request.LastName))
        {
            return string.Join(' ', new[] { request.FirstName?.Trim(), request.LastName?.Trim() }
                .Where(part => !string.IsNullOrWhiteSpace(part)));
        }

        return string.IsNullOrWhiteSpace(request.FullName)
            ? request.Email?.Trim() ?? "Mobile user"
            : request.FullName.Trim();
    }

    private static (string FirstName, string LastName) GetFirstAndLastName(SignupRequestDto request, string email)
    {
        if (!string.IsNullOrWhiteSpace(request.FirstName) && !string.IsNullOrWhiteSpace(request.LastName))
        {
            return (request.FirstName.Trim(), request.LastName.Trim());
        }

        return SplitName(GetDisplayName(request), email);
    }

    private static (string FirstName, string LastName) SplitName(string? fullName, string email)
    {
        var fallback = email.Split('@', 2)[0];
        var parts = (string.IsNullOrWhiteSpace(fullName) ? fallback : fullName.Trim())
            .Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        return parts.Length switch
        {
            0 => ("User", "Demo"),
            1 => (parts[0], "Demo"),
            _ => (parts[0], string.Join(' ', parts.Skip(1)))
        };
    }

    private static string GetHoppaUserId(JsonElement? response)
    {
        if (response is null)
        {
            return string.Empty;
        }

        foreach (var propertyName in new[] { "Id", "id", "UserId", "userId" })
        {
            if (response.Value.TryGetProperty(propertyName, out var property))
            {
                return property.ValueKind switch
                {
                    JsonValueKind.Number when property.TryGetInt32(out var numericId) => numericId.ToString(),
                    JsonValueKind.String => property.GetString() ?? string.Empty,
                    _ => string.Empty
                };
            }
        }

        return string.Empty;
    }

    private static string? GetJsonValue(JsonElement? response, params string[] propertyNames)
    {
        if (response is not { ValueKind: JsonValueKind.Object } value)
        {
            return null;
        }

        foreach (var propertyName in propertyNames)
        {
            if (!value.TryGetProperty(propertyName, out var property))
            {
                continue;
            }

            return property.ValueKind switch
            {
                JsonValueKind.String => property.GetString(),
                JsonValueKind.Number => property.GetRawText(),
                _ => null
            };
        }

        return null;
    }

    private static ApplicationResult<AuthTokenResponseDto> AuthTokenResponseDtoFailure(
        string code,
        string message,
        int statusCode)
    {
        return ApplicationResult<AuthTokenResponseDto>.Failure(new ApplicationError(code, message, statusCode));
    }

    private static string Sign(string value, string signingKey)
    {
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(signingKey));
        return Base64UrlEncode(hmac.ComputeHash(Encoding.ASCII.GetBytes(value)));
    }

    private static string HashToken(string token)
    {
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
    }

    private static string Base64UrlEncode(byte[] value)
    {
        return Convert.ToBase64String(value)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }
}
