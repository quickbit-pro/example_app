#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class ApplicationUser : CompanyScopedEntity
{
    public string Email { get; set; } = string.Empty;

    public string EmailNormalized { get; set; } = string.Empty;

    public string? PhoneNumber { get; set; }

    public string? Nickname { get; set; }

    public string? DisplayName { get; set; }

    public string Status { get; set; } = "pending";

    public string Locale { get; set; } = "en-US";

    public string? TimeZone { get; set; }

    public DateTimeOffset? LastLoginAt { get; set; }

    public DateTimeOffset? EmailVerifiedAt { get; set; }

    public string RiskProfileJson { get; set; } = "{}";

    public string MetadataJson { get; set; } = "{}";

    // Monotonic onboarding progress, shared by every device on the account.
    public DateTimeOffset? ActivationIntroShownAt { get; set; }
    public DateTimeOffset? FirstDepositObservedAt { get; set; }

    // Account security. The TOTP secret is only used server-side; recovery
    // codes are stored hashed and consumed on use.
    public bool TwoFactorEnabled { get; set; }

    public string? TwoFactorSecret { get; set; }

    public DateTimeOffset? TwoFactorEnabledAt { get; set; }

    public string RecoveryCodesJson { get; set; } = "[]";

    /// <summary>Hash of the duress password; entering it locks the account.</summary>
    public string? DuressPasswordHash { get; set; }

    public DateTimeOffset? LockedAt { get; set; }

    public string? LockReason { get; set; }

    public DateTimeOffset? PasswordChangedAt { get; set; }

    public ICollection<UserIdentity> Identities { get; set; } = new List<UserIdentity>();

    public ICollection<RefreshSession> RefreshSessions { get; set; } = new List<RefreshSession>();

    public AdminProfile? AdminProfile { get; set; }

    public ICollection<KycVerification> KycVerifications { get; set; } = new List<KycVerification>();

    public ICollection<BankingSnapshot> BankingSnapshots { get; set; } = new List<BankingSnapshot>();

    public ICollection<PaymentCard> Cards { get; set; } = new List<PaymentCard>();

    public ICollection<AuditLogEntry> AuditLogs { get; set; } = new List<AuditLogEntry>();

    public ICollection<PushDevice> PushDevices { get; set; } = new List<PushDevice>();

    public ICollection<PushNotification> PushNotifications { get; set; } = new List<PushNotification>();
}
