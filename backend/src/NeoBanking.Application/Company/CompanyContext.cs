namespace NeoBanking.Application.Company;

public sealed record CompanyContext(
    string InstallationId,
    string CompanyName,
    string BrandName,
    BrandingContext Branding) : ICompanyContext
{
    public static CompanyContext Empty { get; } = new(
        "local",
        "NeoBanking",
        "NeoBanking",
        new BrandingContext(null, null, null, null, null));
}
