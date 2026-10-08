using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.Company;
using NeoBanking.Application.DTOs.Branding;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Route("api/v1/branding")]
public sealed class BrandingController : ApiControllerBase
{
    private readonly ICompanyContextAccessor _companyContextAccessor;
    private readonly IProxyHoppaRequestUseCase _proxyHoppa;

    public BrandingController(
        ICompanyContextAccessor companyContextAccessor,
        IProxyHoppaRequestUseCase proxyHoppa)
    {
        _companyContextAccessor = companyContextAccessor;
        _proxyHoppa = proxyHoppa;
    }

    [AllowAnonymous]
    [HttpGet]
    public ActionResult<CompanyBrandingDto> GetBranding()
    {
        var company = _companyContextAccessor.Current;
        return Ok(new CompanyBrandingDto
        {
            CompanyName = company.BrandName,
            LogoUrl = company.Branding.LogoUrl,
            PrimaryColor = company.Branding.PrimaryColor,
            SupportEmail = company.Branding.SupportEmail,
            TermsUrl = company.Branding.TermsUrl,
            PrivacyUrl = company.Branding.PrivacyUrl
        });
    }

    [Authorize(Policy = AuthorizationPolicyNames.Admin)]
    [HttpPut]
    public ActionResult<JsonElement?> UpdateBranding(
        [FromBody] UpdateCompanyBrandingRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "branding.update.unsupported",
            "Hoppa staging OpenAPI does not expose a branding update endpoint.");
    }
}
