using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Application.Common;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

/// <summary>
/// Mobile-safe façade for Hoppa's public BoomFi exchange API. The Hoppa user ID
/// always comes from the authenticated token and cannot be selected by a client.
/// </summary>
[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/exchange")]
public sealed class MobileExchangeController : ApiControllerBase
{
    private const string UpstreamRoot = "/api/v2/crypto-virtual-accounts";
    private readonly IProxyHoppaRequestUseCase _proxyHoppa;
    private readonly CompanyFeatureOptions _features;

    public MobileExchangeController(
        IProxyHoppaRequestUseCase proxyHoppa,
        IOptions<CompanyOptions> companyOptions)
    {
        _proxyHoppa = proxyHoppa;
        _features = companyOptions.Value.Features;
    }

    [HttpGet("overview")]
    public Task<ActionResult<JsonElement?>> GetOverview(CancellationToken cancellationToken) =>
        GetAsync("trading-overview", cancellationToken);

    [HttpGet("transfers")]
    public Task<ActionResult<JsonElement?>> GetTransfers(CancellationToken cancellationToken) =>
        GetAsync("transfers", cancellationToken);

    [HttpGet("transfers/{transferId:int}")]
    public Task<ActionResult<JsonElement?>> GetTransfer(int transferId, CancellationToken cancellationToken) =>
        GetAsync($"transfers/{transferId}", cancellationToken);

    [HttpPost("account")]
    public Task<ActionResult<JsonElement?>> OpenAccount([FromBody] JsonElement request, CancellationToken cancellationToken) =>
        PostAsync(string.Empty, request, false, cancellationToken);

    [HttpPost("payin-address")]
    public Task<ActionResult<JsonElement?>> CreatePayInAddress([FromBody] JsonElement request, CancellationToken cancellationToken) =>
        PostAsync("payin-address", request, false, cancellationToken);

    [HttpPost("ramp-quote")]
    public Task<ActionResult<JsonElement?>> GetRampQuote([FromBody] JsonElement request, CancellationToken cancellationToken) =>
        PostAsync("ramp-quote", request, false, cancellationToken);

    [HttpPost("quote")]
    public Task<ActionResult<JsonElement?>> GetExchangeQuote([FromBody] JsonElement request, CancellationToken cancellationToken) =>
        PostAsync("exchange/quote", request, false, cancellationToken);

    [HttpPost("quote/accept")]
    public Task<ActionResult<JsonElement?>> AcceptExchangeQuote([FromBody] JsonElement request, CancellationToken cancellationToken) =>
        PostAsync("exchange/accept", request, true, cancellationToken);

    [HttpPost("interlace-to-equals/quote")]
    public Task<ActionResult<JsonElement?>> GetInterlaceToEqualsQuote([FromBody] JsonElement request, CancellationToken cancellationToken) =>
        PostAsync("interlace-to-equals/quote", request, false, cancellationToken);

    [HttpPost("interlace-to-equals/initiate")]
    public Task<ActionResult<JsonElement?>> InitiateInterlaceToEquals([FromBody] JsonElement request, CancellationToken cancellationToken) =>
        PostAsync("interlace-to-equals/initiate", request, true, cancellationToken);

    [HttpPost("interlace-to-equals/confirm")]
    public Task<ActionResult<JsonElement?>> ConfirmInterlaceToEquals([FromBody] JsonElement request, CancellationToken cancellationToken) =>
        PostAsync("interlace-to-equals/confirm", request, true, cancellationToken);

    [HttpPost("equals-to-interlace")]
    public Task<ActionResult<JsonElement?>> CreateEqualsToInterlace([FromBody] JsonElement request, CancellationToken cancellationToken) =>
        PostAsync("equals-to-interlace", request, true, cancellationToken);

    [HttpPost("equals-to-wallet/initiate")]
    public Task<ActionResult<JsonElement?>> InitiateEqualsToWallet([FromBody] JsonElement request, CancellationToken cancellationToken) =>
        PostAsync("equals-to-wallet/initiate", request, true, cancellationToken);

    [HttpPost("equals-to-wallet/confirm")]
    public Task<ActionResult<JsonElement?>> ConfirmEqualsToWallet([FromBody] JsonElement request, CancellationToken cancellationToken) =>
        PostAsync("equals-to-wallet/confirm", request, true, cancellationToken);

    [HttpPost("transfers/{transferId:int}/decision")]
    public Task<ActionResult<JsonElement?>> DecideTransfer(
        int transferId,
        [FromBody] JsonElement request,
        CancellationToken cancellationToken) =>
        PostAsync($"transfers/{transferId}/decision", request, true, cancellationToken);

    private async Task<ActionResult<JsonElement?>> GetAsync(
        string relativePath,
        CancellationToken cancellationToken)
    {
        var precondition = CheckAccess(requireOutflows: false, out var userId);
        if (precondition is not null) return precondition;

        var result = await _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object?>
            {
                Method = HttpMethod.Get,
                UpstreamPath = BuildPath(relativePath),
                Query = Query(("userId", userId)),
                FailureCode = "mobile.exchange.upstream_failed",
                FailureMessage = "We could not process the Exchange request."
            },
            cancellationToken);

        return ToActionResult(result);
    }

    private async Task<ActionResult<JsonElement?>> PostAsync(
        string relativePath,
        JsonElement request,
        bool requireOutflows,
        CancellationToken cancellationToken)
    {
        var precondition = CheckAccess(requireOutflows, out var userId);
        if (precondition is not null) return precondition;

        var result = await _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object>
            {
                Method = HttpMethod.Post,
                UpstreamPath = BuildPath(relativePath),
                Request = WithUserId(request, userId),
                FailureCode = "mobile.exchange.upstream_failed",
                FailureMessage = "We could not process the Exchange request."
            },
            cancellationToken);

        return ToActionResult(result);
    }

    private ActionResult<JsonElement?>? CheckAccess(bool requireOutflows, out string userId)
    {
        userId = string.Empty;
        if (!_features.BoomFiExchangeEnabled)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.exchange.disabled",
                "Exchange is not enabled for this installation.",
                StatusCodes.Status403Forbidden)));
        }

        if (requireOutflows && !_features.WalletOutflowsEnabled)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.exchange.outflows_disabled",
                "Money movement is not enabled for this installation.",
                StatusCodes.Status403Forbidden)));
        }

        return TryGetCurrentUserId(out userId) ? null : MissingIdentity<JsonElement?>();
    }

    private static string BuildPath(string relativePath) =>
        string.IsNullOrWhiteSpace(relativePath)
            ? UpstreamRoot
            : $"{UpstreamRoot}/{relativePath}";
}
