using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;

namespace NeoBanking.Api.Controllers;

[AllowAnonymous]
[Route("api/v1/mobile/config")]
public sealed class MobileConfigurationController(IOptions<CompanyOptions> options) : ApiControllerBase
{
    [HttpGet]
    public ActionResult<object> Get()
    {
        var company = options.Value;
        var referralMode = NormalizeReferralMode(company.Features.ReferralRegistrationMode);

        return Ok(new
        {
            company = new
            {
                name = company.Name,
                brandName = company.BrandName,
                company.Branding.LogoUrl,
                company.Branding.PrimaryColor,
                company.Branding.SupportEmail,
                company.Branding.TermsUrl,
                company.Branding.PrivacyUrl,
                eSignUrl = company.Branding.ESignUrl,
                eCommunicationNoticeUrl = company.Branding.ECommunicationNoticeUrl,
                generalTermsUrl = company.Branding.GeneralTermsUrl,
                generalTermsUsUrl = company.Branding.GeneralTermsUsUrl,
                additionalAcknowledgementsUrl = company.Branding.AdditionalAcknowledgementsUrl,
                equalsGeneralTermsUrl = company.Branding.EqualsGeneralTermsUrl,
                company.Branding.EqualsRegulatoryDisclaimerEu,
                company.Branding.EqualsRegulatoryDisclaimerUk,
                company.Branding.EqualsRegulatoryRegionDefault
            },
            features = new
            {
                referralsEnabled = company.Features.ReferralsEnabled,
                referralRegistrationMode = company.Features.ReferralsEnabled ? referralMode : "disabled",
                vouchersEnabled = company.Features.VouchersEnabled,
                existingAccountClaimEnabled = company.Features.ExistingAccountClaimEnabled,
                boomFiExchangeEnabled = company.Features.BoomFiExchangeEnabled,
                walletOutflowsEnabled = company.Features.WalletOutflowsEnabled,
                equalsMoneyEnabled = company.Features.EqualsMoneyEnabled,
                businessOnboardingEnabled = company.Features.BusinessOnboardingEnabled
            }
        });
    }

    private static string NormalizeReferralMode(string? value)
    {
        return string.Equals(value?.Trim(), "required", StringComparison.OrdinalIgnoreCase)
            ? "required"
            : "optional";
    }
}
