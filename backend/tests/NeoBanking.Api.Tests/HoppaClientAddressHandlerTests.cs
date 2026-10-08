using System.Net;
using Microsoft.AspNetCore.Http;
using NeoBanking.Infrastructure.Hoppa;
using Xunit;

public sealed class HoppaClientAddressHandlerTests
{
    [Theory]
    [InlineData("127.0.0.1", "198.51.100.7", "198.51.100.7")]
    [InlineData("::ffff:127.0.0.1", "::ffff:198.51.100.8", "198.51.100.8")]
    [InlineData("198.51.100.9", "203.0.113.99", "198.51.100.9")]
    [InlineData("127.0.0.1", "198.51.100.7, 203.0.113.99", null)]
    [InlineData("127.0.0.1", "not-an-address", null)]
    public async Task OnlyTrustsSingleAddressFromLoopbackProxy(string peer, string realIp, string? expected)
    {
        var context = new DefaultHttpContext();
        context.Connection.RemoteIpAddress = IPAddress.Parse(peer);
        context.Request.Headers["X-Real-IP"] = realIp;
        context.Request.Headers["X-Forwarded-For"] = "203.0.113.99";
        using var client = new HttpClient(new HoppaClientAddressHandler(
            new HttpContextAccessor { HttpContext = context }) { InnerHandler = new Capture(expected) });
        using var request = new HttpRequestMessage(HttpMethod.Get, "https://upstream.test/");
        request.Headers.Add("X-Forwarded-For", "203.0.113.99");
        using var response = await client.SendAsync(request);
    }

    [Fact]
    public async Task BackgroundCallsHaveNoFabricatedClientAddress()
    {
        using var client = new HttpClient(new HoppaClientAddressHandler(
            new HttpContextAccessor()) { InnerHandler = new Capture(null) });
        using var response = await client.GetAsync("https://upstream.test/");
    }

    private sealed class Capture(string? expected) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var actual = request.Headers.TryGetValues("X-Forwarded-For", out var values) ? values.Single() : null;
            Assert.Equal(expected, actual);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK));
        }
    }
}
