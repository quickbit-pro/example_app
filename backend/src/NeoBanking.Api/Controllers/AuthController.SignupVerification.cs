using System.Net.Mail;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Company;
using NeoBanking.Application.DTOs.Auth;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Api.Controllers;

public sealed partial class AuthController
{
    internal const string SignupEmailPurpose = "signup_email_verification";

    // Only this endpoint creates a placeholder. It has no login identity, provider
    // account or session, and therefore cannot authenticate or perform banking actions.
    [AllowAnonymous]
    [EnableRateLimiting("signup-code")]
    [HttpPost("~/api/v1/mobile/auth/signup/email-code")]
    public async Task<ActionResult<object>> RequestSignupEmailCode(
        [FromBody] SignupEmailCodeRequestDto request, CancellationToken cancellationToken)
    {
        var email = request.Email?.Trim();
        if (string.IsNullOrWhiteSpace(email) || email.Length > 320 ||
            !MailAddress.TryCreate(email, out var address) || address.Address != email)
            return BadRequest(new { code = "auth.signup.email_required", message = "Enter a valid email address." });

        var registration = await (registrationPolicy ?? new CompanyRegistrationPolicy(proxyHoppa, companyOptions)).GetAsync(cancellationToken);
        if (!registration.Available || !registration.AllowsSelfRegistration)
            return StatusCode(registration.Available ? 403 : 503, new { code = "auth.signup.registration_unavailable", message = "Registration is not currently available." });

        var company = await dbContext.CompanyInstallations.SingleOrDefaultAsync(x => x.Slug == "default", cancellationToken);
        if (company is null) return StatusCode(503, new { code = "auth.signup.registration_unavailable", message = "Registration is not currently available." });
        var normalized = email.ToUpperInvariant();
        await using var transaction = dbContext.Database.IsRelational()
            ? await dbContext.Database.BeginTransactionAsync(cancellationToken) : null;
        var user = await dbContext.Users.SingleOrDefaultAsync(x => x.CompanyInstallationId == company.Id && x.EmailNormalized == normalized, cancellationToken);
        if (user is not null && dbContext.Database.IsNpgsql())
            user = await dbContext.Users.FromSqlInterpolated($"SELECT * FROM neobanking.users WHERE \"Id\" = {user.Id} FOR UPDATE")
                .SingleAsync(cancellationToken);

        // Existing accounts and unavailable addresses get the same response. Never
        // overwrite an existing identity or let this flow unlock a blocked account.
        if (user is not null && (user.Status != "pending_signup" || user.LockedAt is not null ||
            await dbContext.UserIdentities.AnyAsync(x => x.UserId == user.Id, cancellationToken) ||
            await dbContext.ProviderMappings.AnyAsync(x => x.InternalEntityType == "user" && x.InternalEntityId == user.Id, cancellationToken)))
            return SignupCodeAccepted();

        var now = DateTimeOffset.UtcNow;
        if (user is null)
        {
            user = new ApplicationUser { CompanyInstallationId = company.Id, Email = email, EmailNormalized = normalized,
                Status = "pending_signup", CreatedAt = now, UpdatedAt = now };
            dbContext.Users.Add(user);
        }
        else if (await dbContext.UserVerificationCodes.CountAsync(x => x.UserId == user.Id && x.Purpose == SignupEmailPurpose &&
                     x.CreatedAt > now.AddHours(-1), cancellationToken) >= 3)
            return SignupCodeAccepted();

        try
        {
            await emailNotifier.SendSignupEmailVerificationAsync(user, SignupEmailPurpose, cancellationToken);
            await dbContext.SaveChangesAsync(cancellationToken);
            if (transaction is not null) await transaction.CommitAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            // A concurrent request may have inserted this email. It receives the
            // same accepted response; only the winning transaction queues a code.
            dbContext.ChangeTracker.Clear();
        }
        return SignupCodeAccepted();
    }

    private ActionResult<object> SignupCodeAccepted() => Accepted(new
    {
        message = "If this address can register, a confirmation code has been sent.",
        expiresInMinutes = 10,
        retryAfterSeconds = 60
    });

    private ActionResult<object> SignupEmailCodeRequired() => BadRequest(new
    {
        code = "auth.signup.email_verification_required",
        message = "Enter the valid confirmation code sent to your email before creating an account."
    });
}
