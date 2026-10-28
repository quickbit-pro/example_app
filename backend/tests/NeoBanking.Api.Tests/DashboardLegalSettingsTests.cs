using Xunit;
using System.Text.Json;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Company;

namespace NeoBanking.Api.Tests;

public sealed class DashboardLegalSettingsTests
{
    private static readonly CompanyOptions Company = new() { DashboardCompanyId = 1, DashboardBrandingDomain = "dashboard.hoppa.global" };

    [Theory]
    [InlineData(2, true, "default", "dashboard.hoppa.global")]
    [InlineData(1, false, "default", "dashboard.hoppa.global")]
    [InlineData(1, true, "alternate", "dashboard.hoppa.global")]
    [InlineData(1, true, "default", "another.example")]
    public void RejectsOtherTenantInactiveOrNonDefault(int id, bool active, string variant, string domain)
    {
        var json = JsonSerializer.SerializeToElement(new { companyId = id, isActive = active, variantName = variant, domain });
        Assert.Throws<InvalidDataException>(() => DashboardLegalSettings.Parse(json, Company));
    }

    [Fact]
    public void MapsDashboardNamesAndVersionChangesInvalidateConsent()
    {
        BrandingOptions Read(string version) => DashboardLegalSettings.Parse(JsonSerializer.SerializeToElement(new {
            companyId = 1, isActive = true, variantName = "default", domain = "dashboard.hoppa.global",
            equalsGeneralTermsUrl = "https://docs.hoppa.global/terms.pdf", equalsTermsVersion = version,
            interlaceGeneralTermsUrl = "https://docs.hoppa.global/non-us.pdf",
            interlaceGeneralTermsUrl2 = "https://docs.hoppa.global/us.pdf", equalsRegulatoryRegionDefault = "UK"
        }), Company);
        var first = Read("1.2");
        Assert.Equal("https://docs.hoppa.global/non-us.pdf", first.GeneralTermsUrl);
        Assert.Equal("https://docs.hoppa.global/us.pdf", first.GeneralTermsUsUrl);
        Assert.Equal("https://equalsmoney.com/privacy", EqualsConsentService.Documents(first).PrivacyUrl);
        Assert.NotEqual(EqualsConsentService.Documents(first).Version, EqualsConsentService.Documents(Read("1.3")).Version);
        Assert.Null(Read("1.2").TermsUrl);
    }
}
