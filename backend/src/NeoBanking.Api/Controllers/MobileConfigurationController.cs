using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;

namespace NeoBanking.Api.Controllers;

[AllowAnonymous]
[Route("api/v1/mobile/config")]
public sealed class MobileConfigurationController(IOptions<CompanyOptions> options, CompanyRegistrationPolicy registrationPolicy,
    DashboardLegalSettings? legalSettings = null) : ApiControllerBase
{
    [HttpGet]
    public async Task<ActionResult<object>> Get(CancellationToken ct = default)
    {
        Response.Headers.CacheControl = "no-store";
        var company = options.Value;
        var branding = legalSettings is null ? company.Branding : await legalSettings.GetAsync(ct);
        var registration = await registrationPolicy.GetAsync(ct);
        var referralMode = registration.ReferralRequired ? "required" : "optional";

        return Ok(new
        {
            company = new
            {
                name = company.Name,
                legalDocumentsFromDashboard = !string.IsNullOrWhiteSpace(company.DashboardBrandingUrl),
                brandName = company.BrandName,
                branding.LogoUrl,
                branding.PrimaryColor,
                branding.SupportEmail,
                branding.TermsUrl,
                branding.PrivacyUrl,
                eSignUrl = branding.ESignUrl,
                eCommunicationNoticeUrl = branding.ECommunicationNoticeUrl,
                generalTermsUrl = branding.GeneralTermsUrl,
                generalTermsUsUrl = branding.GeneralTermsUsUrl,
                additionalAcknowledgementsUrl = branding.AdditionalAcknowledgementsUrl,
                equalsGeneralTermsUrl = branding.EqualsGeneralTermsUrl,
                branding.EqualsTermsVersion, branding.EqualsTermsEffectiveDate,
                branding.EqualsRegulatoryDisclaimerEu,
                branding.EqualsRegulatoryDisclaimerUk,
                branding.EqualsRegulatoryRegionDefault
            },
            registration = new
            {
                registration.Available,
                registration.AllowsSelfRegistration,
                registration.RequireExternalWallet,
                registration.ReferralRequired,
                referralCodesEnabled = registration.ReferralsEnabled,
                registration.BlockedCountries
            },
            features = new
            {
                referralsEnabled = company.Features.ReferralsEnabled,
                referralRegistrationMode = company.Features.ReferralsEnabled && registration.Available ? referralMode : "disabled",
                vouchersEnabled = company.Features.VouchersEnabled,
                existingAccountClaimEnabled = company.Features.ExistingAccountClaimEnabled,
                boomFiExchangeEnabled = company.Features.BoomFiExchangeEnabled,
                unifiedCddOnboardingEnabled = company.Features.BoomFiExchangeEnabled || company.Features.EqualsMoneyEnabled,
                walletOutflowsEnabled = company.Features.WalletOutflowsEnabled,
                equalsMoneyEnabled = company.Features.EqualsMoneyEnabled,
                businessOnboardingEnabled = company.Features.BusinessOnboardingEnabled
            }
        });
    }

}
