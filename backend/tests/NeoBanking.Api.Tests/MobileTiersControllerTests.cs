using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Tiers;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobileTiersControllerTests
{
    private const string Catalog = """
        {
          "Tiers": [
            { "Id": 1, "Name": "Lite", "AccountType": "personal", "IsActive": true, "IsHidden": false },
            { "Id": 2, "Name": "Basic", "AccountType": "personal", "IsActive": true, "IsHidden": true },
            { "Id": 3, "Name": "Premium", "AccountType": "personal", "IsActive": true, "IsHidden": false },
            { "Id": 5, "Name": "Pro Business", "AccountType": "business", "IsActive": true, "IsHidden": false }
          ]
        }
        """;

    [Fact]
    public async Task ListTiers_OffersTheLiveAccountTypeAndKeepsTheCurrentTier()
    {
        var proxy = new TierProxy(Catalog, user: """{ "Id": 10466, "AccountType": "personal", "SelectedTierId": 2 }""");
        var controller = await CreateControllerAsync(proxy, localAccountType: "business");

        var payload = OkPayload(await controller.ListTiers(CancellationToken.None));

        // Basic is hidden but is the customer's plan; the business tier is never shown.
        Assert.Equal([1, 2, 3], TierIds(payload));
    }

    [Fact]
    public async Task ListTiers_FallsBackToTheAccountTypeStoredAtSignup()
    {
        var proxy = new TierProxy(Catalog, user: null);
        var controller = await CreateControllerAsync(proxy, localAccountType: "business");

        var payload = OkPayload(await controller.ListTiers(CancellationToken.None));

        Assert.Equal([5], TierIds(payload));
    }

    [Fact]
    public async Task ListTiers_PassesTheProviderFailureThrough()
    {
        var proxy = new TierProxy(catalog: null, user: """{ "AccountType": "personal" }""");
        var controller = await CreateControllerAsync(proxy);

        var response = await controller.ListTiers(CancellationToken.None);

        Assert.IsNotType<OkObjectResult>(response.Result);
    }

    [Theory]
    [InlineData(2)] // hidden
    [InlineData(5)] // business tier for a personal account
    [InlineData(99)] // not in the catalogue
    public async Task SelectTier_RefusesATierTheCustomerIsNotOffered(int tierId)
    {
        var proxy = new TierProxy(Catalog, user: """{ "AccountType": "personal", "SelectedTierId": 1 }""");
        var controller = await CreateControllerAsync(proxy);

        var response = await controller.SelectTier(
            new ChangeUserTierRequestDto { TierId = tierId, TierCycle = "monthly" },
            CancellationToken.None);

        var badRequest = Assert.IsType<BadRequestObjectResult>(response.Result);
        Assert.Equal(
            "mobile.tiers.not_available",
            JsonSerializer.SerializeToElement(badRequest.Value).GetProperty("code").GetString());
        Assert.DoesNotContain(proxy.Requests, request => request.Method == HttpMethod.Post);
    }

    [Theory]
    [InlineData(3)] // public tier
    [InlineData(2)] // hidden, but the customer is already on it (a billing-cycle change)
    public async Task SelectTier_ForwardsAnOfferedTier(int tierId)
    {
        var proxy = new TierProxy(Catalog, user: """{ "AccountType": "personal", "SelectedTierId": 2 }""");
        var controller = await CreateControllerAsync(proxy);

        var response = await controller.SelectTier(
            new ChangeUserTierRequestDto { TierId = tierId, TierCycle = "yearly" },
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var post = Assert.Single(proxy.Requests, request => request.Method == HttpMethod.Post);
        Assert.Equal("/api/v2/users/10466/tier", post.Path);
        var body = Assert.IsType<SetUserTierRequestDto>(post.Body);
        Assert.Equal(tierId, body.TierId);
        Assert.Equal("yearly", body.TierCycle);
    }

    private static async Task<MobileTiersController> CreateControllerAsync(
        TierProxy proxy,
        string localAccountType = "personal")
    {
        var dbContext = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(dbContext);
        var stored = await dbContext.Users.FindAsync(user.Id);
        stored!.MetadataJson = JsonSerializer.Serialize(new { accountType = localAccountType });
        await dbContext.SaveChangesAsync();

        return new MobileTiersController(dbContext, proxy)
        {
            ControllerContext = MobileIdentityTestSupport.ControllerContext(user.Id)
        };
    }

    private static JsonElement OkPayload(ActionResult<JsonElement?> response)
    {
        var ok = Assert.IsType<OkObjectResult>(response.Result);
        return JsonSerializer.SerializeToElement(ok.Value);
    }

    private static int[] TierIds(JsonElement payload) =>
        payload.GetProperty("Tiers").EnumerateArray().Select(tier => tier.GetProperty("Id").GetInt32()).ToArray();

    /// <summary>Answers the tier catalogue and the provider user; a null body is a provider failure.</summary>
    private sealed class TierProxy(string? catalog, string? user) : IProxyHoppaRequestUseCase
    {
        public List<(HttpMethod Method, string Path, object? Body)> Requests { get; } = [];

        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(
            ProxyHoppaRequestCommand<TRequest> command,
            CancellationToken cancellationToken)
        {
            lock (Requests)
            {
                Requests.Add((command.Method, command.UpstreamPath, command.Request));
            }

            var body = command.UpstreamPath switch
            {
                "/api/v2/tiers" => catalog,
                "/api/v2/users/10466" => user,
                _ => """{ "Success": true }"""
            };

            return Task.FromResult(body is null
                ? ApplicationResult<JsonElement?>.Failure(new ApplicationError(command.FailureCode, command.FailureMessage, 502))
                : ApplicationResult<JsonElement?>.Success(JsonDocument.Parse(body).RootElement.Clone()));
        }
    }
}
