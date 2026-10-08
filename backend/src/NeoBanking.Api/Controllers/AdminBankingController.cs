using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.DTOs.Admin;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/banking")]
public sealed class AdminBankingController : HoppaProxyControllerBase
{
    public AdminBankingController(IProxyHoppaRequestUseCase proxyHoppa)
        : base(proxyHoppa)
    {
    }

    [HttpGet("accounts")]
    public async Task<ActionResult<JsonElement?>> ListAccounts(
        [FromQuery] string? userId,
        [FromQuery] string? status,
        [FromQuery] int? limit,
        [FromQuery] string? cursor,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            "banking/accounts",
            null,
            "admin.banking.accounts.list.failed",
            "Hoppa failed to list bank accounts.",
            cancellationToken,
            Query(("userId", userId), ("status", status), ("limit", limit), ("cursor", cursor))));
    }

    [HttpGet("accounts/{accountId}")]
    public async Task<ActionResult<JsonElement?>> GetAccount(string accountId, CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            $"banking/accounts/{Segment(accountId)}",
            null,
            "admin.banking.accounts.get.failed",
            "Hoppa failed to load bank account.",
            cancellationToken));
    }

    [HttpGet("accounts/{accountId}/balances")]
    public async Task<ActionResult<JsonElement?>> GetBalances(string accountId, CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            $"banking/accounts/{Segment(accountId)}/balances",
            null,
            "admin.banking.balances.failed",
            "Hoppa failed to load bank account balances.",
            cancellationToken));
    }

    [HttpPatch("accounts/{accountId}/status")]
    public async Task<ActionResult<JsonElement?>> UpdateAccountStatus(
        string accountId,
        [FromBody] AdminStatusUpdateRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = accountId;
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "admin.banking.accounts.status.unsupported",
            "Hoppa staging OpenAPI does not expose a bank account status update endpoint.");
    }

    [HttpGet("payees")]
    public async Task<ActionResult<JsonElement?>> ListPayees(
        [FromQuery] string? userId,
        [FromQuery] int? limit,
        [FromQuery] string? cursor,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            "banking/payees",
            null,
            "admin.banking.payees.list.failed",
            "Hoppa failed to list payees.",
            cancellationToken,
            Query(("userId", userId), ("limit", limit), ("cursor", cursor))));
    }

    [HttpGet("transfers")]
    public async Task<ActionResult<JsonElement?>> ListTransfers(
        [FromQuery] string? userId,
        [FromQuery] string? status,
        [FromQuery] int? limit,
        [FromQuery] string? cursor,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            "banking/transfers",
            null,
            "admin.banking.transfers.list.failed",
            "Hoppa failed to list transfers.",
            cancellationToken,
            Query(("userId", userId), ("status", status), ("limit", limit), ("cursor", cursor))));
    }

    [HttpGet("transfers/{transferId}")]
    public async Task<ActionResult<JsonElement?>> GetTransfer(string transferId, CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            $"banking/transfers/{Segment(transferId)}",
            null,
            "admin.banking.transfers.get.failed",
            "Hoppa failed to load transfer.",
            cancellationToken));
    }
}
