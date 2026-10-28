using System.Text.Json;
using NeoBanking.Application.DTOs.Banking;
using Xunit;

namespace NeoBanking.Api.Tests;

public class MobilePayeeAcknowledgementTests
{
    [Fact]
    public void ClientCannotDisableNameCheckAcknowledgement()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var request = JsonSerializer.Deserialize<CreatePayeeRequestDto>(
            """{"name":"Jane Doe","requireVerificationAcknowledgement":false,"userId":999}""", options)!;
        var upstream = CreatePayeeUpstreamRequestDto.From(request, "21");
        var body = JsonSerializer.SerializeToElement(upstream, options);
        Assert.True(body.GetProperty("requireVerificationAcknowledgement").GetBoolean());
        Assert.Equal(21, body.GetProperty("userId").GetInt32());
    }
}
