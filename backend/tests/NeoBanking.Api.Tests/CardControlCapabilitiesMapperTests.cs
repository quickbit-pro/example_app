using System.Text.Json;
using NeoBanking.Api.Cards;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class CardControlCapabilitiesMapperTests
{
    [Fact]
    public void Map_UsesExplicitHoppaCapabilitiesWithoutInferringFromBin()
    {
        using var document = JsonDocument.Parse("""
            {
              "data": {
                "card": {
                  "bin": "555555",
                  "capabilities": {
                    "supportedActions": ["freeze", "merchant_lock", "limits"],
                    "isMerchantLocked": true,
                    "lockedMerchantName": "Example Store",
                    "limits": { "daily": 500 }
                  }
                }
              }
            }
            """);

        var result = CardControlCapabilitiesMapper.Map(document.RootElement);

        Assert.True(result.CanFreeze);
        Assert.True(result.CanMerchantLock);
        Assert.True(result.CanUpdateLimits);
        Assert.True(result.IsMerchantLocked);
        Assert.Equal("Example Store", result.LockedMerchantName);
        Assert.NotNull(result.Limits);
        Assert.False(result.CanControlAtm);
    }

    [Fact]
    public void Map_DoesNotEnableAdvancedControlsFromBinAlone()
    {
        using var document = JsonDocument.Parse("""
            { "card": { "bin": "555555", "status": "active" } }
            """);

        var result = CardControlCapabilitiesMapper.Map(document.RootElement);

        Assert.False(result.CanMerchantLock);
        Assert.False(result.CanUpdateLimits);
        Assert.False(result.CanControlOnlinePayments);
        Assert.Empty(result.SupportedActions);
    }
}
