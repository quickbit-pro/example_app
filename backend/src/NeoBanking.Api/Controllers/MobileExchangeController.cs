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

    [HttpGet("verification")]
    public Task<ActionResult<JsonElement?>> Verification(CancellationToken ct) => GetAsync("verification", ct);
    [HttpGet("verification/application")]
    public Task<ActionResult<JsonElement?>> Application(CancellationToken ct) => GetAsync("verification/application", ct);
    [HttpGet("settlement-accounts")]
    public Task<ActionResult<JsonElement?>> SettlementAccounts(CancellationToken ct) => GetAsync("verification/settlement-accounts", ct);
    [HttpPost("verification/session")]
    public Task<ActionResult<JsonElement?>> VerificationSession([FromBody] JsonElement request, CancellationToken ct) =>
        PostAsync("verification/session", request, false, ct);
    [HttpPost("verification/application")]
    public Task<ActionResult<JsonElement?>> SubmitApplication([FromBody] JsonElement request, CancellationToken ct) =>
        PostAsync("verification/application", request, false, ct);
    [HttpPost("verification/tin")]
    public Task<ActionResult<JsonElement?>> SubmitTin([FromBody] JsonElement request, CancellationToken ct) =>
        PostAsync("verification/tin", request, false, ct);
    [HttpPost("verification/edd")]
    public Task<ActionResult<JsonElement?>> SubmitEdd([FromBody] JsonElement request, CancellationToken ct) =>
        PostAsync("verification/edd", request, false, ct);
    [HttpPost("payout-address")]
    public Task<ActionResult<JsonElement?>> CryptoPayout([FromBody] JsonElement request, CancellationToken ct) =>
        PostAsync("payout-address", request, true, ct);
    [HttpPost("payout-fiat")]
    public Task<ActionResult<JsonElement?>> FiatPayout([FromBody] JsonElement request, CancellationToken ct) =>
        PostAsync("payout-fiat", request, true, ct);
    [HttpPost("equals-to-interlace/fund")]
    public Task<ActionResult<JsonElement?>> FundExchange([FromBody] JsonElement request, CancellationToken ct) =>
        PostAsync("equals-to-interlace/fund", request, true, ct);
    [HttpPost("bank-address-book")]
    public Task<ActionResult<JsonElement?>> RegisterBank([FromBody] JsonElement request, CancellationToken ct) =>
        PostAsync("bank-address-book", request, false, ct);
    [HttpPost("crypto-address-book")]
    public Task<ActionResult<JsonElement?>> RegisterCrypto([FromBody] JsonElement request, CancellationToken ct) =>
        PostAsync("crypto-address-book", request, false, ct);
    [HttpGet("external-accounts")]
    public Task<ActionResult<JsonElement?>> Destinations(CancellationToken ct) => GetAsync("external-accounts", ct);
    [HttpDelete("external-accounts/{accountId:long}")]
    public async Task<ActionResult<JsonElement?>> DeleteDestination(long accountId, CancellationToken ct)
    {
        var precondition = CheckAccess(true, out var userId);
        if (precondition is not null) return precondition;
        var result = await _proxyHoppa.ExecuteAsync(new ProxyHoppaRequestCommand<object?>
        {
            Method = HttpMethod.Delete, UpstreamPath = BuildPath($"external-accounts/{accountId}"),
            Query = Query(("userId", userId)), SuppressPayloadLogging = true,
            FailureCode = "mobile.exchange.upstream_failed", FailureMessage = "Could not remove the destination."
        }, ct);
        return ExchangeResult(result);
    }

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
                SuppressPayloadLogging = true,
                FailureCode = "mobile.exchange.upstream_failed",
                FailureMessage = "We could not process the Exchange request."
            },
            cancellationToken);

        return ExchangeResult(result);
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
                Query = Query(("userId", userId)),
                SuppressPayloadLogging = true,
                Request = ExchangePayload(request, userId),
                FailureCode = "mobile.exchange.upstream_failed",
                FailureMessage = "We could not process the Exchange request."
            },
            cancellationToken);

        return ExchangeResult(result);
    }

    // Hoppa returns actionable validation/conflict messages as JSON. Keep them
    // visible instead of replacing them with the proxy's generic failure title.
    private ActionResult<JsonElement?> ExchangeResult(ApplicationResult<JsonElement?> result)
    {
        var error = result.Error;
        if (error is null) return ToActionResult(result);
        string message = error.Message;
        if (error.StatusCode is 400 or 409 or 422 && error.Detail is { Length: <= 8192 })
        {
            try
            {
                using var document = JsonDocument.Parse(error.Detail);
                if (document.RootElement.ValueKind == JsonValueKind.Object &&
                    document.RootElement.TryGetProperty("message", out var value) && value.ValueKind == JsonValueKind.String)
                {
                    var text = value.GetString()?.Trim();
                    if (text is { Length: > 0 and <= 220 } &&
                        !text.Any(char.IsControl) && !text.Contains('{') && !text.Contains('[') &&
                        !text.Contains("http", StringComparison.OrdinalIgnoreCase) &&
                        !text.Contains("token", StringComparison.OrdinalIgnoreCase) &&
                        !text.Contains("secret", StringComparison.OrdinalIgnoreCase) &&
                        !text.Contains("api-key", StringComparison.OrdinalIgnoreCase))
                        message = text;
                }
            }
            catch (JsonException) { /* Non-JSON errors retain the safe generic title. */ }
        }
        // Never forward opaque provider bodies or credentials to the mobile app.
        return ToActionResult(ApplicationResult<JsonElement?>.Failure(
            new ApplicationError(error.Code, message, error.StatusCode)));
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

        return TryGetCurrentUserId(out userId) && int.TryParse(userId, out var numericId) && numericId > 0
            ? null : MissingIdentity<JsonElement?>();
    }

    // Preserve questionnaire dictionary keys and snake_case provider fields.
    // Identity always comes from the authenticated mobile token.
    private static object ExchangePayload(JsonElement request, string userId)
    {
        var payload = new Dictionary<string, object?>();
        if (request.ValueKind == JsonValueKind.Object)
            foreach (var property in request.EnumerateObject())
                if (!string.Equals(property.Name, "userId", StringComparison.OrdinalIgnoreCase))
                    payload[property.Name] = property.Value.Clone();
        payload["userId"] = int.Parse(userId, System.Globalization.CultureInfo.InvariantCulture);
        return payload;
    }

    private static string BuildPath(string relativePath) =>
        string.IsNullOrWhiteSpace(relativePath)
            ? UpstreamRoot
            : $"{UpstreamRoot}/{relativePath}";
}
