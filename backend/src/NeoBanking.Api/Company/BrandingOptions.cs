namespace NeoBanking.Api.Company;

public sealed class BrandingOptions
{
    public string? LogoUrl { get; init; }

    public string? PrimaryColor { get; init; }

    public string? SupportEmail { get; init; }

    public string? TermsUrl { get; init; }

    public string? PrivacyUrl { get; init; }

    /// <summary>Legal documents accepted during registration.</summary>
    public string? ESignUrl { get; init; }

    public string? ECommunicationNoticeUrl { get; init; }

    public string? GeneralTermsUrl { get; init; }

    public string? GeneralTermsUsUrl { get; init; }

    public string? AdditionalAcknowledgementsUrl { get; init; }

    public string? EqualsGeneralTermsUrl { get; init; }

    /// <summary>Equals Money disclosure shown to customers in the EU.</summary>
    public string? EqualsRegulatoryDisclaimerEu { get; init; }

    /// <summary>Equals Money disclosure shown to UK and non-EU customers.</summary>
    public string? EqualsRegulatoryDisclaimerUk { get; init; }

    /// <summary>Fallback region when the client locale has no country.</summary>
    public string EqualsRegulatoryRegionDefault { get; init; } = "EU";
}
