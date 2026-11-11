using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Payments;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobilePaymentsOwnershipTests
{
    private const int OwnerId = 10466;
    private const string Owned = """{"id":11,"userId":10466,"companyId":1,"amount":"1.00"}""";
    private const string UuidOwner = "a5968eb4-229a-4c8f-8e28-65ae8755fbc2";
    private const string UuidRecord = "503745a3-cd3f-4d48-ac3f-53c99de1707a";
    private const string UuidOther = "bd0ff1bb-b8bf-422b-9177-15d36019fe85";

    [Theory]
    [InlineData("mandate")]
    [InlineData("request")]
    [InlineData("payment")]
    public async Task Detail_DoesNotExposeAnotherCustomersRecord(string route)
    {
        var proxy = new Proxy(Success("""{"id":11,"userId":999,"companyId":1,"description":"private"}"""));
        var response = await Detail(Controller(proxy), route);
        Assert.Equal(404, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.DoesNotContain("private", JsonSerializer.Serialize(Assert.IsType<ObjectResult>(response.Result).Value));
        Assert.Equal(HttpMethod.Get, Assert.Single(proxy.Calls).Method);
        Assert.Equal("10466", proxy.Calls[0].Query["userId"]);
    }

    [Theory]
    [InlineData("null")]
    [InlineData("{}")]
    [InlineData("{\"id\":11}")]
    [InlineData("{\"id\":11,\"userId\":null}")]
    [InlineData("{\"id\":12,\"userId\":10466}")]
    [InlineData("{\"id\":11,\"userId\":10466,\"UserId\":999}")]
    [InlineData("{\"id\":11,\"Id\":12,\"userId\":10466}")]
    [InlineData("{\"data\":{\"id\":11,\"userId\":10466}}")]
    public async Task Detail_FailsClosedWhenOwnershipOrRecordIdentityIsUnreliable(string upstream)
    {
        var proxy = new Proxy(Success(upstream));
        var response = await Controller(proxy).GetMandate("11", default);
        Assert.Equal(404, Assert.IsType<ObjectResult>(response.Result).StatusCode);
    }

    [Theory]
    [InlineData(Owned)]
    [InlineData("{\"Id\":\"11\",\"UserId\":\"10466\"}")]
    public async Task Detail_PreservesOwnedRecordWithoutSecondRead(string upstream)
    {
        var proxy = new Proxy(Success(upstream));
        var response = await Controller(proxy).GetPaymentRequest("11", default);
        Assert.Equal(upstream, Assert.IsType<JsonElement>(Assert.IsType<OkObjectResult>(response.Result).Value).GetRawText());
        Assert.Single(proxy.Calls);
    }

    [Theory]
    [InlineData("0")]
    [InlineData("-1")]
    [InlineData("11/revoke")]
    [InlineData("11?userId=999")]
    [InlineData("00000000-0000-0000-0000-000000000000")]
    [InlineData("503745a3cd3f4d48ac3f53c99de1707a")]
    [InlineData("503745a3-cd3f-4d48-ac3f-53c99de1707x")]
    [InlineData("1.0")]
    [InlineData("1e3")]
    [InlineData("+11")]
    [InlineData("9223372036854775808")]
    public async Task Detail_RejectsInvalidRecordIdBeforeCallingProvider(string id)
    {
        var proxy = new Proxy();
        var response = await Controller(proxy).GetMandate(id, default);
        Assert.Equal(404, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Empty(proxy.Calls);
    }

    [Theory]
    [InlineData("mandate")]
    [InlineData("request")]
    [InlineData("payment")]
    public async Task Mutation_RejectsAnotherCustomersRecordWithoutSendingMutation(string route)
    {
        var proxy = new Proxy(Success("{\"id\":11,\"userId\":999}"));
        var response = await Mutate(Controller(proxy), route, default);
        Assert.Equal(404, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Equal(HttpMethod.Get, Assert.Single(proxy.Calls).Method);
    }

    [Theory]
    [InlineData("mandate", "/api/v2/payments/mandates/11", "revoke")]
    [InlineData("request", "/api/v2/payments/requests/11", "cancel")]
    [InlineData("payment", "/api/v2/payments/requests/11", "cancel")]
    public async Task Mutation_PreflightsOwnerThenPreservesAuthorizedOperation(string route, string resource, string action)
    {
        var proxy = new Proxy(Success(Owned), Success(Owned));
        using var cancel = new CancellationTokenSource();
        var response = await Mutate(Controller(proxy), route, cancel.Token);
        Assert.IsType<OkObjectResult>(response.Result);
        Assert.Equal(new[] { resource, resource + "/" + action }, proxy.Calls.Select(c => c.Path));
        Assert.Equal(new[] { HttpMethod.Get, HttpMethod.Put }, proxy.Calls.Select(c => c.Method));
        Assert.All(proxy.Calls, c => Assert.Equal(cancel.Token, c.Cancellation));
        Assert.All(proxy.Calls, c => Assert.Equal("10466", c.Query["userId"]));
    }

    [Theory]
    [InlineData(403, 404)]
    [InlineData(404, 404)]
    [InlineData(502, 502)]
    [InlineData(504, 504)]
    public async Task Mutation_NeverRunsAfterFailedOwnershipRead(int upstreamStatus, int expectedStatus)
    {
        var proxy = new Proxy(ApplicationResult<JsonElement?>.Failure(new("upstream.failed", "Unavailable", upstreamStatus)));
        var response = await Mutate(Controller(proxy), "mandate", default);
        Assert.Equal(expectedStatus, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Single(proxy.Calls);
    }

    [Theory]
    [InlineData("mandates", "mandates")]
    [InlineData("requests", "paymentRequests")]
    [InlineData("payments", "paymentRequests")]
    public async Task List_ForcesCurrentOwnerAndRejectsMixedOwnerResults(string route, string field)
    {
        var proxy = new Proxy(Success("{\"" + field + "\":[" + Owned + ",{\"id\":12,\"userId\":999}],\"total\":2}"));
        var controller = Controller(proxy);
        controller.Request.QueryString = new QueryString("?userId=999&USERID=0");
        var response = await List(controller, route);
        Assert.Equal(404, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Equal("10466", Assert.Single(proxy.Calls).Query["userId"]);
    }

    [Theory]
    [InlineData("{\"mandates\":[],\"total\":0}")]
    [InlineData("{\"Mandates\":[{\"Id\":11,\"UserId\":10466}],\"Total\":1}")]
    public async Task List_PreservesValidOwnedPagination(string upstream)
    {
        var proxy = new Proxy(Success(upstream));
        var response = await List(Controller(proxy), "mandates");
        Assert.Equal(upstream, Assert.IsType<JsonElement>(Assert.IsType<OkObjectResult>(response.Result).Value).GetRawText());
        Assert.Equal("3", proxy.Calls[0].Query["pageNumber"]);
        Assert.Equal("10", proxy.Calls[0].Query["pageSize"]);
    }

    [Theory]
    [InlineData("mandate")]
    [InlineData("request")]
    [InlineData("withdrawal")]
    public async Task Create_OverridesEveryClientUserIdVariantWithOneNumericOwner(string route)
    {
        var proxy = new Proxy(Success(Owned));
        var response = await Create(Controller(proxy), route, Json("""{"userId":999,"USERID":0,"UserID":23,"amount":"1.00","currency":"GBP"}"""));
        Assert.IsType<OkObjectResult>(response.Result);
        var body = JsonSerializer.SerializeToElement(Assert.Single(proxy.Calls).Body);
        Assert.Single(body.EnumerateObject(), p => p.Name.Equals("userId", StringComparison.OrdinalIgnoreCase));
        Assert.Equal(OwnerId, body.GetProperty("userId").GetInt32());
        Assert.Equal("1.00", body.GetProperty("amount").GetString());
    }

    [Theory]
    [InlineData("null")]
    [InlineData("[]")]
    [InlineData("{\"amount\":\"1\",\"Amount\":\"100\"}")]
    public async Task Create_RejectsMalformedOrAmbiguousObjectBeforeSending(string body)
    {
        var proxy = new Proxy();
        var response = await Create(Controller(proxy), "request", Json(body));
        Assert.Equal(400, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Empty(proxy.Calls);
    }

    [Fact]
    public async Task TypedPaymentCreation_UsesAuthenticatedNumericOwner()
    {
        var proxy = new Proxy(Success(Owned));
        var response = await Controller(proxy).CreatePayment(new() { Amount = 1, Currency = "GBP" }, default);
        Assert.IsType<OkObjectResult>(response.Result);
        var body = JsonSerializer.SerializeToElement(Assert.Single(proxy.Calls).Body);
        Assert.Equal(OwnerId, body.GetProperty("userId").GetInt32());
    }

    [Theory]
    [InlineData("mandate")]
    [InlineData("request")]
    [InlineData("withdrawal")]
    [InlineData("payment")]
    public async Task Create_PreservesAcceptedOperationWithoutRequiringRecordShapeInAcknowledgement(string route)
    {
        const string acknowledgement = "{\"status\":\"pending\",\"transactionId\":\"provider-123\"}";
        var proxy = new Proxy(Success(acknowledgement));
        var controller = Controller(proxy);
        var response = route == "payment"
            ? await controller.CreatePayment(new() { Amount = 1, Currency = "GBP" }, default)
            : await Create(controller, route, Json("{\"amount\":\"1.00\",\"currency\":\"GBP\"}"));
        Assert.Equal(acknowledgement, Assert.IsType<JsonElement>(Assert.IsType<OkObjectResult>(response.Result).Value).GetRawText());
        Assert.Single(proxy.Calls);
    }

    [Theory]
    [InlineData("mandate")]
    [InlineData("request")]
    [InlineData("payment")]
    public async Task Mutation_PreservesAcknowledgementAfterOwnershipWasVerified(string route)
    {
        const string acknowledgement = "{\"status\":\"completed\"}";
        var proxy = new Proxy(Success(Owned), Success(acknowledgement));
        var response = await Mutate(Controller(proxy), route, default);
        Assert.Equal(acknowledgement, Assert.IsType<JsonElement>(Assert.IsType<OkObjectResult>(response.Result).Value).GetRawText());
        Assert.Equal(2, proxy.Calls.Count);
    }

    [Theory]
    [InlineData("10466")]
    [InlineData("999")]
    [InlineData(UuidOwner)]
    public async Task LegacyCustomerPayout_IsUnavailableWithoutAnyProviderCall(string identity)
    {
        var proxy = new Proxy();
        var response = await Controller(proxy, identity).CreatePayout(
            Json("{\"userId\":999,\"amount\":\"1000.00\",\"currency\":\"GBP\",\"destinationAddress\":\"other-payee\"}"), default);
        var result = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(403, result.StatusCode);
        Assert.Equal("mobile.payments.payouts.unavailable", Assert.IsType<ProblemDetails>(result.Value).Extensions["code"]);
        Assert.Empty(proxy.Calls);
    }

    [Theory]
    [InlineData("")]
    [InlineData("not-a-linked-provider-id")]
    [InlineData("0")]
    [InlineData("00000000-0000-0000-0000-000000000000")]
    [InlineData("a5968eb4229a4c8f8e2865ae8755fbc2")]
    public async Task MissingOrInvalidProviderIdentity_NeverCallsProvider(string identity)
    {
        var proxy = new Proxy();
        var response = await Controller(proxy, identity).GetMandate("11", default);
        Assert.Equal(401, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Empty(proxy.Calls);
    }

    [Theory]
    [InlineData("mandate")]
    [InlineData("request")]
    [InlineData("payment")]
    public async Task UuidDetail_MatchesCanonicalOwnerAndRecord(string route)
    {
        var record = JsonSerializer.Serialize(new { Id = UuidRecord.ToUpperInvariant(), UserId = UuidOwner });
        var proxy = new Proxy(Success(record));
        var response = await Detail(Controller(proxy, UuidOwner.ToUpperInvariant()), route, UuidRecord);
        Assert.Equal(record, Assert.IsType<JsonElement>(Assert.IsType<OkObjectResult>(response.Result).Value).GetRawText());
        var call = Assert.Single(proxy.Calls);
        Assert.EndsWith("/" + UuidRecord, call.Path);
        Assert.Equal(UuidOwner, call.Query["userId"]);
    }

    [Theory]
    [InlineData(UuidOwner, UuidOther, UuidRecord)]
    [InlineData(UuidOwner, UuidOwner, UuidOther)]
    [InlineData(UuidOwner, "10466", UuidRecord)]
    [InlineData("10466", UuidOwner, UuidRecord)]
    [InlineData(UuidOwner, "00000000-0000-0000-0000-000000000000", UuidRecord)]
    [InlineData(UuidOwner, UuidOwner, "11")]
    public async Task UuidMutation_DeniesWrongOwnerOrRecordWithoutWrite(string identity, string recordOwner, string recordId)
    {
        var proxy = new Proxy(Success(JsonSerializer.Serialize(new { id = recordId, userId = recordOwner })));
        var response = await Mutate(Controller(proxy, identity), "request", default, UuidRecord);
        Assert.Equal(404, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Equal(HttpMethod.Get, Assert.Single(proxy.Calls).Method);
    }

    [Theory]
    [InlineData("mandate")]
    [InlineData("request")]
    [InlineData("payment")]
    public async Task UuidMutation_PreflightsThenUsesCanonicalResourcePath(string route)
    {
        var record = JsonSerializer.Serialize(new { id = UuidRecord, userId = UuidOwner.ToUpperInvariant() });
        const string acknowledgement = "{\"status\":\"completed\"}";
        var proxy = new Proxy(Success(record), Success(acknowledgement));
        var response = await Mutate(Controller(proxy, UuidOwner), route, default, UuidRecord.ToUpperInvariant());
        Assert.Equal(acknowledgement, Assert.IsType<JsonElement>(Assert.IsType<OkObjectResult>(response.Result).Value).GetRawText());
        Assert.Equal(new[] { HttpMethod.Get, HttpMethod.Put }, proxy.Calls.Select(c => c.Method));
        Assert.All(proxy.Calls, call => Assert.Contains("/" + UuidRecord, call.Path));
        Assert.All(proxy.Calls, call => Assert.Equal(UuidOwner, call.Query["userId"]));
    }

    [Theory]
    [InlineData("mandate")]
    [InlineData("request")]
    [InlineData("withdrawal")]
    [InlineData("payment")]
    public async Task UuidCreate_ForcesCanonicalAuthenticatedOwnerAsString(string route)
    {
        var proxy = new Proxy(Success("{\"status\":\"pending\"}"));
        var controller = Controller(proxy, UuidOwner.ToUpperInvariant());
        var response = route == "payment"
            ? await controller.CreatePayment(new() { Amount = 1, Currency = "GBP" }, default)
            : await Create(controller, route, Json("{\"userId\":999,\"USERID\":\"" + UuidOther + "\",\"amount\":\"1.00\"}"));
        Assert.IsType<OkObjectResult>(response.Result);
        var call = Assert.Single(proxy.Calls);
        Assert.Equal(UuidOwner, call.Query["userId"]);
        var body = JsonSerializer.SerializeToElement(call.Body);
        Assert.Single(body.EnumerateObject(), p => p.Name.Equals("userId", StringComparison.OrdinalIgnoreCase));
        Assert.Equal(UuidOwner, body.GetProperty("userId").GetString());
    }

    [Theory]
    [InlineData("mandates", "mandates")]
    [InlineData("requests", "paymentRequests")]
    [InlineData("payments", "paymentRequests")]
    public async Task UuidList_PreservesOwnedRecordsAndDeniesMixedOwners(string route, string field)
    {
        var own = new { id = UuidRecord, userId = UuidOwner.ToUpperInvariant() };
        var other = new { id = UuidOther, userId = UuidOther };
        var ownedPage = JsonSerializer.Serialize(new Dictionary<string, object> { [field] = new[] { own }, ["total"] = 1 });
        var mixedPage = JsonSerializer.Serialize(new Dictionary<string, object> { [field] = new[] { own, other }, ["total"] = 2 });
        var proxy = new Proxy(Success(ownedPage), Success(mixedPage));
        var controller = Controller(proxy, UuidOwner);
        Assert.IsType<OkObjectResult>((await List(controller, route)).Result);
        Assert.Equal(404, Assert.IsType<ObjectResult>((await List(controller, route)).Result).StatusCode);
        Assert.All(proxy.Calls, call => Assert.Equal(UuidOwner, call.Query["userId"]));
    }

    private static MobilePaymentsController Controller(Proxy proxy, string userId = "10466") => new(proxy)
    {
        ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(new[] { new Claim("hoppa_user_id", userId) }, "test"))
        } }
    };

    private static Task<ActionResult<JsonElement?>> Detail(MobilePaymentsController c, string route, string id = "11") => route switch
    {
        "mandate" => c.GetMandate(id, default), "request" => c.GetPaymentRequest(id, default), _ => c.GetPayment(id, default)
    };

    private static Task<ActionResult<JsonElement?>> Mutate(MobilePaymentsController c, string route, CancellationToken ct, string id = "11") => route switch
    {
        "mandate" => c.RevokeMandate(id, Json("{\"reason\":\"cancel\"}"), ct),
        "request" => c.CancelPaymentRequest(id, Json("{\"reason\":\"cancel\"}"), ct),
        _ => c.CancelPayment(id, new CancelPaymentRequestDto { Reason = "cancel" }, ct)
    };

    private static Task<ActionResult<JsonElement?>> List(MobilePaymentsController c, string route) => route switch
    {
        "mandates" => c.ListMandates(3, 10, null, null, null, null, default),
        "requests" => c.ListPaymentRequests(3, 10, null, null, null, null, default),
        _ => c.ListPayments(null, 10, null, default)
    };

    private static Task<ActionResult<JsonElement?>> Create(MobilePaymentsController c, string route, JsonElement body) => route switch
    {
        "mandate" => c.CreateMandate(body, default), "request" => c.CreatePaymentRequest(body, default),
        "payout" => c.CreatePayout(body, default), _ => c.CreateWithdrawal(body, default)
    };

    private static JsonElement Json(string json) => JsonSerializer.Deserialize<JsonElement>(json);
    private static ApplicationResult<JsonElement?> Success(string json) => ApplicationResult<JsonElement?>.Success(Json(json));
    private sealed record Call(HttpMethod Method, string Path, IReadOnlyDictionary<string, string?> Query, object? Body, CancellationToken Cancellation);
    private sealed class Proxy(params ApplicationResult<JsonElement?>[] results) : IProxyHoppaRequestUseCase
    {
        private readonly Queue<ApplicationResult<JsonElement?>> _results = new(results);
        public List<Call> Calls { get; } = [];
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(ProxyHoppaRequestCommand<TRequest> command, CancellationToken ct)
        {
            Calls.Add(new(command.Method, command.UpstreamPath, command.Query, command.Request, ct));
            return Task.FromResult(_results.Dequeue());
        }
    }
}
