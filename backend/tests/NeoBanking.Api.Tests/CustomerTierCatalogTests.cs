using System.Text.Json;
using NeoBanking.Api.Tiers;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class CustomerTierCatalogTests
{
    // The provider's company catalogue: every account type, hidden and inactive tiers included.
    private const string Catalog = """
        {
          "Tiers": [
            { "Id": 1, "Name": "Lite", "AccountType": "personal", "IsActive": true, "IsHidden": false, "IsDefault": true },
            { "Id": 2, "Name": "Basic", "AccountType": "personal", "IsActive": true, "IsHidden": true },
            { "Id": 3, "Name": "Premium", "AccountType": "Personal", "IsActive": true, "IsHidden": false },
            { "Id": 4, "Name": "Retired", "AccountType": "personal", "IsActive": false, "IsHidden": false },
            { "Id": 5, "Name": "Pro Business", "AccountType": "business", "IsActive": true, "IsHidden": false },
            { "Id": 6, "Name": "Enterprise Business", "AccountType": "business", "IsActive": true, "IsHidden": true },
            { "Id": 7, "Name": "Everyone", "AccountType": "", "IsActive": true, "IsHidden": false }
          ]
        }
        """;

    private static JsonElement Json(string text) => JsonDocument.Parse(text).RootElement.Clone();

    private static int[] Ids(JsonElement payload, string listKey = "Tiers") =>
        payload.GetProperty(listKey).EnumerateArray().Select(tier => tier.GetProperty("Id").GetInt32()).ToArray();

    [Fact]
    public void Filter_OffersPersonalCustomersTheirActivePublicTiers()
    {
        var filtered = CustomerTierCatalog.Filter(Json(Catalog), "personal", currentTierId: null);

        Assert.Equal([1, 3, 7], Ids(filtered));
    }

    [Fact]
    public void Filter_OffersBusinessCustomersOnlyBusinessTiers()
    {
        var filtered = CustomerTierCatalog.Filter(Json(Catalog), "business", currentTierId: null);

        Assert.Equal([5, 7], Ids(filtered));
    }

    [Theory]
    [InlineData(2)] // hidden
    [InlineData(4)] // inactive
    [InlineData(6)] // other account type and hidden
    public void Filter_AlwaysKeepsTheTierTheCustomerIsOn(int currentTierId)
    {
        var filtered = CustomerTierCatalog.Filter(Json(Catalog), "personal", currentTierId);

        Assert.Contains(currentTierId, Ids(filtered));
        Assert.DoesNotContain(5, Ids(filtered));
    }

    [Fact]
    public void Filter_KeepsTheEnvelopeAndEveryOtherField()
    {
        var filtered = CustomerTierCatalog.Filter(Json(Catalog), "personal", currentTierId: null);

        var lite = filtered.GetProperty("Tiers")[0];
        Assert.Equal("Lite", lite.GetProperty("Name").GetString());
        Assert.True(lite.GetProperty("IsDefault").GetBoolean());
    }

    [Fact]
    public void Filter_ReadsBareArraysWrappersAndCamelCase()
    {
        var bare = CustomerTierCatalog.Filter(
            Json("""[{ "id": 1, "accountType": "business" }, { "id": 2, "accountType": "personal", "isHidden": "true" }, { "id": 3 }]"""),
            "personal",
            currentTierId: null);
        Assert.Equal([3], bare.EnumerateArray().Select(tier => tier.GetProperty("id").GetInt32()));

        var wrapped = CustomerTierCatalog.Filter(
            Json("""{ "data": { "tiers": [{ "tierId": "8", "accountType": "all" }, { "tierId": "9", "isActive": false }] } }"""),
            "business",
            currentTierId: null);
        Assert.Equal(["8"], wrapped.GetProperty("data").GetProperty("tiers").EnumerateArray()
            .Select(tier => tier.GetProperty("tierId").GetString()));
    }

    [Fact]
    public void Filter_DropsEntriesThatAreNotTiers()
    {
        var filtered = CustomerTierCatalog.Filter(Json("""{ "Tiers": [null, "Lite", { "Id": 1 }] }"""), "personal", null);

        Assert.Equal([1], Ids(filtered));
    }

    [Fact]
    public void NormalizeAccountType_TreatsAnythingButBusinessAsPersonal()
    {
        Assert.Equal("business", CustomerTierCatalog.NormalizeAccountType(" Business "));
        Assert.Equal("personal", CustomerTierCatalog.NormalizeAccountType("personal"));
        Assert.Equal("personal", CustomerTierCatalog.NormalizeAccountType(null));
    }
}
