using System.Net.Http;
using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.Common;
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
            request,
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
            request,
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
    public Task<ActionResult<JsonElement?>> CreatePayout(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out _))
        {
            return Task.FromResult(MissingIdentity<JsonElement?>());
        }

        // This legacy integrator operation uses company funds. Customer payouts
        // must go through the banking flow with its balance and approval checks.
        return Task.FromResult(ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
            "mobile.payments.payouts.unavailable",
            "Payouts are unavailable here. Use the bank transfer flow to make this payment.",
            403))));
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
            request,
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

    private async Task<ApplicationResult<JsonElement?>> SendPaymentRequestAsync<TRequest>(
        string userId,
        HttpMethod method,
        string relativePath,
        TRequest? request,
        string failureCode,
        string failureMessage,
        CancellationToken cancellationToken,
        IReadOnlyDictionary<string, string?>? query = null)
    {
        if (!TryPaymentId(userId, out var ownerId))
        {
            return ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "identity.hoppa_user_missing", "A linked customer identity is required.", 401));
        }

        // The provider sees a company API key, so the app must retain the signed-in
        // customer's boundary before forwarding any record lookup or mutation.
        var scopedQuery = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
        if (query is not null)
        {
            foreach (var item in query) scopedQuery[item.Key] = item.Value;
        }
        scopedQuery["userId"] = ownerId;

        string? resourceId = null;
        var segments = relativePath.Split('/');
        if (segments.Length >= 3 && segments[1] is "mandates" or "requests")
        {
            if (!TryPaymentId(segments[2], out var parsedId)) return ResourceNotFound();
            resourceId = parsedId;
            segments[2] = parsedId;
            relativePath = string.Join('/', segments);
            var owned = await _proxyHoppa.ExecuteAsync(new ProxyHoppaRequestCommand<object?>
            {
                Method = HttpMethod.Get,
                UpstreamPath = $"/api/v2/payments/{segments[1]}/{parsedId}",
                Query = scopedQuery,
                FailureCode = failureCode,
                FailureMessage = failureMessage
            }, cancellationToken);

            if (!owned.IsSuccess)
            {
                return owned.Error!.StatusCode is 403 or 404 ? ResourceNotFound() : owned;
            }
            if (!IsOwnedRecord(owned.Value, ownerId, resourceId)) return ResourceNotFound();
            if (method == HttpMethod.Get) return owned;
        }

        object? upstreamRequest = request;
        var createsCustomerRecord = method == HttpMethod.Post && relativePath is
            "payments/create" or "payments/mandates" or "payments/requests" or
            "payments/withdrawals";
        if (createsCustomerRecord)
        {
            var body = JsonSerializer.SerializeToElement(request);
            if (body.ValueKind != JsonValueKind.Object) return InvalidRequest();
            var fields = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
            foreach (var property in body.EnumerateObject())
            {
                // Remove every casing of userId, including duplicate JSON fields.
                if (property.Name.Equals("userId", StringComparison.OrdinalIgnoreCase)) continue;
                if (!fields.TryAdd(property.Name, property.Value)) return InvalidRequest();
            }
            fields["userId"] = long.TryParse(ownerId, NumberStyles.None, CultureInfo.InvariantCulture, out var numericOwner)
                ? JsonSerializer.SerializeToElement(numericOwner)
                : JsonSerializer.SerializeToElement(ownerId);
            upstreamRequest = fields;
        }

        var result = await _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object?>
            {
                Method = method,
                UpstreamPath = $"/api/v2/{relativePath}",
                Query = scopedQuery,
                Request = upstreamRequest,
                FailureCode = failureCode,
                FailureMessage = failureMessage
            },
            cancellationToken);

        if (!result.IsSuccess) return result;
        // Mutations were authorized before dispatch. Preserve their provider
        // outcome: turning an acknowledgement into a failure can invite a retry
        // after a payment or withdrawal has already been accepted.
        if (method == HttpMethod.Get && relativePath is "payments/mandates" or "payments/requests")
        {
            var collectionName = relativePath == "payments/mandates" ? "mandates" : "paymentRequests";
            if (!TryUniqueProperty(result.Value, collectionName, out var records) ||
                records.ValueKind != JsonValueKind.Array ||
                records.EnumerateArray().Any(record => !IsOwnedRecord(record, ownerId, null)))
            {
                return ResourceNotFound();
            }
        }
        return result;
    }

    private static bool IsOwnedRecord(JsonElement? record, string ownerId, string? resourceId) =>
        TryUniqueProperty(record, "userId", out var owner) && TryJsonId(owner, out var actualOwner) && actualOwner == ownerId &&
        TryUniqueProperty(record, "id", out var id) && TryJsonId(id, out var actualId) &&
        (resourceId is null || actualId == resourceId);

    private static bool TryUniqueProperty(JsonElement? value, string name, out JsonElement property)
    {
        property = default;
        if (value is not { ValueKind: JsonValueKind.Object } element) return false;
        var found = false;
        foreach (var candidate in element.EnumerateObject())
        {
            if (!candidate.Name.Equals(name, StringComparison.OrdinalIgnoreCase)) continue;
            if (found) return false;
            property = candidate.Value;
            found = true;
        }
        return found;
    }

    private static bool TryJsonId(JsonElement value, out string id)
    {
        id = string.Empty;
        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var numericId) && numericId > 0)
        {
            id = numericId.ToString(CultureInfo.InvariantCulture);
            return true;
        }
        return value.ValueKind == JsonValueKind.String && TryPaymentId(value.GetString(), out id);
    }

    private static bool TryPaymentId(string? value, out string id)
    {
        id = string.Empty;
        // Legacy Hoppa uses integer IDs; Cardeo uses UUIDs. Canonicalize each
        // representation without ever treating a UUID as a numeric identity.
        if (long.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var numericId) && numericId > 0)
        {
            id = numericId.ToString(CultureInfo.InvariantCulture);
            return true;
        }
        if (value?.Length == 36 && Guid.TryParseExact(value, "D", out var guidId) && guidId != Guid.Empty)
        {
            id = guidId.ToString("D");
            return true;
        }
        return false;
    }

    private static ApplicationResult<JsonElement?> ResourceNotFound() =>
        ApplicationResult<JsonElement?>.Failure(new ApplicationError(
            "mobile.payments.not_found", "The requested payment record was not found.", 404));

    private static ApplicationResult<JsonElement?> InvalidRequest() =>
        ApplicationResult<JsonElement?>.Failure(new ApplicationError(
            "mobile.payments.invalid_request", "A payment request must contain unambiguous object fields.", 400));

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
