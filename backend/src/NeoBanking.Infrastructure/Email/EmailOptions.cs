#nullable enable

namespace NeoBanking.Infrastructure.Email;

public sealed class EmailOptions
{
    public const string SectionName = "Email";

    /// <summary>"sendgrid", "log" (write to application log) or "disabled".</summary>
    public string Provider { get; init; } = "log";

    public string FromEmail { get; init; } = string.Empty;

    public string FromName { get; init; } = string.Empty;

    public string? ReplyToEmail { get; init; }

    public int MaxAttempts { get; init; } = 5;

    public int VerificationCodeMinutes { get; init; } = 15;

    public int PasswordResetCodeMinutes { get; init; } = 15;

    /// <summary>Minimum seconds between two codes for the same user and purpose.</summary>
    public int ResendCooldownSeconds { get; init; } = 60;

    /// <summary>
    /// When true, customers whose email is not confirmed cannot sign in. Admin
    /// accounts are exempt. Existing users are backfilled as verified by the
    /// migration that introduced the flag.
    /// </summary>
    public bool RequireVerifiedEmailForLogin { get; init; }

    /// <summary>
    /// When true, sign-up rejects addresses at throwaway mailbox providers
    /// (mailinator and the like), using the list bundled with the API.
    /// </summary>
    public bool BlockDisposableSignupDomains { get; init; } = true;

    /// <summary>Comma-separated domains rejected at sign-up in addition to the bundled list.</summary>
    public string BlockedSignupDomains { get; init; } = string.Empty;

    /// <summary>
    /// Comma-separated domains that may sign up even though they are on the list,
    /// for a legitimate provider that was listed by mistake. Normally empty.
    /// </summary>
    public string AllowedSignupDomains { get; init; } = string.Empty;

    public SendGridOptions SendGrid { get; init; } = new();

    public bool IsSendGrid => string.Equals(Provider?.Trim(), "sendgrid", StringComparison.OrdinalIgnoreCase);

    public bool IsLog => string.Equals(Provider?.Trim(), "log", StringComparison.OrdinalIgnoreCase);
}

public sealed class SendGridOptions
{
    public string? ApiKey { get; init; }

    /// <summary>Optional EU data-residency host, e.g. https://api.eu.sendgrid.com.</summary>
    public string? Host { get; init; }

    public bool SandboxMode { get; init; }
}
