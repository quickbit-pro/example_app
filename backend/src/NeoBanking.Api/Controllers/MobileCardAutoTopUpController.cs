using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.Common;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/cards")]
public sealed class MobileCardAutoTopUpController(IProxyHoppaRequestUseCase proxy) : ApiControllerBase
{
    [HttpGet("{cardId:int}/auto-topup")]
    public Task<ActionResult<JsonElement?>> Get(int cardId, CancellationToken ct) =>
        Send(HttpMethod.Get, $"cards/{cardId}/auto-topup", cardId, (object?)null, ct);

    [HttpPost("auto-topup/low-balance")]
    public Task<ActionResult<JsonElement?>> LowBalance(LowBalanceRequest request, CancellationToken ct) =>
        Send(HttpMethod.Post, "cards/auto-topup/low-balance", request.CardId, request, ct,
            !request.Enabled || (request.DisclaimerAccepted && request.Watermark > 0 &&
                request.TargetBalance > request.Watermark && request.MonthlyLimit > 0));

    [HttpPost("auto-topup/failed-tx")]
    public Task<ActionResult<JsonElement?>> FailedTransaction(FailedTransactionRequest request, CancellationToken ct) =>
        Send(HttpMethod.Post, "cards/auto-topup/failed-tx", request.CardId, request, ct,
            !request.Enabled || (request.DisclaimerAccepted && request.MaxAmount > 0 && request.MonthlyLimit > 0));

    [HttpPost("auto-topup/deposit")]
    public Task<ActionResult<JsonElement?>> Deposit(DepositRequest request, CancellationToken ct)
    {
        var settings = request.Settings;
        var valid = settings is { Count: > 0 and <= 2 } && settings.All(s => s is not null &&
            (s.Currency == "USDC" || s.Currency == "USDT") &&
            (!s.Enabled || (s.MaxAmount > 0 && request.DisclaimerAccepted))) &&
            settings.Select(s => s.Currency).Distinct().Count() == settings.Count;
        return Send(HttpMethod.Post, "cards/auto-topup/deposit", request.CardId, request, ct, valid);
    }

    private async Task<ActionResult<JsonElement?>> Send<T>(HttpMethod method, string path, int cardId, T body,
        CancellationToken ct, bool valid = true)
    {
        if (!TryGetCurrentUserId(out var userId) || !int.TryParse(userId, out var numericUser) || numericUser <= 0)
            return MissingIdentity<JsonElement?>();
        if (cardId <= 0 || !valid)
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.cards.auto_topup.invalid", "Check the amounts and accept the automatic top-up authorization before enabling.", 400)));
        // No caller-supplied userId is accepted. Hoppa also verifies company/card ownership.
        return ToActionResult(await proxy.ExecuteAsync(new ProxyHoppaRequestCommand<T> {
            Method = method, UpstreamPath = $"/api/v2/{path}", Request = body,
            Query = new Dictionary<string, string?> { ["userId"] = userId },
            FailureCode = "mobile.cards.auto_topup.failed", FailureMessage = "Unable to update automatic top-up settings."
        }, ct));
    }

    public sealed record LowBalanceRequest(int CardId, bool Enabled, decimal Watermark, decimal TargetBalance, decimal MonthlyLimit, bool DisclaimerAccepted);
    public sealed record FailedTransactionRequest(int CardId, bool Enabled, decimal MaxAmount, decimal MonthlyLimit, bool DisclaimerAccepted);
    public sealed record DepositRequest(int CardId, bool DisclaimerAccepted, List<DepositSetting>? Settings);
    public sealed record DepositSetting(string Currency, bool Enabled, decimal MaxAmount);
}
