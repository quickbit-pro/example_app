using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.Company;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AdminMorDashboardQueryTests
{
    [Fact]
    public async Task OverviewAndUsersAreBuiltFromPublishedTenantScopedReads()
    {
        var proxy = new ReadProxy(); var controller = Create(proxy);
        var overview = Json(await controller.Overview(default));
        Assert.Equal(1, overview.GetProperty("counts").GetProperty("users").GetInt32());
        Assert.Equal(2, overview.GetProperty("counts").GetProperty("cards").GetInt32());
        Assert.Equal(1, overview.GetProperty("counts").GetProperty("assignedCards").GetInt32());
        Assert.Equal(JsonValueKind.Null, overview.GetProperty("kyb").ValueKind);
        Assert.Equal("installation", overview.GetProperty("company").GetProperty("displayNameSource").GetString());
        Assert.Equal(12.34m, overview.GetProperty("balances").GetProperty("totalUsdValue").GetDecimal());
        var users = Json(await controller.Users(default));
        var user = Assert.Single(users.EnumerateArray());
        Assert.Equal("Ada Lovelace", user.GetProperty("name").GetString());
        Assert.Equal(101, user.GetProperty("userId").GetInt32());
        Assert.DoesNotContain(proxy.Paths, p => p.EndsWith("/overview") || p.EndsWith("/context") || p.EndsWith("/users"));
        Assert.All(proxy.Paths, p => Assert.StartsWith("/api/v2/mor/public/", p));
    }

    [Fact]
    public async Task MerchantCapabilityUsesAuthorizedPublicRead()
    {
        var proxy = new ReadProxy(); var context = Json(await Create(proxy).Context(default));
        Assert.True(context.GetProperty("merchant").GetBoolean());
        Assert.False(context.GetProperty("whitelabel").GetBoolean());
        Assert.True(context.GetProperty("capabilities").GetProperty("cardOrdering").GetBoolean());
        Assert.True(context.GetProperty("capabilities").GetProperty("cardCancellation").GetBoolean());
        Assert.Single(proxy.Paths);
    }

    [Fact]
    public async Task ParentFallbackRequiresMerchantForbiddenAndAuthorizedCompanyListing()
    {
        var proxy = new ReadProxy { TransactionStatus = 403 };
        var context = Json(await Create(proxy).Context(default));
        Assert.False(context.GetProperty("merchant").GetBoolean());
        Assert.True(context.GetProperty("whitelabel").GetBoolean());
        Assert.Equal(new[] {"/api/v2/mor/public/transactions", "/api/v2/mor/public/companies"}, proxy.Paths);
    }

    [Theory]
    [InlineData(401)] [InlineData(404)] [InlineData(429)] [InlineData(500)] [InlineData(503)]
    public async Task AuthAndProviderFailuresDoNotBecomeCapabilityDecisions(int status)
    {
        var proxy = new ReadProxy { TransactionStatus = status };
        var response = await Create(proxy).Context(default);
        Assert.Equal(status, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Single(proxy.Paths);
    }

    [Fact]
    public async Task MalformedDataCannotBecomeZeroCounts()
    {
        var proxy = new ReadProxy { MalformedCards = true };
        var response = await Create(proxy).Overview(default);
        Assert.Equal(502, Assert.IsType<ObjectResult>(response.Result).StatusCode);
    }

    [Fact]
    public async Task OnboardingProviderFailureIsNotTreatedAsNotSubmitted()
    {
        var proxy = new ReadProxy { OnboardingStatus = 503 };
        var response = await Create(proxy).Overview(default);
        Assert.Equal(503, Assert.IsType<ObjectResult>(response.Result).StatusCode);
    }

    [Theory]
    [InlineData(true)] [InlineData(false)]
    public async Task FundingUsesExistingApiAndDerivedMerchantAdmin(bool estimate)
    {
        var proxy = new ReadProxy(); var controller = Create(proxy);
        controller.Request.QueryString = new QueryString("?userId=999&companyId=999");
        if (estimate) await controller.QuantumEstimate(100m, default);
        else await controller.QuantumTransfer(new("USDT", "USD", 100m), default);
        Assert.Equal("102", proxy.FundingUserId);
        Assert.Equal(estimate ? "/api/v2/cards/quantum-topup/estimate" : "/api/v2/transfers/crypto-to-quantum-transfer", proxy.Paths.Last());
    }

    [Fact]
    public async Task FundingCannotUseTheParentOrAnUnverifiedActor()
    {
        var proxy = new ReadProxy { TransactionStatus = 403 };
        var result = await Create(proxy).QuantumTransfer(new("USDT", "USD", 10m), default);
        Assert.Equal(403, Assert.IsType<ObjectResult>(result.Result).StatusCode);
        Assert.Single(proxy.Paths);
        Assert.Null(proxy.FundingUserId);
    }

    private static JsonElement Json(ActionResult<JsonElement?> result) => Assert.IsType<JsonElement>(Assert.IsType<OkObjectResult>(result.Result).Value);
    private static AdminMorController Create(ReadProxy proxy) => new(proxy, new Installation()) { ControllerContext = new() { HttpContext = new DefaultHttpContext() } };
    private sealed class Installation : ICompanyContextAccessor
    {
        public ICompanyContext Current => CompanyContext.Empty;
        public void SetCurrent(ICompanyContext context) { }
        public void Clear() { }
    }
    private sealed class ReadProxy : IProxyHoppaRequestUseCase
    {
        public List<string> Paths { get; } = [];
        public string? FundingUserId { get; private set; }
        public int TransactionStatus { get; init; } = 200;
        public int OnboardingStatus { get; init; } = 404;
        public bool MalformedCards { get; init; }
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command, CancellationToken ct)
        {
            Paths.Add(command.UpstreamPath);
            if (!command.UpstreamPath.StartsWith("/api/v2/mor/public/"))
            {
                FundingUserId = command.Query["userId"];
                if (command.Method == HttpMethod.Get) Assert.Equal("100", command.Query["amount"]);
                else Assert.Equal(100m, JsonSerializer.SerializeToElement(command.Request).GetProperty("Amount").GetDecimal());
                return Task.FromResult(ApplicationResult<JsonElement?>.Success(JsonSerializer.SerializeToElement(new { success = true })));
            }
            Assert.Equal(HttpMethod.Get, command.Method);
            var route = command.UpstreamPath.Replace("/api/v2/mor/public/", "");
            var status = route == "transactions" ? TransactionStatus : route == "onboarding-status" ? OnboardingStatus : 200;
            if (status != 200) return Task.FromResult(ApplicationResult<JsonElement?>.Failure(new("upstream", "Upstream error", status)));
            var json = route switch {
                "transactions" => "{\"data\":[],\"users\":[{\"userId\":101,\"role\":\"user_simple\",\"name\":\"Ada Lovelace\",\"email\":\"ada@example.test\"},{\"userId\":102,\"role\":\"white_label_admin_mor\",\"name\":\"Admin\"}]}",
                "cards" => MalformedCards ? "{}" : "[{\"id\":1,\"assignedUserId\":101},{\"id\":2,\"assignedUserId\":null}]",
                "wallets" => "{\"balances\":{\"totalUsdValue\":12.34}}",
                "companies" => "[]",
                _ => throw new InvalidOperationException("Unexpected upstream route: " + route)
            };
            if (route == "transactions") Assert.Equal("1", command.Query["pageSize"]);
            return Task.FromResult(ApplicationResult<JsonElement?>.Success(JsonSerializer.Deserialize<JsonElement>(json)));
        }
    }
}
