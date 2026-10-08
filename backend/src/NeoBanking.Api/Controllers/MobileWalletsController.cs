using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.DTOs.Banking;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile")]
public sealed class MobileWalletsController : HoppaProxyControllerBase
{
    public MobileWalletsController(IProxyHoppaRequestUseCase proxyHoppa)
        : base(proxyHoppa)
    {
    }

    [HttpPost("interlace-account")]
    public async Task<ActionResult<JsonElement?>> CreateInterlaceAccount(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync<object?>(
            HttpMethod.Post,
            $"/api/v2/users/create-interlace-account/{Segment(userId)}",
            null,
            "mobile.interlace_account.create.failed",
            "We could not create Interlace account.",
            cancellationToken));
    }

    [HttpGet("wallets")]
    public async Task<ActionResult<JsonElement?>> ListWallets(
        [FromQuery] string? id,
        [FromQuery] string? nickname,
        [FromQuery] string? currency,
        [FromQuery] bool? master,
        [FromQuery] string? referenceId,
        [FromQuery] int? limit,
        [FromQuery] int? page,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var wallets = await SendHoppaAsync<object?>(
            HttpMethod.Get,
            $"/api/v2/users/{Segment(userId)}/wallets",
            null,
            "mobile.wallets.list.failed",
            "We could not list wallets.",
            cancellationToken,
            Query(
                ("id", id),
                ("nickname", nickname),
                ("currency", currency),
                ("master", master),
                ("referenceId", referenceId),
                ("limit", limit),
                ("page", page)));

        if (wallets.IsSuccess || wallets.Error!.StatusCode < 500)
        {
            return ToActionResult(wallets);
        }

        // Hoppa's wallet-provider endpoint can be temporarily unavailable even
        // while its authoritative asset balances remain healthy. Returning the
        // assets payload keeps the mobile wallet view usable; the client already
        // understands both wallet and asset response envelopes.
        var assets = await SendHoppaAsync<object?>(
            HttpMethod.Get,
            $"/api/v2/users/{Segment(userId)}/assets",
            null,
            "mobile.wallets.assets_fallback.failed",
            "We could not list wallet assets.",
            cancellationToken);

        return ToActionResult(assets.IsSuccess ? assets : wallets);
    }

    [HttpGet("assets")]
    public async Task<ActionResult<JsonElement?>> ListAssets(
        [FromQuery] string? interlaceAccountId,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync<object?>(
            HttpMethod.Get,
            $"/api/v2/users/{Segment(userId)}/assets",
            null,
            "mobile.assets.list.failed",
            "We could not list assets.",
            cancellationToken,
            Query(("interlaceAccountId", interlaceAccountId))));
    }

    [HttpGet("crypto-addresses")]
    public async Task<ActionResult<JsonElement?>> ListCryptoAddresses(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync<object?>(
            HttpMethod.Get,
            $"/api/v2/users/{Segment(userId)}/crypto-addresses",
            null,
            "mobile.crypto_addresses.list.failed",
            "We could not list crypto deposit addresses.",
            cancellationToken));
    }

    [HttpPost("wallets/top-up")]
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
            "mobile.wallets.topup.failed",
            "We could not top up wallet.",
            cancellationToken,
            Query(("userId", userId))));
    }

    [HttpGet("crypto-transactions")]
    public async Task<ActionResult<JsonElement?>> ListCryptoTransactions(
        [FromQuery] string? id,
        [FromQuery] string? transactionHash,
        [FromQuery] string? referenceId,
        [FromQuery] DateTimeOffset? startTime,
        [FromQuery] DateTimeOffset? endTime,
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
            "/api/v2/transfers/crypto-transactions",
            null,
            "mobile.crypto_transactions.list.failed",
            "We could not list crypto transactions.",
            cancellationToken,
            Query(
                ("userId", userId),
                ("id", id),
                ("transactionHash", transactionHash),
                ("referenceId", referenceId),
                ("startTime", startTime),
                ("endTime", endTime),
                ("limit", limit),
                ("page", page))));
    }
}
