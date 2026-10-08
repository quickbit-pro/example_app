using System.Net;
using Microsoft.AspNetCore.Http;
using NeoBanking.Infrastructure.Hoppa;
using Xunit;
namespace NeoBanking.Api.Tests;
public class ReferralTrustedClientAddressTests
{
    [Theory]
    [InlineData("127.0.0.1","203.0.113.7","203.0.113.7")]
    [InlineData("::ffff:127.0.0.1","::ffff:203.0.113.7","203.0.113.7")]
    [InlineData("203.0.113.8","198.51.100.9","203.0.113.8")]
    [InlineData("127.0.0.1",null,null)]
    [InlineData("::1","not-an-ip",null)]
    [InlineData("127.0.0.1","127.0.0.1",null)]
    [InlineData("127.0.0.1","203.0.113.1,198.51.100.1",null)]
    public void OnlyTrustedLoopbackProxyCanSupplyClientAddress(string peer,string? header,string? expected)
    {
        var context=new DefaultHttpContext();context.Connection.RemoteIpAddress=IPAddress.Parse(peer);
        if(header is not null)context.Request.Headers["X-Real-IP"]=header;
        context.Request.Headers["X-Forwarded-For"]="198.51.100.250";
        Assert.Equal(expected,TrustedClientAddress.Resolve(context)?.ToString());
    }
}
