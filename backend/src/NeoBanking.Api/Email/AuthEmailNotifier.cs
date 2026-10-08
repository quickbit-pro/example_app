using Microsoft.Extensions.Options;
using NeoBanking.Application.Email;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Email;
using NeoBanking.Infrastructure.Security;

namespace NeoBanking.Api.Email;

/// <summary>
/// Issues verification codes and queues the matching customer emails. Nothing
/// is persisted until the caller saves the DbContext.
/// </summary>
public sealed class AuthEmailNotifier(
    EmailOutbox outbox,
    UserVerificationCodeService verificationCodes,
    IOptions<EmailOptions> emailOptions)
{
    public int VerificationCodeMinutes => Math.Clamp(emailOptions.Value.VerificationCodeMinutes, 1, 24 * 60);

    public int PasswordResetCodeMinutes => Math.Clamp(emailOptions.Value.PasswordResetCodeMinutes, 1, 24 * 60);

    public int ResendCooldownSeconds => Math.Max(0, emailOptions.Value.ResendCooldownSeconds);

    private TimeSpan Cooldown => TimeSpan.FromSeconds(Math.Max(0, emailOptions.Value.ResendCooldownSeconds));

    /// <summary>Returns false when the resend cooldown suppressed a new code.</summary>
    public async Task<bool> SendEmailVerificationAsync(ApplicationUser user, CancellationToken cancellationToken)
    {
        var issued = await verificationCodes.IssueAsync(
            user,
            VerificationPurposes.EmailVerification,
            TimeSpan.FromMinutes(VerificationCodeMinutes),
            Cooldown,
            cancellationToken);
        if (issued is null)
        {
            return false;
        }

        await outbox.EnqueueAsync(
            new EmailRequest(
                user.CompanyInstallationId,
                user.Id,
                user.Email,
                user.DisplayName,
                EmailTemplateCatalog.EmailVerification,
                new Dictionary<string, string>
                {
                    ["code"] = issued.Code,
                    ["expiresMinutes"] = VerificationCodeMinutes.ToString()
                },
                EmailOutbox.SerializeMetadata(new { purpose = VerificationPurposes.EmailVerification })),
            cancellationToken);

        return true;
    }

    public async Task<bool> SendPasswordResetAsync(ApplicationUser user, CancellationToken cancellationToken)
    {
        var issued = await verificationCodes.IssueAsync(
            user,
            VerificationPurposes.PasswordReset,
            TimeSpan.FromMinutes(PasswordResetCodeMinutes),
            Cooldown,
            cancellationToken);
        if (issued is null)
        {
            return false;
        }

        var message = await outbox.EnqueueAsync(
            new EmailRequest(
                user.CompanyInstallationId,
                user.Id,
                user.Email,
                user.DisplayName,
                EmailTemplateCatalog.PasswordReset,
                new Dictionary<string, string>
                {
                    ["code"] = issued.Code,
                    ["expiresMinutes"] = PasswordResetCodeMinutes.ToString()
                },
                EmailOutbox.SerializeMetadata(new { purpose = VerificationPurposes.PasswordReset, verificationCodeId = issued.Id, expiresAt = issued.ExpiresAt })),
            cancellationToken);

        if (message is null)
            throw new InvalidOperationException("Password recovery email could not be queued. Check the installation's email template configuration.");
        return true;
    }

    public Task SendAccountConnectedAsync(ApplicationUser user, string method, DateTimeOffset connectedAt, CancellationToken cancellationToken)
    {
        return outbox.EnqueueAsync(
            new EmailRequest(
                user.CompanyInstallationId,
                user.Id,
                user.Email,
                user.DisplayName,
                EmailTemplateCatalog.AccountConnected,
                new Dictionary<string, string>
                {
                    ["connectedAt"] = connectedAt.ToUniversalTime().ToString("d MMM yyyy, HH:mm 'UTC'", System.Globalization.CultureInfo.InvariantCulture),
                    ["method"] = method
                },
                EmailOutbox.SerializeMetadata(new { purpose = "account_connected" })),
            cancellationToken);
    }
}
