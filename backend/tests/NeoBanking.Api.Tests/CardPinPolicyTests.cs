using NeoBanking.Api.Cards;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class CardPinPolicyTests
{
    [Theory]
    [InlineData("482915")]
    [InlineData("907341")]
    [InlineData("112358")]
    [InlineData("135790")]
    public void Validate_AcceptsUnpredictableSixDigitPins(string pin)
    {
        Assert.Null(CardPinPolicy.Validate(pin));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("1234")]
    [InlineData("12345")]
    [InlineData("1234567")]
    [InlineData("12a456")]
    [InlineData("１２３４５６")]
    public void Validate_RejectsAnythingButSixAsciiDigits(string? pin)
    {
        var error = CardPinPolicy.Validate(pin);

        Assert.NotNull(error);
        Assert.Equal(CardPinPolicy.ErrorCode, error!.Code);
        Assert.Equal(422, error.StatusCode);
    }

    [Theory]
    [InlineData("000000")]
    [InlineData("111111")]
    [InlineData("999999")]
    public void Validate_RejectsSingleRepeatedDigit(string pin)
    {
        Assert.NotNull(CardPinPolicy.Validate(pin));
        Assert.True(CardPinPolicy.IsSingleDigit(pin));
    }

    [Theory]
    [InlineData("123456")]
    [InlineData("654321")]
    [InlineData("456789")]
    [InlineData("890123")]
    [InlineData("210987")]
    [InlineData("098765")]
    public void Validate_RejectsConsecutiveRuns(string pin)
    {
        Assert.NotNull(CardPinPolicy.Validate(pin));
        Assert.True(CardPinPolicy.IsSequential(pin));
    }

    [Theory]
    [InlineData("121212")]
    [InlineData("123123")]
    [InlineData("909090")]
    [InlineData("258258")]
    public void Validate_RejectsRepeatingPatterns(string pin)
    {
        Assert.NotNull(CardPinPolicy.Validate(pin));
        Assert.True(CardPinPolicy.IsRepeatedBlock(pin));
    }

    [Theory]
    [InlineData("112233")]
    [InlineData("124578")]
    [InlineData("135791")]
    public void Validate_DoesNotOverReject(string pin)
    {
        Assert.False(CardPinPolicy.IsSequential(pin));
        Assert.False(CardPinPolicy.IsRepeatedBlock(pin));
        Assert.Null(CardPinPolicy.Validate(pin));
    }
}
