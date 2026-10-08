#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class KycVerification : CompanyScopedEntity
{
    public Guid UserId { get; set; }

    public ApplicationUser? User { get; set; }

    public Guid? OnboardingApplicationId { get; set; }

    public OnboardingApplication? OnboardingApplication { get; set; }

    public string Provider { get; set; } = string.Empty;

    public string? ProviderReference { get; set; }

    public string Status { get; set; } = "pending";

    public string Level { get; set; } = "standard";

    public string CountryCode { get; set; } = "US";

    public DateTimeOffset StartedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? SubmittedAt { get; set; }

    public DateTimeOffset? ReviewedAt { get; set; }

    public DateTimeOffset? ExpiresAt { get; set; }

    public string ApplicantDataJson { get; set; } = "{}";

    public string DocumentChecksJson { get; set; } = "{}";

    public string RiskSignalsJson { get; set; } = "{}";
}
