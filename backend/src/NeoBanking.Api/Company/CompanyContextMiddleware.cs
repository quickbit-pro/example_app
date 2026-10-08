using Microsoft.Extensions.Options;
using NeoBanking.Application.Company;

namespace NeoBanking.Api.Company;

public sealed class CompanyContextMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(
        HttpContext context,
        IOptionsSnapshot<CompanyOptions> options,
        ICompanyContextAccessor companyContextAccessor)
    {
        companyContextAccessor.Clear();

        var company = options.Value;
        companyContextAccessor.SetCurrent(new CompanyContext(
            Normalize(company.InstallationId, CompanyOptions.SectionName),
            Normalize(company.Name, "NeoBanking"),
            Normalize(company.BrandName, company.Name),
            new BrandingContext(
                company.Branding.LogoUrl,
                company.Branding.PrimaryColor,
                company.Branding.SupportEmail,
                company.Branding.TermsUrl,
                company.Branding.PrivacyUrl)));

        await next(context);
    }

    private static string Normalize(string? value, string fallback)
    {
        return string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
    }
}
