#nullable enable

namespace NeoBanking.Infrastructure.Persistence;

internal static class DefaultSeedData
{
    public static readonly Guid CompanyInstallationId = new("019de30e-f84b-7fb1-8cef-4ddc4aba335f");

    public const string CompanySlug = "default";
    public const string CompanyLegalName = "NeoBanking Default Company";
    public const string CompanyDisplayName = "Default";
    public const string CompanyStatus = "active";
    public const string CompanyCountryCode = "US";
    public const string CompanyDefaultCurrency = "USD";
}
