#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class KybVerification : CompanyScopedEntity
{
    public Guid? OnboardingApplicationId { get; set; }

    public OnboardingApplication? OnboardingApplication { get; set; }

    public string BusinessName { get; set; } = string.Empty;

    public string? RegistrationNumber { get; set; }

    public string CountryCode { get; set; } = "US";

    public string Provider { get; set; } = string.Empty;

    public string? ProviderReference { get; set; }

    public string Status { get; set; } = "pending";

    public DateTimeOffset? SubmittedAt { get; set; }

    public DateTimeOffset? ReviewedAt { get; set; }

    public DateTimeOffset? ExpiresAt { get; set; }

    public string BusinessProfileJson { get; set; } = "{}";

    public string BeneficialOwnersJson { get; set; } = "[]";

    public string DocumentChecksJson { get; set; } = "{}";

    public string RiskSignalsJson { get; set; } = "{}";
}
