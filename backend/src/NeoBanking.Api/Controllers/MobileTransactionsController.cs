using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.DTOs.Banking;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/transactions")]
public sealed class MobileTransactionsController : HoppaProxyControllerBase
{
    public MobileTransactionsController(IProxyHoppaRequestUseCase proxyHoppa)
        : base(proxyHoppa)
    {
    }

    [HttpGet]
    public async Task<ActionResult<JsonElement?>> ListTransactions(
        [FromQuery] string? accountId,
        [FromQuery] int? page,
        [FromQuery] int? pageSize,
        [FromQuery] string? types,
        [FromQuery] string? statuses,
        [FromQuery] DateOnly? from,
        [FromQuery] DateOnly? to,
        [FromQuery] string? search,
        [FromQuery] decimal? minAmount,
        [FromQuery] decimal? maxAmount,
        [FromQuery] string? sources,
        [FromQuery] string? cardIds,
        [FromQuery] string? walletIds,
        [FromQuery] string? sortBy,
        [FromQuery] string? sortOrder,
        [FromQuery] int? limit,
        [FromQuery] string? cursor,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync<object?>(
            HttpMethod.Get,
            "/api/v2/transactions",
            null,
            "mobile.transactions.list.failed",
            "We could not list transactions.",
            cancellationToken,
            Query(
                ("userId", userId),
                ("walletIds", walletIds ?? accountId),
                ("page", page),
                ("pageSize", pageSize ?? limit),
                ("types", types),
                ("statuses", statuses),
                ("startDate", from),
                ("endDate", to),
                ("search", search),
                ("minAmount", minAmount),
                ("maxAmount", maxAmount),
                ("sources", sources),
                ("cardIds", cardIds),
                ("sortBy", sortBy),
                ("sortOrder", sortOrder),
                ("cursor", cursor))));
    }

    [HttpGet("{transactionId}")]
    public async Task<ActionResult<JsonElement?>> GetTransaction(string transactionId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync<object?>(
            HttpMethod.Get,
            $"/api/v2/transactions/{Segment(transactionId)}",
            null,
            "mobile.transactions.get.failed",
            "We could not load transaction.",
            cancellationToken,
            Query(("userId", userId))));
    }

    [HttpGet("export")]
    [HttpPost("export")]
    public async Task<ActionResult<JsonElement?>> ExportTransactions(
        [FromQuery] string? format,
        [FromQuery] string? types,
        [FromQuery] string? statuses,
        [FromQuery] DateOnly? startDate,
        [FromQuery] DateOnly? endDate,
        [FromQuery] string? search,
        [FromQuery] decimal? minAmount,
        [FromQuery] decimal? maxAmount,
        [FromQuery] string? sources,
        [FromQuery] string? cardIds,
        [FromQuery] string? walletIds,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync<object?>(
            HttpMethod.Get,
            "/api/v2/transactions/export",
            null,
            "mobile.transactions.export.failed",
            "We could not export transactions.",
            cancellationToken,
            Query(
                ("userId", userId),
                ("format", format),
                ("types", types),
                ("statuses", statuses),
                ("startDate", startDate),
                ("endDate", endDate),
                ("search", search),
                ("minAmount", minAmount),
                ("maxAmount", maxAmount),
                ("sources", sources),
                ("cardIds", cardIds),
                ("walletIds", walletIds))));
    }

    [HttpGet("stats")]
    public async Task<ActionResult<JsonElement?>> GetTransactionStats(
        [FromQuery] DateOnly? startDate,
        [FromQuery] DateOnly? endDate,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync<object?>(
            HttpMethod.Get,
            "/api/v2/transactions/stats",
            null,
            "mobile.transactions.stats.failed",
            "We could not load transaction stats.",
            cancellationToken,
            Query(("userId", userId), ("startDate", startDate), ("endDate", endDate))));
    }

    [HttpPost("sync")]
    public async Task<ActionResult<JsonElement?>> SyncTransactions(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync<object?>(
            HttpMethod.Post,
            "/api/v2/transactions/sync",
            null,
            "mobile.transactions.sync.failed",
            "We could not sync transactions.",
            cancellationToken,
            Query(("userId", userId))));
    }

    [HttpPost("top-up")]
    public async Task<ActionResult<JsonElement?>> TopUpWallet(
        [FromBody] WalletTopUpRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out _))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync(
            HttpMethod.Post,
            "/api/v2/transactions/top-up",
            request,
            "mobile.transactions.top_up.failed",
            "We could not top up wallet.",
            cancellationToken));
    }
}
