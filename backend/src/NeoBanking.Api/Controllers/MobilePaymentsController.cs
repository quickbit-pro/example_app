using System.Net.Http;
using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.DTOs.Payments;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/payments")]
public sealed class MobilePaymentsController : ApiControllerBase
{
    private readonly IProxyHoppaRequestUseCase _proxyHoppa;

    public MobilePaymentsController(IProxyHoppaRequestUseCase proxyHoppa)
    {
        _proxyHoppa = proxyHoppa;
    }

    [HttpGet]
    public async Task<ActionResult<JsonElement?>> ListPayments(
        [FromQuery] string? status,
        [FromQuery] int? limit,
        [FromQuery] string? cursor,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "payments/requests",
            null,
            "mobile.payments.list.failed",
            "We could not list payments.",
            cancellationToken,
            Query(("userId", userId), ("status", status), ("pageSize", limit), ("cursor", cursor))));
    }

    [HttpPost]
    [HttpPost("create")]
    public async Task<ActionResult<JsonElement?>> CreatePayment(
        [FromBody] CreatePaymentRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync(
            userId,
            HttpMethod.Post,
            "payments/create",
            CreatePaymentUpstreamRequest(request, userId),
            "mobile.payments.create.failed",
            "We could not create payment.",
            cancellationToken));
    }

    [HttpGet("mandates")]
    public async Task<ActionResult<JsonElement?>> ListMandates(
        [FromQuery] int? pageNumber,
        [FromQuery] int? pageSize,
        [FromQuery] string? status,
        [FromQuery] string? currency,
        [FromQuery] DateOnly? dateFrom,
        [FromQuery] DateOnly? dateTo,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "payments/mandates",
            null,
            "mobile.payments.mandates.list.failed",
            "We could not list payment mandates.",
            cancellationToken,
            Query(
                ("userId", userId),
                ("pageNumber", pageNumber),
                ("pageSize", pageSize),
                ("status", status),
                ("currency", currency),
                ("dateFrom", dateFrom),
                ("dateTo", dateTo))));
    }

    [HttpPost("mandates")]
    public async Task<ActionResult<JsonElement?>> CreateMandate(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync(
            userId,
            HttpMethod.Post,
            "payments/mandates",
            WithUserId(request, userId),
            "mobile.payments.mandates.create.failed",
            "We could not create payment mandate.",
            cancellationToken));
    }

    [HttpGet("mandates/{mandateId}")]
    public async Task<ActionResult<JsonElement?>> GetMandate(string mandateId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"payments/mandates/{Segment(mandateId)}",
            null,
            "mobile.payments.mandates.get.failed",
            "We could not load payment mandate.",
            cancellationToken));
    }

    [HttpPut("mandates/{mandateId}/revoke")]
    public async Task<ActionResult<JsonElement?>> RevokeMandate(
        string mandateId,
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync(
            userId,
            HttpMethod.Put,
            $"payments/mandates/{Segment(mandateId)}/revoke",
            request,
            "mobile.payments.mandates.revoke.failed",
            "We could not revoke payment mandate.",
            cancellationToken));
    }

    [HttpGet("requests")]
    public async Task<ActionResult<JsonElement?>> ListPaymentRequests(
        [FromQuery] int? pageNumber,
        [FromQuery] int? pageSize,
        [FromQuery] string? status,
        [FromQuery] string? currency,
        [FromQuery] DateOnly? dateFrom,
        [FromQuery] DateOnly? dateTo,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "payments/requests",
            null,
            "mobile.payments.requests.list.failed",
            "We could not list payment requests.",
            cancellationToken,
            Query(
                ("userId", userId),
                ("pageNumber", pageNumber),
                ("pageSize", pageSize),
                ("status", status),
                ("currency", currency),
                ("dateFrom", dateFrom),
                ("dateTo", dateTo))));
    }

    [HttpPost("requests")]
    public async Task<ActionResult<JsonElement?>> CreatePaymentRequest(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync(
            userId,
            HttpMethod.Post,
            "payments/requests",
            WithUserId(request, userId),
            "mobile.payments.requests.create.failed",
            "We could not create payment request.",
            cancellationToken));
    }

    [HttpGet("requests/{requestId}")]
    public async Task<ActionResult<JsonElement?>> GetPaymentRequest(string requestId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"payments/requests/{Segment(requestId)}",
            null,
            "mobile.payments.requests.get.failed",
            "We could not load payment request.",
            cancellationToken));
    }

    [HttpPut("requests/{requestId}/cancel")]
    public async Task<ActionResult<JsonElement?>> CancelPaymentRequest(
        string requestId,
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync(
            userId,
            HttpMethod.Put,
            $"payments/requests/{Segment(requestId)}/cancel",
            request,
            "mobile.payments.requests.cancel.failed",
            "We could not cancel payment request.",
            cancellationToken));
    }

    [HttpPost("payouts")]
    public async Task<ActionResult<JsonElement?>> CreatePayout(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync(
            userId,
            HttpMethod.Post,
            "payments/payouts",
            WithUserId(request, userId),
            "mobile.payments.payouts.create.failed",
            "We could not create payout.",
            cancellationToken));
    }

    [HttpPost("withdrawals")]
    public async Task<ActionResult<JsonElement?>> CreateWithdrawal(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync(
            userId,
            HttpMethod.Post,
            "payments/withdrawals",
            WithUserId(request, userId),
            "mobile.payments.withdrawals.create.failed",
            "We could not create withdrawal.",
            cancellationToken));
    }

    [HttpPost("withdrawals/fee")]
    public async Task<ActionResult<JsonElement?>> EstimateWithdrawalFee(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync(
            userId,
            HttpMethod.Post,
            "payments/withdrawals/fee",
            request,
            "mobile.payments.withdrawals.fee.failed",
            "We could not estimate withdrawal fee.",
            cancellationToken));
    }

    [HttpGet("{paymentId}")]
    public async Task<ActionResult<JsonElement?>> GetPayment(string paymentId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"payments/requests/{Segment(paymentId)}",
            null,
            "mobile.payments.get.failed",
            "We could not load payment.",
            cancellationToken));
    }

    [HttpPost("{paymentId}/cancel")]
    public async Task<ActionResult<JsonElement?>> CancelPayment(
        string paymentId,
        [FromBody] CancelPaymentRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendPaymentRequestAsync(
            userId,
            HttpMethod.Put,
            $"payments/requests/{Segment(paymentId)}/cancel",
            request,
            "mobile.payments.cancel.failed",
            "We could not cancel payment.",
            cancellationToken));
    }

    private Task<NeoBanking.Application.Common.ApplicationResult<JsonElement?>> SendPaymentRequestAsync<TRequest>(
        string userId,
        HttpMethod method,
        string relativePath,
        TRequest? request,
        string failureCode,
        string failureMessage,
        CancellationToken cancellationToken,
        IReadOnlyDictionary<string, string?>? query = null)
    {
        return _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<TRequest>
            {
                Method = method,
                UpstreamPath = $"/api/v2/{relativePath}",
                Query = query ?? new Dictionary<string, string?>(),
                Request = request,
                FailureCode = failureCode,
                FailureMessage = failureMessage
            },
            cancellationToken);
    }

    private static object CreatePaymentUpstreamRequest(CreatePaymentRequestDto request, string userId)
    {
        return new
        {
            UserId = int.TryParse(userId, out var numericUserId) ? numericUserId : (object)userId,
            Amount = request.Amount.ToString(CultureInfo.InvariantCulture),
            request.Currency,
            Description = request.Reference,
            MerchantReferenceId = request.DestinationReference
        };
    }
}
