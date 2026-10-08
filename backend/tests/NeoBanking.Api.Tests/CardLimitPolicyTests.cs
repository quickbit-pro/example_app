using System.Text.Json;
using NeoBanking.Api.Cards;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class CardLimitPolicyTests
{
    private static JsonElement Json(string text) => JsonDocument.Parse(text).RootElement.Clone();

    [Fact]
    public void ResolveCaps_PrefersCardTypeLimitsOverTier()
    {
        var cardTier = Json("""{"cardTypeTier":{"id":7,"cardType":{"id":3,"limits":{"daily_spend":500,"weekly_spend":2000,"monthly_spend":6000}}}}""");
        var tier = Json("""{"id":2,"name":"Pro","limits":{"daily_limit":1000,"monthly_limit":10000}}""");

        var caps = CardLimitPolicy.ResolveCaps(cardTier, tier);

        Assert.Equal("card_type", caps.Source);
        Assert.Equal(500m, caps.Daily);
        Assert.Equal(2000m, caps.Weekly);
        Assert.Equal(6000m, caps.Monthly);
    }

    [Fact]
    public void ResolveCaps_FallsBackToTierLimits()
    {
        var cardTier = Json("""{"cardType":{"id":3,"limits":null}}""");
        var tier = Json("""{"id":2,"limits":{"daily_limit":"1000","monthly_limit":10000}}""");

        var caps = CardLimitPolicy.ResolveCaps(cardTier, tier);

        Assert.Equal("tier", caps.Source);
        Assert.Equal(1000m, caps.Daily);
        Assert.Null(caps.Weekly);
        Assert.Equal(10000m, caps.Monthly);
    }

    [Fact]
    public void ResolveCaps_IsNoneWithoutAnyLimits()
    {
        Assert.False(CardLimitPolicy.ResolveCaps(null, Json("""{"id":1}""")).HasAny);
        Assert.Equal("none", CardLimitPolicy.ResolveCaps(null, null).Source);
    }

    [Fact]
    public void FindTier_LocatesTierInsideWrappedList()
    {
        var tiers = Json("""{"data":{"tiers":[{"id":1,"name":"Standard"},{"id":2,"name":"Pro"}]}}""");

        var tier = CardLimitPolicy.FindTier(tiers, 2);

        Assert.NotNull(tier);
        Assert.Equal("Pro", tier!.Value.GetProperty("name").GetString());
        Assert.Null(CardLimitPolicy.FindTier(tiers, 9));
    }

    [Fact]
    public void ValidationError_RejectsValuesAboveCapOrInconsistent()
    {
        var caps = new CardLimitCaps(500m, 2000m, 6000m, "card_type");

        Assert.Null(CardLimitPolicy.ValidationError(400m, 1500m, 5000m, caps));
        Assert.Contains("Daily limit cannot exceed your tier's ceiling of 500", CardLimitPolicy.ValidationError(501m, null, null, caps));
        Assert.Contains("Monthly limit cannot exceed", CardLimitPolicy.ValidationError(null, null, 6000.01m, caps));
        Assert.Equal("Daily limit cannot be negative.", CardLimitPolicy.ValidationError(-1m, null, null, caps));
        Assert.Equal("Daily limit cannot exceed the weekly limit.", CardLimitPolicy.ValidationError(400m, 300m, null, caps));
        Assert.Null(CardLimitPolicy.ValidationError(999999m, null, null, CardLimitCaps.None));
    }

    [Fact]
    public void FindCardTypeTier_PicksTheCardsRowFromTheTierList()
    {
        var payload = Json("""{"cardTypeTiers":[{"cardTypeSecondaryId":260,"cardTypeId":3,"tierId":3,"cardType":{"id":3,"limits":{"daily_spend":500}}},{"cardTypeSecondaryId":316,"cardTypeId":5,"tierId":3,"cardType":{"id":5,"limits":{"daily_spend":900}}}]}""");

        var byRow = CardLimitPolicy.FindCardTypeTier(payload, 316, null);
        Assert.Equal(316, byRow!.Value.GetProperty("cardTypeSecondaryId").GetInt32());

        var byCardType = CardLimitPolicy.FindCardTypeTier(payload, 999, 3);
        Assert.Equal(260, byCardType!.Value.GetProperty("cardTypeSecondaryId").GetInt32());

        Assert.Null(CardLimitPolicy.FindCardTypeTier(payload, 999, 999));
        Assert.Equal(500m, CardLimitPolicy.ResolveCaps(byCardType, null).Daily);
    }

    [Fact]
    public void UpstreamLimits_DropTrailingScale()
    {
        Assert.Equal("500", NeoBanking.Application.DTOs.Cards.UpdateCardLimitsUpstreamRequestDto.Normalize(500.0m)!.Value.ToString(System.Globalization.CultureInfo.InvariantCulture));
        Assert.Equal("12.5", NeoBanking.Application.DTOs.Cards.UpdateCardLimitsUpstreamRequestDto.Normalize(12.50m)!.Value.ToString(System.Globalization.CultureInfo.InvariantCulture));
        Assert.Null(NeoBanking.Application.DTOs.Cards.UpdateCardLimitsUpstreamRequestDto.Normalize(null));
    }
}
