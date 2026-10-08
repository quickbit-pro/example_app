using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.DTOs.Mor;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

// Parent provisioning is a separate backend administration capability. It is not
// a page or role in the merchant/cardholder portal, and retains existing admin auth.
[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/mor/companies")]
public sealed class AdminMorCompaniesController(IProxyHoppaRequestUseCase proxy) : HoppaProxyControllerBase(proxy)
{
    [HttpGet]
    public Task<ActionResult<JsonElement?>> Companies(CancellationToken ct) => Forward(HttpMethod.Get,"companies",null,ct);
    [HttpGet("merchant-tiers")]
    public Task<ActionResult<JsonElement?>> MerchantTiers(CancellationToken ct) => Forward(HttpMethod.Get,"companies/merchant-tiers",null,ct);
    [HttpPost]
    public Task<ActionResult<JsonElement?>> CreateCompany([FromBody] MorCompanyRequest body,CancellationToken ct) => Forward(HttpMethod.Post,"companies",body,ct);
    private async Task<ActionResult<JsonElement?>> Forward(HttpMethod method,string path,object? body,CancellationToken ct) => ToActionResult(await SendHoppaAsync(method,
        $"/api/v2/mor/public/{path}",body,"admin.mor.companies.failed","Unable to complete the company request.",ct));
}
