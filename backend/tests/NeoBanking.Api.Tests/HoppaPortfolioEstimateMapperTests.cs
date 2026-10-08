using System.Text.Json;
using NeoBanking.Api.Portfolio;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class HoppaPortfolioEstimateMapperTests
{
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
