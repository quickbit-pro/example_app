namespace NeoBanking.Api.Admin;

/// <summary>
/// Read model for the admin customer support view
/// (<c>GET api/v1/admin/customers/{userId}/support</c>). Everything here is safe to
/// show to a support agent: no hashes, tokens, secrets or raw request/response bodies.
/// </summary>
public sealed record CustomerSupportResponse(
    DateTimeOffset GeneratedAt,
    CustomerSupportAccount Account,
    CustomerSupportActivity Activity30d,
    CustomerSupportSessions Sessions,
    IReadOnlyList<CustomerSupportDevice> Devices,
    CustomerSupportTickets Tickets,
    IReadOnlyList<CustomerSupportNotification> Notifications,
    IReadOnlyList<CustomerSupportPeerTransfer> PeerTransfers,
    IReadOnlyList<CustomerSupportVerification> VerificationHistory,
    IReadOnlyList<CustomerSupportOnboardingApplication> OnboardingApplications,
    IReadOnlyList<CustomerSupportAuditEntry> AuditTrail,
    CustomerSupportApiCalls ApiCalls);

public sealed record CustomerSupportAccount(
    string DisplayName,
    string Email,
    DateTimeOffset? EmailVerifiedAt,
    string? Phone,
    string Status,
    string Locale,
    string? TimeZone,
    DateTimeOffset CreatedAt,
    DateTimeOffset? LastLoginAt,
    DateTimeOffset? PasswordChangedAt,
    bool TwoFactorEnabled,
    DateTimeOffset? TwoFactorEnabledAt,
    CustomerSupportLock? Lock,
    IReadOnlyList<CustomerSupportSignInMethod> SignInMethods);

public sealed record CustomerSupportLock(
    DateTimeOffset LockedAt,
    string? LockReason,
    DateTimeOffset UnlockAvailableAt,
    bool CanUnlockNow);

public sealed record CustomerSupportSignInMethod(
    string Provider,
    string? EmailAtProvider,
    bool IsPrimary,
    DateTimeOffset? LastAuthenticatedAt);

public sealed record CustomerSupportActivity(
    int CompletedTransactionCount,
    IReadOnlyList<CustomerSupportCurrencyAmount> Inflow,
    IReadOnlyList<CustomerSupportCurrencyAmount> Outflow,
    DateTimeOffset? LastTransactionAt,
    DateTimeOffset? LastActivityAt);

public sealed record CustomerSupportCurrencyAmount(string Currency, decimal Amount);

public sealed record CustomerSupportSessions(
    int ActiveCount,
    IReadOnlyList<CustomerSupportSession> Items);

public sealed record CustomerSupportSession(
    Guid Id,
    string? DeviceName,
    string? IpAddress,
    string? UserAgent,
    DateTimeOffset CreatedAt,
    DateTimeOffset? LastUsedAt,
    DateTimeOffset ExpiresAt,
    DateTimeOffset? RevokedAt,
    string? RevocationReason);

public sealed record CustomerSupportDevice(
    Guid Id,
    string Platform,
    string? AppVersion,
    string? Locale,
    bool IsEnabled,
    DateTimeOffset LastSeenAt);

public sealed record CustomerSupportTickets(
    int TotalCount,
    int AwaitingSupportCount,
    IReadOnlyList<CustomerSupportTicket> Items);

public sealed record CustomerSupportTicket(
    Guid Id,
    string Subject,
    string Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    int MessageCount,
    DateTimeOffset? LastMessageAt,
    bool LastMessageFromAdmin);

/// <summary>One outbound message; <paramref name="Kind"/> is <c>push</c> or <c>email</c>.</summary>
public sealed record CustomerSupportNotification(
    Guid Id,
    string Kind,
    string Title,
    string Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset? SentAt,
    DateTimeOffset? ReadAt,
    string? ErrorMessage,
    int AttemptCount,
    string? EventType,
    string? TemplateKey);

/// <summary><paramref name="Direction"/> is <c>sent</c> or <c>received</c> from the customer's point of view.</summary>
public sealed record CustomerSupportPeerTransfer(
    Guid Id,
    string Direction,
    string CounterpartyName,
    decimal Amount,
    string Currency,
    string Status,
    string? Note,
    string? ErrorCode,
    string? ErrorMessage,
    string ExternalReferenceId,
    DateTimeOffset CreatedAt,
    DateTimeOffset? CompletedAt);

/// <summary><paramref name="Type"/> is <c>kyc</c> or <c>kyb</c>; <paramref name="Level"/> is only set for KYC, <paramref name="BusinessName"/> only for KYB.</summary>
public sealed record CustomerSupportVerification(
    Guid Id,
    string Type,
    string Provider,
    string? ProviderReference,
    string Status,
    string? Level,
    string CountryCode,
    DateTimeOffset StartedAt,
    DateTimeOffset? SubmittedAt,
    DateTimeOffset? ReviewedAt,
    DateTimeOffset? ExpiresAt,
    string? BusinessName);

public sealed record CustomerSupportOnboardingApplication(
    Guid Id,
    string Kind,
    string Status,
    string CurrentStep,
    int WorkflowVersion,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    DateTimeOffset? SubmittedAt,
    DateTimeOffset? CompletedAt);

public sealed record CustomerSupportAuditEntry(
    Guid Id,
    string Action,
    string EntityType,
    Guid? EntityId,
    DateTimeOffset OccurredAt,
    string? IpAddress,
    string? UserAgent);

public sealed record CustomerSupportApiCalls(
    int FailedLast24h,
    int FailedLast7d,
    IReadOnlyList<CustomerSupportApiCallFailure> RecentFailures);

public sealed record CustomerSupportApiCallFailure(
    Guid Id,
    DateTimeOffset OccurredAt,
    string AppMethod,
    string AppPath,
    int? AppStatusCode,
    string HoppaMethod,
    string HoppaEndpoint,
    int? HoppaStatusCode,
    long HoppaDurationMs,
    string? FailureCode,
    string? FailureMessage,
    string? TraceId);
