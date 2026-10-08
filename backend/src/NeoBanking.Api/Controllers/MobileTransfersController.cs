using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.DTOs.Banking;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/transfers")]
public sealed class MobileTransfersController : HoppaProxyControllerBase
{
    public MobileTransfersController(IProxyHoppaRequestUseCase proxyHoppa)
        : base(proxyHoppa)
    {
    }

    [HttpGet]
    public async Task<ActionResult<JsonElement?>> ListTransfers(
        [FromQuery] string? status,
        [FromQuery] int? limit,
        [FromQuery] int? page,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync<object?>(
            HttpMethod.Get,
            "/api/v2/transfers",
            null,
            "mobile.transfers.list.failed",
            "We could not list transfers.",
            cancellationToken,
            Query(("userId", userId), ("status", status), ("pageSize", limit), ("pageNumber", page))));
    }

    [HttpGet("{transferId}")]
    public async Task<ActionResult<JsonElement?>> GetTransfer(string transferId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync<object?>(
            HttpMethod.Get,
            $"/api/v2/transfers/{Segment(transferId)}",
            null,
            "mobile.transfers.get.failed",
            "We could not load transfer.",
            cancellationToken,
            Query(("userId", userId))));
    }

    [HttpPost("wallet-topup")]
    public async Task<ActionResult<JsonElement?>> TopUpWallet(
        [FromBody] WalletTopUpRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync(
            HttpMethod.Post,
            "/api/v2/transfers/wallet-topup",
            WalletTopUpUpstreamRequestDto.From(request),
            "mobile.transfers.wallet_topup.failed",
            "We could not top up wallet.",
            cancellationToken,
            Query(("userId", userId))));
    }

    [HttpPost("crypto-to-quantum-transfer")]
    public async Task<ActionResult<JsonElement?>> CreateCryptoToQuantumTransfer(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync(
            HttpMethod.Post,
            "/api/v2/transfers/crypto-to-quantum-transfer",
            request,
            "mobile.transfers.crypto_to_quantum.failed",
            "We could not transfer crypto to Quantum.",
            cancellationToken,
            Query(("userId", userId))));
    }

    [HttpPost("quantum-usd-to-crypto-exchange")]
    public async Task<ActionResult<JsonElement?>> CreateQuantumToCryptoExchange(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync(
            HttpMethod.Post,
            "/api/v2/transfers/quantum-usd-to-crypto-exchange",
            request,
            "mobile.transfers.quantum_to_crypto.failed",
            "We could not exchange Quantum USD to crypto.",
            cancellationToken,
            Query(("userId", userId))));
    }

    [HttpGet("withdrawals/available-balance")]
    public async Task<ActionResult<JsonElement?>> GetWithdrawalAvailableBalance(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync<object?>(
            HttpMethod.Get,
            "/api/v2/transfers/withdrawals/available-balance",
            null,
            "mobile.transfers.withdrawals.available_balance.failed",
            "We could not load withdrawal available balance.",
            cancellationToken,
            Query(("userId", userId))));
    }

    [HttpGet("withdrawals/fee-and-quota")]
    public async Task<ActionResult<JsonElement?>> GetWithdrawalFeeAndQuota(
        [FromQuery] string? chain,
        [FromQuery] string? address,
        [FromQuery] string? currency,
        [FromQuery] string? amount,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync<object?>(
            HttpMethod.Get,
            "/api/v2/transfers/withdrawals/fee-and-quota",
            null,
            "mobile.transfers.withdrawals.fee_and_quota.failed",
            "We could not load withdrawal fee and quota.",
            cancellationToken,
            Query(("userId", userId), ("chain", chain), ("address", address), ("currency", currency), ("amount", amount))));
    }

    [HttpPost("withdrawals/crypto")]
    public async Task<ActionResult<JsonElement?>> CreateCryptoWithdrawal(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync(
            HttpMethod.Post,
            "/api/v2/transfers/withdrawals/crypto",
            WithUserId(request, userId),
            "mobile.transfers.withdrawals.crypto.failed",
            "We could not create crypto withdrawal.",
            cancellationToken));
    }

    [HttpPost("withdrawals/crypto/confirm")]
    public async Task<ActionResult<JsonElement?>> ConfirmCryptoWithdrawal(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync(
            HttpMethod.Post,
            "/api/v2/transfers/withdrawals/crypto/confirm",
            WithUserId(request, userId),
            "mobile.transfers.withdrawals.crypto.confirm.failed",
            "We could not confirm crypto withdrawal.",
            cancellationToken));
    }

    [HttpPost("withdrawals/crypto/resend")]
    public async Task<ActionResult<JsonElement?>> ResendCryptoWithdrawalOtp(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync(
            HttpMethod.Post,
            "/api/v2/transfers/withdrawals/crypto/resend",
            WithUserId(request, userId),
            "mobile.transfers.withdrawals.crypto.resend.failed",
            "We could not resend the crypto withdrawal verification code.",
            cancellationToken));
    }
}
