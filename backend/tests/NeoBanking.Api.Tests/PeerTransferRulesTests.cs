using NeoBanking.Api.Auth;
using NeoBanking.Api.Peer;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class PeerTransferRulesTests
{
    [Theory]
    [InlineData("usd", "USD")]
    [InlineData(" USDC ", "USDC")]
    [InlineData("usdt", "USDT")]
    [InlineData("EUR", null)]
    [InlineData("BTC", null)]
    [InlineData(null, null)]
    public void NormalizeCurrency_AllowsOnlyDollarAssets(string? input, string? expected)
    {
        Assert.Equal(expected, PeerTransferRules.NormalizeCurrency(input));
    }

    [Fact]
    public void Fee_IsFreeWithinDailyQuota_ThenOnePercent()
    {
        Assert.Equal(0m, PeerTransferRules.CalculateFee(250m, 9, "USD"));
        Assert.Equal(2.5m, PeerTransferRules.CalculateFee(250m, 10, "USD"));
        Assert.Equal(0.123457m, PeerTransferRules.CalculateFee(12.3456789m, 12, "USDC"));
    }

    [Fact]
    public void Evaluate_RateLimitsWithinFifteenSeconds()
    {
        var now = new DateTimeOffset(2026, 9, 4, 10, 0, 0, TimeSpan.Zero);
        var pricing = PeerTransferRules.Evaluate(now, 3, now.AddSeconds(-5), 40m, "USD");

        Assert.True(pricing.IsRateLimited);
        Assert.Equal(10, pricing.RateLimitSecondsRemaining);
        Assert.Equal(now.AddSeconds(10), pricing.NextAllowedAt);
        Assert.Equal(7, pricing.FreeTransfersRemaining);
        Assert.False(pricing.FeeApplies);
        Assert.Equal(47, pricing.SendsRemainingToday);
    }

    [Fact]
    public void Evaluate_AppliesFeeAndCapsAfterQuota()
    {
        var now = new DateTimeOffset(2026, 9, 4, 10, 0, 0, TimeSpan.Zero);
        var pricing = PeerTransferRules.Evaluate(now, 50, now.AddMinutes(-1), 100m, "USD");

        Assert.False(pricing.IsRateLimited);
        Assert.True(pricing.FeeApplies);
        Assert.Equal(1m, pricing.FeeAmount);
        Assert.Equal(0, pricing.FreeTransfersRemaining);
        Assert.Equal(0, pricing.SendsRemainingToday);
    }

    [Theory]
    [InlineData("12.5", "USD", "12.50")]
    [InlineData("12.5", "USDC", "12.500000")]
    [InlineData("0.1", "USDT", "0.100000")]
    public void FormatAmount_UsesProviderPrecision(string amount, string currency, string expected)
    {
        Assert.Equal(expected, PeerTransferRules.FormatAmount(decimal.Parse(amount, System.Globalization.CultureInfo.InvariantCulture), currency));
    }

    [Fact]
    public void RoundAmount_TruncatesBeyondSupportedDecimals()
    {
        Assert.Equal(10.12m, PeerTransferRules.RoundAmount(10.129m, "USD"));
        Assert.Equal(10.123456m, PeerTransferRules.RoundAmount(10.1234569m, "USDT"));
    }

    [Fact]
    public void Masking_HidesContactDetailsButKeepsRecognisableTail()
    {
        Assert.Equal("jo***@example.com", PeerTransferRules.MaskEmail("john@example.com"));
        Assert.Equal("j***@x.io", PeerTransferRules.MaskEmail("j@x.io"));
        Assert.Null(PeerTransferRules.MaskEmail(" "));
        Assert.Equal("+********456", PeerTransferRules.MaskPhone("+386 40 123 456"));
        Assert.Null(PeerTransferRules.MaskPhone(null));
    }

    [Fact]
    public void Names_SplitAndInitialsFallBackToEmail()
    {
        Assert.Equal(("Ana", "Maria Kovač"), PeerTransferRules.SplitName("Ana Maria Kovač", "ana@x.io"));
        Assert.Equal(("ana.k", ""), PeerTransferRules.SplitName(null, "ana.k@x.io"));
        Assert.Equal("AK", PeerTransferRules.Initials("Ana", "Kovač"));
        Assert.Equal("A", PeerTransferRules.Initials("ana", ""));
        Assert.Equal("?", PeerTransferRules.Initials("", ""));
    }

    [Fact]
    public void AvatarColor_IsStablePerUser()
    {
        var id = Guid.NewGuid();
        Assert.Equal(PeerTransferRules.AvatarColor(id), PeerTransferRules.AvatarColor(id));
        Assert.StartsWith("#", PeerTransferRules.AvatarColor(id));
    }

    [Theory]
    [InlineData("+386 40 123 456", "0038640123456", true)]
    [InlineData("+386 40 123 456", "040 123 456", true)]
    [InlineData("+386 40 123 456", "+386 40 123 457", false)]
    [InlineData("+386 40 123 456", "456", false)]
    public void PhonesMatch_IgnoresFormattingAndCountryPrefix(string stored, string query, bool expected)
    {
        Assert.Equal(expected, PeerTransferRules.PhonesMatch(stored, query));
    }

    [Fact]
    public void RateLimitKeys_ReadUserFromUnverifiedToken()
    {
        var payload = Convert.ToBase64String("""{"local_user_id":"abc-123","sub":"10466"}"""u8.ToArray())
            .TrimEnd('=').Replace('+', '-').Replace('/', '_');
        var token = $"eyJhbGciOiJIUzI1NiJ9.{payload}.signature";

        Assert.Equal("abc-123", RateLimitKeys.UnverifiedClaim(token, "local_user_id"));
        Assert.Null(RateLimitKeys.UnverifiedClaim("not-a-token", "sub"));
    }
}
