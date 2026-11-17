using System.Text.Json;
using NeoBanking.Api;
using NeoBanking.Application.DTOs.Cards;
using NeoBanking.Application.DTOs.Tiers;
using Xunit;
namespace NeoBanking.Api.Tests;
public sealed class LegacyPlatformContractTests
{
    [Fact] public void PlatformIdsRemainIntegers() => LegacyPlatformContract.Verify();
    [Fact] public void ProductionTopUpRequestRetainsCard614()
    {
        using var body = JsonDocument.Parse("""{"Value":108.0,"Token":"USD"}""");
        var request = CardTopUpUpstreamRequestDto.From(body.RootElement, "614");
        var json = JsonSerializer.SerializeToElement(request);
        Assert.Equal(614, json.GetProperty("CardId").GetInt32());
        Assert.Equal(108m, json.GetProperty("Value").GetDecimal());
        Assert.Equal("USD", json.GetProperty("Token").GetString());
    }
    [Fact] public void UnloadRetainsNumericCardId()
    {
        using var body = JsonDocument.Parse("""{"Value":10,"Currency":"USD"}""");
        Assert.Equal(614, JsonSerializer.SerializeToElement(CardUnloadUpstreamRequestDto.From(body.RootElement,"614")).GetProperty("CardId").GetInt32());
    }
    [Fact] public void CardOrderAndTierUseNumericIds()
    {
        Assert.Equal(326, JsonSerializer.SerializeToElement(new CreateCardRequestDto { CardTypeId=326 }).GetProperty("CardTypeId").GetInt32());
        Assert.Equal(25, JsonSerializer.SerializeToElement(new SetUserTierRequestDto { TierId=25 }).GetProperty("TierId").GetInt32());
    }
}
