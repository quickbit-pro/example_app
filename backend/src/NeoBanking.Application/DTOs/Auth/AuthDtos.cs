namespace NeoBanking.Application.DTOs.Auth;

public sealed class LoginRequestDto
{
    public string? Email { get; init; }

    public string? Password { get; init; }

    /// <summary>Friendly device label supplied by the client (e.g. "iPhone", "Web browser").</summary>
    public string? DeviceName { get; init; }

    public string? DeviceId { get; init; }
}

public sealed class AuthSessionDto
{
    public Guid Id { get; init; }

    public string DeviceName { get; init; } = string.Empty;

    public string? UserAgent { get; init; }

    public string? IpAddress { get; init; }

    public DateTimeOffset CreatedAt { get; init; }

    public DateTimeOffset? LastUsedAt { get; init; }

    public DateTimeOffset ExpiresAt { get; init; }

    /// <summary>True for the session that issued the access token making this request.</summary>
    public bool IsCurrent { get; init; }
}

public sealed class SignupRequestDto
{
    public string? Email { get; init; }

    public string? Password { get; init; }

    public string? FullName { get; init; }

    public string? FirstName { get; init; }

    public string? LastName { get; init; }

    public string? Phone { get; init; }

    public string? AccountType { get; init; }

    public Guid? InstallationToken { get; init; }
    public Guid? RegistrationAttemptId { get; init; }
    public Guid? ReferralQuoteId { get; init; }
    public string? ReferralTermsHash { get; init; }
    public string? ReferralPolicyHash { get; init; }
    /// <summary>Continue account creation with an explicitly unconfirmed referral when no valid quote is available.</summary>
    public bool ReferralNeedsReview { get; init; }

    public string? ReferralCode { get; init; }

    public string? ReferralSource { get; init; }

    /// <summary>
    /// The new user explicitly accepted that the inviter is credited for their sign-up.
    /// Required for attribution unless the source is an email invitation.
    /// </summary>
    public bool? ReferralAccepted { get; init; }

    /// <summary>The referral program terms version shown to the user when they accepted.</summary>
    public int? ReferralTermsVersion { get; init; }

    /// <summary>Legal agreements accepted at registration (keys, timestamps, document URLs).</summary>
    public Dictionary<string, object?>? LegalAgreements { get; init; }
}

public sealed class AccountClaimChallengeRequestDto
{
    public string? Email { get; init; }
}

public sealed class AccountClaimChallengeResponseDto
{
    public Guid ChallengeId { get; init; }

    public DateTimeOffset ExpiresAt { get; init; }

    public string Message { get; init; } = string.Empty;
}

public sealed class CompleteAccountClaimRequestDto
{
    public string? Email { get; init; }

    public Guid ChallengeId { get; init; }

    public string? Code { get; init; }

    public string? Password { get; init; }
}

public sealed class ScanAccountLinkRequestDto
{
    public string? QrPayload { get; init; }

    public string? DeviceName { get; init; }
}

public sealed class AccountLinkTokenRequestDto
{
    public string? Token { get; init; }
}

public sealed class CompleteAccountLinkRequestDto
{
    public string? Token { get; init; }

    public string? Password { get; init; }
}

public sealed class AccountLinkStatusResponseDto
{
    public Guid ChallengeId { get; init; }

    public string Status { get; init; } = string.Empty;

    public DateTimeOffset ExpiresAt { get; init; }
}

public sealed class RefreshTokenRequestDto
{
    public string? RefreshToken { get; init; }
}

public sealed class AuthTokenResponseDto
{
    public string? AccessToken { get; init; }

    public string? RefreshToken { get; init; }

    public int ExpiresInSeconds { get; init; }

    public IReadOnlyList<string> Roles { get; init; } = [];

    public string? UserName { get; init; }

    public string? Email { get; init; }

    /// <summary>True when the password was accepted but a second factor is still required.</summary>
    public bool RequiresTwoFactor { get; init; }

    /// <summary>Short-lived token to present with the one-time code.</summary>
    public string? ChallengeToken { get; init; }
}

public sealed class TwoFactorLoginRequestDto
{
    public string? ChallengeToken { get; init; }

    public string? Code { get; init; }
}

public sealed class AccountSecurityDto
{
    public bool TwoFactorEnabled { get; init; }

    public DateTimeOffset? TwoFactorEnabledAt { get; init; }

    public int RecoveryCodesRemaining { get; init; }

    public bool DuressPasswordSet { get; init; }

    public DateTimeOffset? PasswordChangedAt { get; init; }
}

public sealed class PasswordConfirmRequestDto
{
    public string? CurrentPassword { get; init; }
}

public sealed class TwoFactorSetupResponseDto
{
    public string Secret { get; init; } = string.Empty;

    public string OtpauthUri { get; init; } = string.Empty;
}

public sealed class TwoFactorCodeRequestDto
{
    public string? Code { get; init; }
}

public sealed class TwoFactorEnableResponseDto
{
    public IReadOnlyList<string> RecoveryCodes { get; init; } = [];
}

public sealed class ChangePasswordRequestDto
{
    public string? CurrentPassword { get; init; }

    public string? NewPassword { get; init; }
}

public sealed class DuressPasswordRequestDto
{
    public string? CurrentPassword { get; init; }

    public string? DuressPassword { get; init; }
}

public sealed class LockedAccountDto
{
    public Guid Id { get; init; }

    public string Email { get; init; } = string.Empty;

    public string? DisplayName { get; init; }

    public DateTimeOffset LockedAt { get; init; }

    public string? LockReason { get; init; }

    public DateTimeOffset UnlockAvailableAt { get; init; }
}

public sealed class ReferralSignupQuoteRequest
{
    public Guid RegistrationAttemptId { get; init; }
    public string ReferralCode { get; init; } = "";
    public string? Source { get; init; }
    public string? InvitationToken { get; init; }
    public string? Locale { get; init; }
}
