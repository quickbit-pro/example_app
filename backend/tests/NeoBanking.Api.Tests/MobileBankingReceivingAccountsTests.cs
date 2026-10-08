using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobileBankingReceivingAccountsTests
{
    [Fact]
    public async Task ListReceivingAccounts_PreservesBankDetailsAndExactAccountIdentity()
    {
        var payload = Json("""
            {"Accounts":[{"AccountId":"budget-eur","AccountType":"BUDGET","ParentAccountId":"owner-1","AccountHolderName":"Test Account Holder","LinkedBankAccounts":[{"Currency":"EUR","IBAN":"test-api-iban","BIC":"test-api-bic"}]}]}
            """);
        var proxy = new StubProxy(ApplicationResult<JsonElement?>.Success(payload));
        var controller = CreateController(proxy);
        using var cancellation = new CancellationTokenSource();

        var response = await controller.ListReceivingAccounts(cancellation.Token);

        var ok = Assert.IsType<OkObjectResult>(response.Result);
        var body = Assert.IsType<JsonElement>(ok.Value);
        Assert.Equal(payload.GetRawText(), body.GetRawText());
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Get, request.Method);
        Assert.Equal("/api/v2/baas/accounts", request.UpstreamPath);
        Assert.Equal("10466", Assert.Single(request.Query).Value);
        Assert.True(request.Query.ContainsKey("userId"));
        Assert.Equal(cancellation.Token, proxy.CancellationToken);
    }

    [Fact]
    public async Task ListReceivingAccounts_IgnoresCallerSuppliedScope()
    {
        var proxy = new StubProxy(ApplicationResult<JsonElement?>.Success(Json("""{"Accounts":[]}""")));
        var controller = CreateController(proxy);
        controller.Request.QueryString = new QueryString(
            "?userId=someone-else&UserId=another-user&accountId=other-account&currency=EUR");

        await controller.ListReceivingAccounts(CancellationToken.None);

        var request = Assert.Single(proxy.Requests);
        Assert.Single(request.Query);
        Assert.Equal("10466", request.Query["userId"]);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(" ")]
    public async Task ListReceivingAccounts_RequiresMappedUserBeforeCallingUpstream(string? userId)
    {
        var proxy = new StubProxy();
        var controller = CreateController(proxy, userId);
        controller.Request.QueryString = new QueryString("?userId=10466");

        var response = await controller.ListReceivingAccounts(CancellationToken.None);

        var result = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status401Unauthorized, result.StatusCode);
        var problem = Assert.IsType<ProblemDetails>(result.Value);
        Assert.Equal("identity.missing", problem.Extensions["code"]);
        Assert.Empty(proxy.Requests);
    }

    [Theory]
    [InlineData(StatusCodes.Status403Forbidden)]
    [InlineData(StatusCodes.Status404NotFound)]
    [InlineData(StatusCodes.Status502BadGateway)]
    public async Task ListReceivingAccounts_PropagatesUpstreamFailure(int statusCode)
    {
        var proxy = new StubProxy(ApplicationResult<JsonElement?>.Failure(
            new ApplicationError("receiving.failed", "Receiving accounts unavailable.", statusCode)));
        var controller = CreateController(proxy);

        var response = await controller.ListReceivingAccounts(CancellationToken.None);

        var result = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(statusCode, result.StatusCode);
        var problem = Assert.IsType<ProblemDetails>(result.Value);
        Assert.Equal("receiving.failed", problem.Extensions["code"]);
        Assert.Equal("Receiving accounts unavailable.", problem.Title);
        Assert.Single(proxy.Requests);
    }

    private static MobileBankingController CreateController(StubProxy proxy, string? userId = "10466")
    {
        var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, "local-user") };
        if (userId is not null)
        {
            claims.Add(new Claim("hoppa_user_id", userId));
        }

        var context = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(claims, "test"))
        };
        context.Request.Path = "/api/v1/mobile/banking/receiving-accounts";
        return new MobileBankingController(proxy)
        {
            ControllerContext = new ControllerContext { HttpContext = context }
        };
    }

    private static JsonElement Json(string value)
    {
        using var document = JsonDocument.Parse(value);
        return document.RootElement.Clone();
    }

    private sealed record CapturedRequest(
        HttpMethod Method,
        string UpstreamPath,
        IReadOnlyDictionary<string, string?> Query);

    private sealed class StubProxy(params ApplicationResult<JsonElement?>[] results)
        : IProxyHoppaRequestUseCase
    {
        private readonly Queue<ApplicationResult<JsonElement?>> _results = new(results);

        public List<CapturedRequest> Requests { get; } = [];
        public CancellationToken CancellationToken { get; private set; }

        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(
            ProxyHoppaRequestCommand<TRequest> command,
            CancellationToken cancellationToken)
        {
            Requests.Add(new CapturedRequest(command.Method, command.UpstreamPath, command.Query));
            CancellationToken = cancellationToken;
            return Task.FromResult(_results.Dequeue());
        }
    }
}
