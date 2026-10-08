using System;

namespace NeoBanking.Application.DTOs.Onboarding;

public sealed class StartOnboardingRequestDto
{
    public string? CountryCode { get; init; }

    public string? ProductCode { get; init; }

    public string? CustomerType { get; init; }
}

public sealed class OnboardingStatusDto
{
    public string? UserId { get; init; }

    public string? Status { get; init; }

    public string[] RequiredActions { get; init; } = Array.Empty<string>();
}

public sealed class UpdateOnboardingStepRequestDto
{
    public string? Step { get; init; }

    public string? Status { get; init; }

    public string? Notes { get; init; }
}

public sealed class StartBusinessOnboardingRequestDto
{
    public string? BusinessName { get; init; }

    public string? RegistrationNumber { get; init; }

    public string? CountryCode { get; init; }

    public string? LegalForm { get; init; }
}

public sealed class UpdateBusinessProfileRequestDto
{
    public string? BusinessName { get; init; }

    public string? TradingName { get; init; }

    public string? IndustryCode { get; init; }

    public string? WebsiteUrl { get; init; }

    public string? RegisteredAddress { get; init; }
}

public sealed class UpsertBeneficialOwnerRequestDto
{
    public string? OwnerId { get; init; }

    public string? FullName { get; init; }

    public DateOnly? DateOfBirth { get; init; }

    public decimal? OwnershipPercentage { get; init; }

    public string? CountryCode { get; init; }
}

public sealed class SubmitBusinessDocumentRequestDto
{
    public string? DocumentType { get; init; }

    public string? FileId { get; init; }

    public string? IssuingCountryCode { get; init; }
}
