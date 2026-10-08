using NeoBanking.Application.Common;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class PhoneNumberParserTests
{
    [Theory]
    [InlineData("+491782686605", "49", "1782686605")]
    [InlineData("+905323691899", "90", "5323691899")]
    [InlineData("0049 178 268 6605", "49", "1782686605")]
    [InlineData("+386 40 123 456", "386", "40123456")]
    [InlineData("+38640123456", "386", "40123456")]
    [InlineData("+40721234567", "40", "721234567")]
    [InlineData("+14155552671", "1", "4155552671")]
    [InlineData("+85291234567", "852", "91234567")]
    public void Split_ResolvesTheDialCodeForEveryCountry(string value, string expectedCode, string expectedPhone)
    {
        var parsed = PhoneNumberParser.Split(value);

        Assert.NotNull(parsed);
        Assert.Equal(expectedCode, parsed.Value.PhoneCode);
        Assert.Equal(expectedPhone, parsed.Value.Phone);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("+")]
    [InlineData("+49")]
    [InlineData("+4912")]
    [InlineData("+999123456")]
    [InlineData("+38640123")]
    public void Split_ReturnsNullForUnparseableOrInvalidNumbers(string? value)
    {
        Assert.Null(PhoneNumberParser.Split(value));
    }

    [Fact]
    public void Split_LeavesBareNationalNumbersAloneWithoutAFallbackCode()
    {
        Assert.Null(PhoneNumberParser.Split("4155552671"));
    }

    [Fact]
    public void Split_ValidatesBareNationalNumbersAgainstTheFallbackCode()
    {
        var parsed = PhoneNumberParser.Split("4155552671", "1");

        Assert.NotNull(parsed);
        Assert.Equal("1", parsed.Value.PhoneCode);
        Assert.Equal("4155552671", parsed.Value.Phone);
        Assert.Null(PhoneNumberParser.Split("12", "1"));
    }
}
