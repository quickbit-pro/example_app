using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Application.Security;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/settings")]
public sealed class AdminSettingsController : ApiControllerBase
{
    private readonly CompanyOptions _companyOptions;

    public AdminSettingsController(IOptions<CompanyOptions> companyOptions)
    {
        _companyOptions = companyOptions.Value;
    }

    [HttpGet]
    public IActionResult GetSettings()
    {
        return Ok(new
        {
            adminMfaRequired = false,
            defaultTier = "Standard",
            kybRequiredForBusiness = true,
            maintenanceMode = false,
            paymentReviewLimit = 25000,
            company = _companyOptions.Name,
            brandName = _companyOptions.BrandName
        });
    }

    [HttpPut]
    public IActionResult UpdateSettings([FromBody] object request)
    {
        return Ok(request);
    }
}
