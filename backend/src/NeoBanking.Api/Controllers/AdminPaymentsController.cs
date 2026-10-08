using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.DTOs.Admin;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/payments")]
public sealed class AdminPaymentsController : HoppaProxyControllerBase
{
    public AdminPaymentsController(IProxyHoppaRequestUseCase proxyHoppa)
        : base(proxyHoppa)
    {
    }

    [HttpGet]
    public async Task<ActionResult<JsonElement?>> ListPayments(
        [FromQuery] string? userId,
        [FromQuery] string? status,
        [FromQuery] int? limit,
        [FromQuery] string? cursor,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            "payments/requests",
            null,
            "admin.payments.list.failed",
            "Hoppa failed to list payments.",
            cancellationToken,
            Query(("userId", userId), ("status", status), ("limit", limit), ("cursor", cursor))));
    }

    [HttpGet("{paymentId}")]
    public async Task<ActionResult<JsonElement?>> GetPayment(string paymentId, CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            $"payments/requests/{Segment(paymentId)}",
            null,
            "admin.payments.get.failed",
            "Hoppa failed to load payment.",
            cancellationToken));
    }

    [HttpPatch("{paymentId}/status")]
    public async Task<ActionResult<JsonElement?>> UpdateStatus(
        string paymentId,
        [FromBody] AdminStatusUpdateRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = paymentId;
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "admin.payments.status.unsupported",
            "Hoppa staging OpenAPI does not expose a generic payment status update endpoint.");
    }
}
