using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Email;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Auth;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using NeoBanking.Infrastructure.Security;

namespace NeoBanking.Api.Controllers;

/// <summary>
/// Email-code based account recovery and email confirmation. Every "request a
/// code" endpoint answers 202 regardless of whether the address exists so the
/// API cannot be used to enumerate accounts.
/// </summary>
[AllowAnonymous]
[Route("api/v1/mobile/auth")]
public sealed class AuthRecoveryController(
    NeoBankingDbContext dbContext,
    PasswordHasher<ApplicationUser> passwordHasher,
    UserVerificationCodeService verificationCodes,
    LoginAttemptTracker loginAttempts,
    AuthEmailNotifier notifier,
    ILogger<AuthRecoveryController> logger) : ApiControllerBase
{
    private const string PasswordResetSentMessage =
        "Request received. If this email is registered, check your inbox for a password reset code.";

    private const string VerificationSentMessage =
        "If an account exists for this email, a confirmation code has been sent.";

    [HttpPost("password/forgot")]
    public async Task<ActionResult<VerificationCodeIssuedResponseDto>> ForgotPassword(
        [FromBody] ForgotPasswordRequestDto request,
        CancellationToken cancellationToken)
    {
        var normalizedEmail = NormalizeEmail(request.Email);
        if (normalizedEmail is null)
        {
            return EmailRequired<VerificationCodeIssuedResponseDto>();
        }

        var user = await FindLocalUserAsync(normalizedEmail, cancellationToken);
        if (user is not null)
        {
            try
            {
                await notifier.SendPasswordResetAsync(user, cancellationToken);
                await dbContext.SaveChangesAsync(cancellationToken);
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                // Issuance retires the previous code before rendering the email.
                // Do not leave those unsaved changes available to a later save
                // in this request when queuing or persistence fails.
                dbContext.ChangeTracker.Clear();
                logger.LogError(exception, "Password reset email could not be queued for user {UserId}.", user.Id);
            }
        }

        return Accepted(new VerificationCodeIssuedResponseDto
        {
            Message = PasswordResetSentMessage,
            ExpiresInMinutes = notifier.PasswordResetCodeMinutes,
            RetryAfterSeconds = notifier.ResendCooldownSeconds,
            RequestId = HttpContext.TraceIdentifier
        });
    }

    [HttpPost("password/reset")]
    public async Task<ActionResult<object>> ResetPassword(
        [FromBody] ResetPasswordRequestDto request,
        CancellationToken cancellationToken)
    {
        var normalizedEmail = NormalizeEmail(request.Email);
        if (normalizedEmail is null || string.IsNullOrWhiteSpace(request.Code) || string.IsNullOrWhiteSpace(request.NewPassword))
        {
            return Failure<object>("auth.password_reset.required_fields", "Email, code, and new password are required.", StatusCodes.Status400BadRequest);
        }

        if (!UserVerificationCodeService.LooksLikeCode(request.Code.Trim()))
        {
            return Failure<object>("auth.password_reset.invalid_code", "Enter the six-digit code from the email.", StatusCodes.Status400BadRequest);
        }

        var passwordError = PasswordPolicy.Validate(request.NewPassword);
        if (passwordError is not null)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(passwordError));
        }

        var user = await FindLocalUserAsync(normalizedEmail, cancellationToken);
        var identity = user?.Identities.SingleOrDefault(candidate => candidate.Provider == "local");
        if (user is null || identity is null)
        {
            return InvalidCode<object>("auth.password_reset.invalid_code");
        }

        var outcome = await verificationCodes.VerifyAsync(user.Id, VerificationPurposes.PasswordReset, request.Code, cancellationToken);
        if (outcome != VerificationCodeOutcome.Valid)
        {
            await dbContext.SaveChangesAsync(cancellationToken);
            return CodeFailure<object>("auth.password_reset", outcome);
        }

        var now = DateTimeOffset.UtcNow;
        identity.PasswordHash = passwordHasher.HashPassword(user, request.NewPassword);
        identity.UpdatedAt = now;
        user.EmailVerifiedAt ??= now;
        user.UpdatedAt = now;

        var sessions = await dbContext.RefreshSessions
            .Where(session => session.UserId == user.Id && session.RevokedAt == null)
            .ToListAsync(cancellationToken);
        foreach (var session in sessions)
        {
            session.RevokedAt = now;
            session.RevocationReason = "password_reset";
            session.UpdatedAt = now;
        }

        dbContext.AuditLogEntries.Add(new AuditLogEntry
        {
            CompanyInstallationId = user.CompanyInstallationId,
            ActorUserId = user.Id,
            Action = "auth.password_reset",
            EntityType = "user",
            EntityId = user.Id,
            TraceId = HttpContext.TraceIdentifier,
            IpAddress = GetClientIpAddress(),
            UserAgent = Request.Headers.UserAgent.ToString(),
            OccurredAt = now,
            MetadataJson = $"{{\"revokedSessions\":{sessions.Count}}}"
        });

        await dbContext.SaveChangesAsync(cancellationToken);

        // Only verified, persisted recovery clears failures from the old password.
        loginAttempts.Reset(normalizedEmail);

        return Ok(new { message = "Password updated. Sign in with your new password." });
    }

    [HttpPost("email/resend")]
    public async Task<ActionResult<VerificationCodeIssuedResponseDto>> ResendVerification(
        [FromBody] ResendVerificationRequestDto request,
        CancellationToken cancellationToken)
    {
        var normalizedEmail = NormalizeEmail(request.Email);
        if (normalizedEmail is null)
        {
            return EmailRequired<VerificationCodeIssuedResponseDto>();
        }

        var user = await FindLocalUserAsync(normalizedEmail, cancellationToken);
        if (user is not null && user.EmailVerifiedAt is null)
        {
            try
            {
                await notifier.SendEmailVerificationAsync(user, cancellationToken);
                await dbContext.SaveChangesAsync(cancellationToken);
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                logger.LogError(exception, "Verification email could not be queued for user {UserId}.", user.Id);
            }
        }

        return Accepted(new VerificationCodeIssuedResponseDto
        {
            Message = VerificationSentMessage,
            ExpiresInMinutes = notifier.VerificationCodeMinutes
        });
    }

    [HttpPost("email/verify")]
    public async Task<ActionResult<object>> VerifyEmail(
        [FromBody] VerifyEmailRequestDto request,
        CancellationToken cancellationToken)
    {
        var normalizedEmail = NormalizeEmail(request.Email);
        if (normalizedEmail is null || string.IsNullOrWhiteSpace(request.Code))
        {
            return Failure<object>("auth.email_verification.required_fields", "Email and code are required.", StatusCodes.Status400BadRequest);
        }

        if (!UserVerificationCodeService.LooksLikeCode(request.Code.Trim()))
        {
            return Failure<object>("auth.email_verification.invalid_code", "Enter the six-digit code from the email.", StatusCodes.Status400BadRequest);
        }

        var user = await FindLocalUserAsync(normalizedEmail, cancellationToken);
        if (user is null)
        {
            return InvalidCode<object>("auth.email_verification.invalid_code");
        }

        if (user.EmailVerifiedAt is not null)
        {
            return Ok(new { message = "Email address is already confirmed.", emailVerified = true });
        }

        var outcome = await verificationCodes.VerifyAsync(user.Id, VerificationPurposes.EmailVerification, request.Code, cancellationToken);
        if (outcome != VerificationCodeOutcome.Valid)
        {
            await dbContext.SaveChangesAsync(cancellationToken);
            return CodeFailure<object>("auth.email_verification", outcome);
        }

        var now = DateTimeOffset.UtcNow;
        user.EmailVerifiedAt = now;
        user.UpdatedAt = now;
        dbContext.AuditLogEntries.Add(new AuditLogEntry
        {
            CompanyInstallationId = user.CompanyInstallationId,
            ActorUserId = user.Id,
            Action = "auth.email_verified",
            EntityType = "user",
            EntityId = user.Id,
            TraceId = HttpContext.TraceIdentifier,
            IpAddress = GetClientIpAddress(),
            UserAgent = Request.Headers.UserAgent.ToString(),
            OccurredAt = now
        });
        await dbContext.SaveChangesAsync(cancellationToken);

        return Ok(new { message = "Email address confirmed.", emailVerified = true });
    }

    private Task<ApplicationUser?> FindLocalUserAsync(string normalizedEmail, CancellationToken cancellationToken)
    {
        return dbContext.Users
            .Include(user => user.Identities)
            .Where(user => user.EmailNormalized == normalizedEmail &&
                           user.Identities.Any(identity => identity.Provider == "local"))
            .OrderBy(user => user.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);
    }

    private static string? NormalizeEmail(string? email)
    {
        var trimmed = email?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) || !trimmed.Contains('@') ? null : trimmed.ToUpperInvariant();
    }

    private ActionResult<T> EmailRequired<T>()
    {
        return Failure<T>("auth.email_required", "Email is required.", StatusCodes.Status400BadRequest);
    }

    private ActionResult<T> InvalidCode<T>(string code)
    {
        return Failure<T>(code, "The code is invalid or has expired.", StatusCodes.Status400BadRequest);
    }

    private ActionResult<T> CodeFailure<T>(string prefix, VerificationCodeOutcome outcome)
    {
        return outcome switch
        {
            VerificationCodeOutcome.Locked => Failure<T>(
                $"{prefix}.too_many_attempts",
                "Too many incorrect attempts. Request a new code.",
                StatusCodes.Status429TooManyRequests),
            VerificationCodeOutcome.Expired => Failure<T>(
                $"{prefix}.code_expired",
                "The code has expired. Request a new code.",
                StatusCodes.Status400BadRequest),
            _ => InvalidCode<T>($"{prefix}.invalid_code")
        };
    }

    private ActionResult<T> Failure<T>(string code, string message, int statusCode)
    {
        return ToActionResult<T>(ApplicationResult<T>.Failure(new ApplicationError(code, message, statusCode)));
    }
}
