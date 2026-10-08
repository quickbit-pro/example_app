namespace NeoBanking.Application.Company;

public sealed record BrandingContext(
    string? LogoUrl,
    string? PrimaryColor,
    string? SupportEmail,
    string? TermsUrl,
    string? PrivacyUrl);
