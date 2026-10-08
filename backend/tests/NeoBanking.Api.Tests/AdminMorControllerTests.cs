using System.ComponentModel.DataAnnotations;
using System.Reflection;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.Company;
using NeoBanking.Application.DTOs.Mor;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AdminMorControllerTests
{
    [Fact]
    public void EveryActionRequiresVerifiedMorAdminPolicy()
    {
        Assert.Equal(AuthorizationPolicyNames.MorAdmin, typeof(AdminMorController).GetCustomAttribute<AuthorizeAttribute>()!.Policy);
        Assert.DoesNotContain(typeof(AdminMorController).GetMethods(), m => m.GetCustomAttribute<AllowAnonymousAttribute>() != null);
    }

    [Fact]
    public async Task ExplicitRoutesPreserveOperationsAndDiscardTenantAndCredentialQueries()
    {
        var proxy = new RecordingProxy(); var controller = Create(proxy);
        controller.Request.QueryString = new QueryString("?companyId=999&apiKey=untrusted&actorUserId=999&path=admin/users");
        await controller.Cards(default); await controller.CardProducts(default); await controller.CardAnalytics(30, default);
        await controller.Transactions(2, 25, 101, "completed", "card_payment", default);
        await controller.AssignCard(42, new(101), default); await controller.UnassignCard(42, default);
        await controller.LoadCard(42, new(12.34m), default); await controller.UnloadCard(42, new(5m), default);
        await controller.CancelCard(42, default); await new AdminMorCompaniesController(proxy).Companies(default); await new AdminMorCompaniesController(proxy).MerchantTiers(default);
        Assert.Equal(new[] { "GET cards", "GET cards/available", "GET cards/analytics", "GET transactions", "POST cards/42/assign", "POST cards/42/unassign", "POST cards/42/load", "POST cards/42/unload", "POST cards/42/cancel", "GET companies", "GET companies/merchant-tiers" },
            proxy.Requests.Select(r => $"{r.Method} {r.Path.Replace("/api/v2/mor/public/", "")}"));
        Assert.All(proxy.Requests, r => { Assert.StartsWith("/api/v2/mor/public/", r.Path); Assert.DoesNotContain("companyId", r.Query.Keys); Assert.DoesNotContain("apiKey", r.Query.Keys); Assert.DoesNotContain("actorUserId", r.Query.Keys); });
        Assert.Equal("2", proxy.Requests[3].Query["page"]);
        Assert.Equal("101", proxy.Requests[3].Query["userId"]);
        Assert.Equal("completed", proxy.Requests[3].Query["status"]);
        Assert.Equal(101, proxy.Requests[4].Body.GetProperty("AssignedUserId").GetInt32());
        Assert.Equal(12.34m, proxy.Requests[6].Body.GetProperty("Amount").GetDecimal());
    }

    [Fact]
    public async Task OnboardingProvisioningAndWalletContractsUsePublicRoutes()
    {
        var proxy = new RecordingProxy(); var controller = Create(proxy);
        await controller.OnboardingStatus(true, default);
        await controller.Cardholder(new("1990-01-01"), default);
        await controller.CreateUser(new("user@example.test", "Test", "User", "temporary-password", "+38640123456"), default);
        await controller.OrderCards(new(5, 20, true, "Team"), default);
        await new AdminMorCompaniesController(proxy).CreateCompany(new("Merchant", "Merchant Ltd", "123", "SI", "admin@example.test", "Merchant", "Admin", "temporary-password", 7), default);
        await controller.Wallets(default);
        Assert.Equal("True", proxy.Requests[0].Query["refresh"]);
        Assert.Equal("/api/v2/mor/public/users", proxy.Requests[2].Path);
        Assert.Equal("+38640123456", proxy.Requests[2].Body.GetProperty("Phone").GetString());
        Assert.Equal(20, proxy.Requests[3].Body.GetProperty("Quantity").GetInt32());
        Assert.Equal(7, proxy.Requests[4].Body.GetProperty("TierId").GetInt32());
    }

    [Theory]
    [InlineData(401)] [InlineData(403)] [InlineData(404)] [InlineData(409)] [InlineData(422)] [InlineData(503)]
    public async Task ProviderFailureIsPreserved(int status)
    {
        var proxy = new RecordingProxy { Error = new("mor.rejected", "Request declined", status, "KYB_REQUIRED") };
        var response = await Create(proxy).OrderCards(new(1, 1, false, null), default);
        var result = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(status, result.StatusCode);
        Assert.Contains("KYB_REQUIRED", JsonSerializer.Serialize(result.Value));
    }

    [Fact]
    public async Task PartialOrderIsNotConvertedIntoCompleteSuccess()
    {
        var proxy = new RecordingProxy { Response = JsonSerializer.SerializeToElement(new { success = false, requestedQuantity = 3, createdQuantity = 1, errors = new[] { "Provider failed" } }) };
        var response = await Create(proxy).OrderCards(new(1, 3, false, null), default);
        var body = Assert.IsType<JsonElement>(Assert.IsType<OkObjectResult>(response.Result).Value);
        Assert.False(body.GetProperty("success").GetBoolean()); Assert.Equal(1, body.GetProperty("createdQuantity").GetInt32());
    }

    [Fact]
    public async Task CancellationPreservesProviderBalanceRejection()
    {
        var proxy = new RecordingProxy { Error = new("mor.rejected", "Frozen balance must be zero", 409, "CARD_HAS_BALANCE") };
        var response = await Create(proxy).CancelCard(42, default);
        var result = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(409, result.StatusCode);
        Assert.Contains("CARD_HAS_BALANCE", JsonSerializer.Serialize(result.Value));
        Assert.Single(proxy.Requests);
    }

    [Fact]
    public async Task SecureWidgetCannotBeCached()
    {
        var controller = Create(new RecordingProxy()); await controller.SecureWidget(42, default);
        Assert.Contains("no-store", controller.Response.Headers.CacheControl.ToString());
        Assert.Equal("no-referrer", controller.Response.Headers["Referrer-Policy"]);
    }

    [Theory]
    [InlineData(0)] [InlineData(21)]
    public void InvalidOrderQuantityIsRejected(int quantity)
    {
        var request = new MorOrderRequest(1, quantity, false, null);
        Assert.False(Validator.TryValidateObject(request, new ValidationContext(request), [], true));
    }

    [Fact]
    public void NonPositiveFundingIsRejected()
    {
        var request = new MorFundingRequest(0);
        Assert.False(Validator.TryValidateObject(request, new ValidationContext(request), [], true));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("40123456")]
    [InlineData("+123")]
    [InlineData("not-a-number")]
    public void CreateUserRejectsMissingOrMalformedPhone(string? phone)
    {
        var request = new MorUserRequest("user@example.test", "Test", "User", "temporary-password", phone!);
        var errors = new List<ValidationResult>();
        Assert.False(Validator.TryValidateObject(request, new ValidationContext(request), errors, true));
        Assert.Contains(errors, error => error.MemberNames.Contains(nameof(MorUserRequest.Phone)));
    }

    [Fact]
    public void CreateUserAcceptsInternationalPhone()
    {
        var request = new MorUserRequest("user@example.test", "Test", "User", "temporary-password", "+38640123456");
        Assert.True(Validator.TryValidateObject(request, new ValidationContext(request), [], true));
    }

    private static AdminMorController Create(RecordingProxy proxy) => new(proxy, new TestCompanyContext()) { ControllerContext = new() { HttpContext = new DefaultHttpContext() } };
    private sealed class TestCompanyContext : ICompanyContextAccessor
    {
        public ICompanyContext Current { get; private set; } = CompanyContext.Empty;
        public void SetCurrent(ICompanyContext context) => Current = context;
        public void Clear() => Current = CompanyContext.Empty;
    }
    private sealed class RecordingProxy : IProxyHoppaRequestUseCase
    {
        public ApplicationError? Error { get; init; }
        public JsonElement Response { get; init; } = JsonSerializer.SerializeToElement(new { success = true });
        public List<Recorded> Requests { get; } = [];
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command, CancellationToken ct)
        {
            Requests.Add(new(command.Method, command.UpstreamPath, command.Query, JsonSerializer.SerializeToElement(command.Request)));
            return Task.FromResult(Error is null ? ApplicationResult<JsonElement?>.Success(Response) : ApplicationResult<JsonElement?>.Failure(Error));
        }
    }
    private sealed record Recorded(HttpMethod Method, string Path, IReadOnlyDictionary<string,string?> Query, JsonElement Body);
}
