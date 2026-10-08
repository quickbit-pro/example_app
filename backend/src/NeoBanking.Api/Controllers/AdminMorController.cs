using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.DTOs.Mor;
using NeoBanking.Application.Company;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.MorAdmin)]
[Route("api/v1/mor/admin")]
public sealed partial class AdminMorController(IProxyHoppaRequestUseCase proxy, ICompanyContextAccessor companyContextAccessor) : HoppaProxyControllerBase(proxy)
{
    [HttpGet("onboarding-status")]
    public Task<ActionResult<JsonElement?>> OnboardingStatus([FromQuery] bool refresh, CancellationToken ct) => Forward(HttpMethod.Get, "onboarding-status", null, ct, Query(("refresh", refresh)));
    [HttpPost("kyb")]
    public Task<ActionResult<JsonElement?>> SubmitKyb([FromBody] MorKybRequest body, CancellationToken ct) => Forward(HttpMethod.Post, "kyb", body, ct);
    [HttpPost("cardholder")]
    public Task<ActionResult<JsonElement?>> Cardholder([FromBody] MorCardholderRequest body, CancellationToken ct) => Forward(HttpMethod.Post, "cardholder", body, ct);
    [HttpGet("wallets")]
    public Task<ActionResult<JsonElement?>> Wallets(CancellationToken ct) => Forward(HttpMethod.Get, "wallets", null, ct);
    [HttpGet("wallets/quantum-topup/estimate")]
    public Task<ActionResult<JsonElement?>> QuantumEstimate([FromQuery, Range(typeof(decimal), "0.01", "999999999999", ParseLimitsInInvariantCulture = true, ConvertValueInInvariantCulture = true)] decimal amount, CancellationToken ct) => QuantumFunding(HttpMethod.Get, amount, null, ct);
    [HttpPost("wallets/crypto-to-quantum-transfer")]
    public Task<ActionResult<JsonElement?>> QuantumTransfer([FromBody] MorQuantumTransferRequest body, CancellationToken ct) => QuantumFunding(HttpMethod.Post, body.Amount, body, ct);
    [HttpGet("transactions")]
    public Task<ActionResult<JsonElement?>> Transactions([FromQuery, Range(1, 1000000)] int page = 1,
        [FromQuery, Range(1, 100)] int pageSize = 25, [FromQuery] int? userId = null,
        [FromQuery] string? status = null, [FromQuery] string? type = null, CancellationToken ct = default)
        => Forward(HttpMethod.Get, "transactions", null, ct, Query(("page", page), ("pageSize", pageSize), ("userId", userId), ("status", status), ("type", type)));
    [HttpPost("users")]
    public Task<ActionResult<JsonElement?>> CreateUser([FromBody] MorUserRequest body, CancellationToken ct) => Forward(HttpMethod.Post, "users", body, ct);
    [HttpGet("cards")]
    public Task<ActionResult<JsonElement?>> Cards(CancellationToken ct) => Forward(HttpMethod.Get, "cards", null, ct);
    [HttpGet("cards/available")]
    public Task<ActionResult<JsonElement?>> CardProducts(CancellationToken ct) => Forward(HttpMethod.Get, "cards/available", null, ct);
    [HttpGet("cards/analytics")]
    public Task<ActionResult<JsonElement?>> CardAnalytics([FromQuery, Range(7,90)] int days = 30, CancellationToken ct = default) => Forward(HttpMethod.Get, "cards/analytics", null, ct, Query(("days", days)));
    [HttpPost("cards/batch")]
    public Task<ActionResult<JsonElement?>> OrderCards([FromBody] MorOrderRequest body, CancellationToken ct) => Forward(HttpMethod.Post, "cards/batch", body, ct);
    [HttpPost("cards/{cardId:int:min(1)}/assign")]
    public Task<ActionResult<JsonElement?>> AssignCard(int cardId, [FromBody] MorAssignRequest body, CancellationToken ct) => Forward(HttpMethod.Post, $"cards/{cardId}/assign", body, ct);
    [HttpPost("cards/{cardId:int:min(1)}/unassign")]
    public Task<ActionResult<JsonElement?>> UnassignCard(int cardId, CancellationToken ct) => Forward(HttpMethod.Post, $"cards/{cardId}/unassign", null, ct);
    [HttpPost("cards/{cardId:int:min(1)}/cancel")]
    public Task<ActionResult<JsonElement?>> CancelCard(int cardId, CancellationToken ct) => Forward(HttpMethod.Post, $"cards/{cardId}/cancel", null, ct);
    [HttpPost("cards/{cardId:int:min(1)}/load")]
    public Task<ActionResult<JsonElement?>> LoadCard(int cardId, [FromBody] MorFundingRequest body, CancellationToken ct) => Forward(HttpMethod.Post, $"cards/{cardId}/load", body, ct);
    [HttpPost("cards/{cardId:int:min(1)}/unload")]
    public Task<ActionResult<JsonElement?>> UnloadCard(int cardId, [FromBody] MorFundingRequest body, CancellationToken ct) => Forward(HttpMethod.Post, $"cards/{cardId}/unload", body, ct);
    [HttpGet("users/{userId:int:min(1)}/cards")]
    public Task<ActionResult<JsonElement?>> UserCards(int userId, CancellationToken ct) => Forward(HttpMethod.Get, $"users/{userId}/cards", null, ct);
    [HttpGet("cards/{cardId:int:min(1)}/secure-widget")]
    public Task<ActionResult<JsonElement?>> SecureWidget(int cardId, CancellationToken ct)
    {
        Response.Headers.CacheControl = "no-store, no-cache, max-age=0";
        Response.Headers["Referrer-Policy"] = "no-referrer";
        return Forward(HttpMethod.Get, $"cards/{cardId}/secure-widget", null, ct);
    }
    private async Task<ActionResult<JsonElement?>> Forward(HttpMethod method, string resource, object? body,
        CancellationToken ct, IReadOnlyDictionary<string, string?>? query = null)
        => ToActionResult(await SendHoppaAsync(method, $"/api/v2/mor/public/{resource}", body,
            "admin.mor.failed", "Unable to complete the MOR request.", ct, query));
}
