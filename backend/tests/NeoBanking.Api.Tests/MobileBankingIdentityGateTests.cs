using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobileBankingIdentityGateTests
{
    [Theory]
    [InlineData("{}")]
    [InlineData("null")]
    [InlineData("{\"HoppaCardKycApproved\":false}")]
    [InlineData("{\"hoppaStatus\":\"pending\"}")]
    [InlineData("{\"hoppaStatus\":\"rejected\"}")]
    [InlineData("{\"hoppaStatus\":\"not_started\"}")]
    [InlineData("{\"Interlace\":{\"Status\":\"approved\"}}")]
    [InlineData("{\"HoppaCardKycApproved\":false,\"hoppaStatus\":\"approved\"}")]
    public async Task UnapprovedIdentity_NeverPostsBankingApplication(string status)
    {
        var proxy = new StubProxy(ApplicationResult<JsonElement?>.Success(Json(status)));
        var controller = CreateController(proxy);
        controller.Request.QueryString = new QueryString("?userId=someone-else&HoppaCardKycApproved=true");
        var response = await controller.SubmitEqualsMoneyOnboarding(ValidForm(), CancellationToken.None);
        var result = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(403, result.StatusCode);
        Assert.Equal("mobile.banking.identity_verification.required",
            Assert.IsType<ProblemDetails>(result.Value).Extensions["code"]);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Get, request.Method);
        Assert.Equal("/api/v2/users/10466/kyc/detailed-status", request.UpstreamPath);
    }

    [Theory]
    [InlineData("{\"HoppaCardKycApproved\":true}")]
    [InlineData("{\"hoppaCardKycApproved\":true}")]
    [InlineData("{\"hoppaStatus\":\"approved\"}")]
    public async Task ApprovedIdentity_PostsApplicationAfterCheckingStatus(string status)
    {
        var proxy = new StubProxy(ApplicationResult<JsonElement?>.Success(Json(status)),
            ApplicationResult<JsonElement?>.Success(Json("{\"message\":\"submitted\"}")));
        var response = await CreateController(proxy).SubmitEqualsMoneyOnboarding(ValidForm(), CancellationToken.None);
        Assert.IsType<OkObjectResult>(response.Result);
        Assert.Equal(2, proxy.Requests.Count);
        Assert.Equal(HttpMethod.Get, proxy.Requests[0].Method);
        Assert.Equal(HttpMethod.Post, proxy.Requests[1].Method);
        Assert.Equal("/api/v2/banking/equalsmoney-onboarding", proxy.Requests[1].UpstreamPath);
        Assert.Equal("10466", proxy.Requests[1].Query["userId"]);
    }

    [Fact]
    public async Task IdentityStatusFailure_IsReturnedWithoutPosting()
    {
        var proxy = new StubProxy(ApplicationResult<JsonElement?>.Failure(
            new ApplicationError("status.unavailable", "Try again.", 502)));
        var response = await CreateController(proxy).SubmitEqualsMoneyOnboarding(ValidForm(), CancellationToken.None);
        Assert.Equal(502, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Single(proxy.Requests);
    }

    [Fact]
    public async Task MissingIdentity_DoesNotCallUpstream()
    {
        var proxy = new StubProxy();
        var response = await CreateController(proxy, null).SubmitEqualsMoneyOnboarding(ValidForm(), CancellationToken.None);
        Assert.Equal(401, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Empty(proxy.Requests);
    }

    private static EqualsMoneyOnboardingFormDto ValidForm() => new()
    {
        RequestedFeatures = ["PAYMENTS"],
        MainPurpose = ["PURCHASE_OF_GOODS_OR_SERVICES"],
        SourceOfFunds = ["RECEIVING_FUNDS_FROM_OWN_ACCOUNTS"],
        DestinationOfFunds = ["GB"],
        CurrenciesRequired = ["GBP"],
        AnnualVolume = "10001-50000",
        NumberOfPayments = "5-10",
        ProofOfAddress = new FormFile(new MemoryStream("%PDF-test"u8.ToArray()), 0, 9, "ProofOfAddress", "address.pdf")
        { Headers = new HeaderDictionary(), ContentType = "application/pdf" }
    };

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
