namespace NeoBanking.Api.Company;

public sealed class CompanyOptions
{
    public const string SectionName = "Company";

    public string InstallationId { get; init; } = "local";

    public string Name { get; init; } = "NeoBanking";

    public string BrandName { get; init; } = "NeoBanking";

    public BrandingOptions Branding { get; init; } = new();

    public CompanyFeatureOptions Features { get; init; } = new();
}

public sealed class CompanyFeatureOptions
{
    public bool ReferralsEnabled { get; init; }

    public string ReferralRegistrationMode { get; init; } = "optional";

    public bool VouchersEnabled { get; init; }

    public bool ExistingAccountClaimEnabled { get; init; }

    /// <summary>
    /// Shows the BoomFi-backed Exchange experience. The Hoppa company and the
    /// individual user's BoomFi organisation must also be ready before actions
    /// are enabled.
    /// </summary>
    public bool BoomFiExchangeEnabled { get; init; }

    /// <summary>
    /// Allows operations that move funds out of a provider account. Keep this
    /// disabled until the customer has completed operational sign-off.
    /// </summary>
    public bool WalletOutflowsEnabled { get; init; }

    /// <summary>
    /// Shows EqualsMoney onboarding and account surfaces for this installation.
    /// Provider readiness remains authoritative.
    /// </summary>
    public bool EqualsMoneyEnabled { get; init; } = true;

    /// <summary>
    /// Offers the business account type at signup and exposes the business
    /// (KYB) onboarding endpoints. Disable for personal-only installations.
    /// </summary>
    public bool BusinessOnboardingEnabled { get; init; } = true;
}
