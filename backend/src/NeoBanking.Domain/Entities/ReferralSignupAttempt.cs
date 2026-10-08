namespace NeoBanking.Domain.Entities;

/// <summary>Durable evidence created before upstream account creation. Contains no password or invitation token.</summary>
public sealed class ReferralSignupAttempt : CompanyScopedEntity
{
    public string? EmailNormalized { get; set; }
    public Guid? LocalUserId { get; set; }
    public string State { get; set; } = "QUOTED";
    public string? ProviderUserId { get; set; }
    public Guid? QuoteId { get; set; }
    public string ReferralCode { get; set; } = "";
    public string Source { get; set; } = "MANUAL_CODE";
    public string QuoteJson { get; set; } = "{}";
    public DateTimeOffset? ConsentReceivedAt { get; set; }
    public string? FailureReason { get; set; }
}

public sealed class ReferralAttributionIntent : CompanyScopedEntity
{
    public string Kind { get; set; } = "ATTRIBUTION";
    public Guid SignupAttemptId { get; set; }
    public Guid UserId { get; set; }
    public string ProviderUserId { get; set; } = "";
    public string State { get; set; } = "PENDING";
    public string PayloadJson { get; set; } = "{}";
    public string? ResultJson { get; set; }
    public string? Reason { get; set; }
    public int Attempts { get; set; }
    public DateTimeOffset DueAt { get; set; } = DateTimeOffset.UtcNow;
    public Guid? LeaseToken { get; set; }
    public DateTimeOffset? LeaseUntil { get; set; }
}
