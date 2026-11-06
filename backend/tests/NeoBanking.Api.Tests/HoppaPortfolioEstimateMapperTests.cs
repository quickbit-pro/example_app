using System.Text.Json;
using NeoBanking.Api.Portfolio;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class HoppaPortfolioEstimateMapperTests
{
    [Theory]
    [InlineData("USD", 1.12, 1)]
    [InlineData("EUR", 1, 0.8928571428571429)]
    [InlineData("GBP", 0.8, 0.7142857142857143)]
    public void ReferencePrices_ValueTransactionsWithoutCurrentHoldings(
        string currency, double expectedEurRate, double expectedUsdRate)
    {
        // User 227 has EUR movements but no remaining EUR balance from
        // which the old mapper could infer a conversion rate.
        var estimate = HoppaPortfolioEstimateMapper.Map(JsonSerializer.SerializeToElement(new
        {
            currency,
            estimatedTotalAssets = 7.47m,
            balances = new[] { new { assetCode = "EUR", balance = 0, estimatedValue = 0, targetCurrency = currency } }
        }), currency);
        var prices = JsonSerializer.SerializeToElement(new[]
        {
            new { assetCode = "USD", baseCurrency = "USD", price = 1m, isAvailable = true },
            new { assetCode = "EUR", baseCurrency = "USD", price = 1.12m, isAvailable = true },
            new { assetCode = "GBP", baseCurrency = "USD", price = 1.4m, isAvailable = true }
        });

        var result = HoppaPortfolioEstimateMapper.WithReferencePrices(estimate, prices);
        var rates = result.ValuationRates.ToDictionary(row => row.Currency, row => row.Rate);
        Assert.Equal(expectedEurRate, (double)rates["EUR"], 10);
        Assert.Equal(expectedUsdRate, (double)rates["USD"], 10);
        Assert.Equal(estimate.Total, result.Total);
        Assert.Equal(1m, rates[currency]);
    }

    [Fact]
    public void ReferencePrices_PreserveValuationsAndRejectUnusablePrices()
    {
        using var holdings = JsonDocument.Parse("""
            {"currency":"USD","total":12,"balances":[
              {"assetCode":"EUR","balance":10,"estimatedValue":12,"targetCurrency":"USD"}
            ]}
            """);
        using var prices = JsonDocument.Parse("""
            [
              {"AssetCode":"USD","BaseCurrency":"USD","Price":1,"IsAvailable":true},
              {"AssetCode":"EUR","BaseCurrency":"USD","Price":1.12,"IsAvailable":true},
              {"AssetCode":"GBP","BaseCurrency":"USD","Price":1.4,"IsAvailable":true,"IsStale":true},
              {"assetCode":"AED","baseCurrency":"USD","price":0.27,"isAvailable":false},
              {"assetCode":"RON","baseCurrency":"USD","price":0,"isAvailable":true},
              {"assetCode":"BTC","baseCurrency":"EUR","price":100000,"isAvailable":true},
              {"assetCode":"ETH","baseCurrency":"USD","price":-1,"isAvailable":true}
            ]
            """);
        var estimate = HoppaPortfolioEstimateMapper.Map(holdings.RootElement, "USD");
        var result = HoppaPortfolioEstimateMapper.WithReferencePrices(estimate, prices.RootElement);
        var rates = result.ValuationRates.ToDictionary(row => row.Currency, row => row.Rate);
        Assert.Equal(1.2m, rates["EUR"]);
        Assert.Equal(1.4m, rates["GBP"]);
        Assert.Equal(3, rates.Count);
        Assert.True(result.IsStale);
        Assert.Equal(estimate.Total, result.Total);
    }

    [Fact]
    public void ReferencePrices_WithoutTargetOrArrayLeaveEstimateUsable()
    {
        var estimate = HoppaPortfolioEstimateMapper.Map(JsonSerializer.SerializeToElement(new { currency = "GBP", total = 10 }), "GBP");
        Assert.Equal(estimate, HoppaPortfolioEstimateMapper.WithReferencePrices(estimate, null));
        Assert.Equal(estimate, HoppaPortfolioEstimateMapper.WithReferencePrices(estimate, JsonSerializer.SerializeToElement(new { })));
        using var prices = JsonDocument.Parse("""
            [{"assetCode":"USD","baseCurrency":"USD","price":1,"isAvailable":true}]
            """);
        Assert.Equal(estimate, HoppaPortfolioEstimateMapper.WithReferencePrices(estimate, prices.RootElement));
    }

    [Fact]
    public void Map_NormalizesLikelyHoppaEstimateFields()
    {
        using var document = JsonDocument.Parse("""
            {
              "data": {
                "summary": {
                  "estimatedTotalAssets": "24562.35",
                  "currency": "usd",
                  "valuedAt": "2026-09-01T08:00:00Z",
                  "isPartial": true,
                  "missingCurrencies": ["ZMW"]
                }
              }
            }
            """);

        var result = HoppaPortfolioEstimateMapper.Map(document.RootElement, "EUR");

        Assert.Equal("USD", result.Currency);
        Assert.Equal(24562.35m, result.Total);
        Assert.True(result.IsPartial);
        Assert.Equal("ZMW", Assert.Single(result.MissingCurrencies));
        Assert.Equal("hoppa", result.Source);
    }

    [Fact]
    public void Map_NormalizesPublishedEstimatedUserAssetsResponse()
    {
        using var document = JsonDocument.Parse("""
            {
              "UserId": 10466,
              "Currency": "EUR",
              "EstimatedTotalAssets": 1234.56,
              "CalculatedAt": "2026-09-01T09:00:00Z",
              "IsComplete": true,
              "Balances": [
                {
                  "Source": "equals-money",
                  "AssetCode": "GBP",
                  "Balance": 500,
                  "EstimatedValue": 577.12,
                  "TargetCurrency": "EUR",
                  "LastBalanceUpdatedAt": "2026-09-01T08:59:00Z"
                }
              ],
              "ProviderTotals": [
                {
                  "Provider": "equalsmoney",
                  "EstimatedTotalAssets": 512.13,
                  "Currency": "USD",
                  "AssetCount": 7,
                  "IsAvailable": true,
                  "UnpricedAssetCodes": []
                }
              ],
              "UnpricedAssetCodes": ["ZMW"]
            }
            """);

        var result = HoppaPortfolioEstimateMapper.Map(document.RootElement, "USD");

        Assert.Equal("EUR", result.Currency);
        Assert.Equal(1234.56m, result.Total);
        Assert.Equal(DateTimeOffset.Parse("2026-09-01T09:00:00Z"), result.ValuedAt);
        Assert.False(result.IsPartial);
        Assert.Equal("ZMW", Assert.Single(result.MissingCurrencies));
        Assert.False(result.IsStale);
        var provider = Assert.Single(result.ProviderTotals);
        Assert.Equal("equalsmoney", provider.Provider);
        Assert.Equal(512.13m, provider.Total);
        Assert.Equal("USD", provider.Currency);
        Assert.Equal(7, provider.AssetCount);
        Assert.True(provider.IsAvailable);
        Assert.Equal(1.15424m, Assert.Single(result.ValuationRates,
            rate => rate.Currency == "GBP").Rate);
    }

    [Fact]
    public void Map_PreservesRatesForComparingEqualsCurrenciesAndIgnoresUnpricedRows()
    {
        using var document = JsonDocument.Parse("""
            {"currency":"USD","estimatedTotalAssets":57.8375,"balances":[
              {"assetCode":"EUR","balance":37.92,"estimatedValue":44.0823824863,"targetCurrency":"USD"},
              {"assetCode":"AED","balance":42.15,"estimatedValue":11.477195371,"targetCurrency":"USD"},
              {"assetCode":"RON","balance":10.29,"estimatedValue":2.27792943546,"targetCurrency":"USD"},
              {"assetCode":"BTC","balance":0,"estimatedValue":null,"targetCurrency":"USD"},
              {"assetCode":"GBP","balance":5,"estimatedValue":6,"targetCurrency":"EUR"},
              {"assetCode":"ETH","balance":1,"estimatedValue":null,"targetCurrency":"USD"}
            ]}
            """);
        var result = HoppaPortfolioEstimateMapper.Map(document.RootElement, "USD");
        var rates = result.ValuationRates.ToDictionary(row => row.Currency, row => row.Rate);
        Assert.Equal(1m, rates["USD"]);
        Assert.True(37.92m * rates["EUR"] > 42.15m * rates["AED"]);
        Assert.True(42.15m * rates["AED"] > 10.29m * rates["RON"]);
        Assert.Equal(4, rates.Count);
    }
}
