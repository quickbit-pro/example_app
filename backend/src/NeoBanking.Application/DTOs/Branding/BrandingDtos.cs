namespace NeoBanking.Application.DTOs.Branding;

public sealed class CompanyBrandingDto
{
    public string? CompanyName { get; init; }

    public string? LogoUrl { get; init; }

    public string? PrimaryColor { get; init; }

    public string? SupportEmail { get; init; }

    public string? TermsUrl { get; init; }

    public string? PrivacyUrl { get; init; }
}

public sealed class UpdateCompanyBrandingRequestDto
{
    public string? CompanyName { get; init; }

    public string? LogoUrl { get; init; }

    public string? PrimaryColor { get; init; }

    public string? SupportEmail { get; init; }

    public string? TermsUrl { get; init; }

    public string? PrivacyUrl { get; init; }
}
