namespace NeoBanking.Application.Company;

public interface ICompanyContext
{
    string InstallationId { get; }

    string CompanyName { get; }

    string BrandName { get; }

    BrandingContext Branding { get; }
}
