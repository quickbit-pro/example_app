using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.DTOs.Admin;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/transactions")]
public sealed class AdminTransactionsController : HoppaProxyControllerBase
{
    public AdminTransactionsController(IProxyHoppaRequestUseCase proxyHoppa)
        : base(proxyHoppa)
    {
    }

    [HttpGet]
    public async Task<ActionResult<JsonElement?>> ListTransactions(
        [FromQuery] string? userId,
        [FromQuery] string? accountId,
        [FromQuery] DateOnly? from,
        [FromQuery] DateOnly? to,
        [FromQuery] int? limit,
        [FromQuery] string? cursor,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            "transactions",
            null,
            "admin.transactions.list.failed",
            "Hoppa failed to list transactions.",
            cancellationToken,
            Query(("userId", userId), ("accountId", accountId), ("from", from), ("to", to), ("limit", limit), ("cursor", cursor))));
    }

    [HttpGet("{transactionId}")]
    public async Task<ActionResult<JsonElement?>> GetTransaction(string transactionId, CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            $"transactions/{Segment(transactionId)}",
            null,
            "admin.transactions.get.failed",
            "Hoppa failed to load transaction.",
            cancellationToken));
    }

    [HttpPost("{transactionId}/adjustments")]
    public async Task<ActionResult<JsonElement?>> CreateAdjustment(
        string transactionId,
        [FromBody] AdminTransactionAdjustmentRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = transactionId;
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "admin.transactions.adjustments.unsupported",
            "Hoppa staging OpenAPI does not expose a transaction adjustment endpoint.");
    }
}
