using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using NeoBanking.Infrastructure.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public class ReferralActorSignerTests
{
    [Fact]
    public async Task SignatureBindsExactActorBodyPathQueryAndFreshNonce()
    {
        var options=new ReferralAuditDelegationOptions{Enabled=true,InstallationId="test-app",CompanyId=42,Secret=new string('x',40)};
        using var request=new HttpRequestMessage(HttpMethod.Put,"/api/v2/referrals/program?programId=a%20b")
        {Content=JsonContent.Create(new {reason="Änderung",revision=7})};
        await ReferralActorSigner.SignAsync(request,"admin:123",options,default);
        var encoded=request.Headers.GetValues("X-Referral-Actor").Single();
        var signature=request.Headers.GetValues("X-Referral-Actor-Signature").Single();
        Assert.Equal(WebEncoders.Base64UrlEncode(HMACSHA256.HashData(Encoding.UTF8.GetBytes(options.Secret),Encoding.UTF8.GetBytes(encoded))),signature);
        using var json=JsonDocument.Parse(WebEncoders.Base64UrlDecode(encoded)); var value=json.RootElement;
        Assert.Equal("/api/v2/referrals/program?programId=a%20b",value.GetProperty("path").GetString());
        Assert.Equal("admin:123",value.GetProperty("actor_id").GetString()); Assert.Equal(42,value.GetProperty("company_id").GetInt32());
        Assert.Equal(Convert.ToHexString(SHA256.HashData(await request.Content.ReadAsByteArrayAsync())).ToLowerInvariant(),value.GetProperty("body_sha256").GetString());
        Assert.Equal(120,value.GetProperty("expires_at").GetInt64()-value.GetProperty("issued_at").GetInt64());
        using var retry=new HttpRequestMessage(HttpMethod.Put,"/api/v2/referrals/program?programId=a%20b");
        await ReferralActorSigner.SignAsync(retry,"admin:123",options,default);
        using var next=JsonDocument.Parse(WebEncoders.Base64UrlDecode(retry.Headers.GetValues("X-Referral-Actor").Single()));
        Assert.NotEqual(value.GetProperty("nonce").GetString(),next.RootElement.GetProperty("nonce").GetString());
    }
    [Theory]
    [InlineData(false,"admin:123","/api/v2/referrals/program")]
    [InlineData(true,null,"/api/v2/referrals/program")]
    [InlineData(true,"admin:123","/api/v2/users")]
    public async Task DisabledMissingActorAndUnrelatedRoutesNeverClaimHumanActor(bool enabled,string? actor,string path)
    {
        using var request=new HttpRequestMessage(HttpMethod.Get,path);
        await ReferralActorSigner.SignAsync(request,actor,new(){Enabled=enabled,InstallationId="test-app",CompanyId=42,Secret=new string('x',40)},default);
        Assert.False(request.Headers.Contains("X-Referral-Actor"));
    }
    [Fact]
    public async Task EnabledButMisconfiguredSigningFailsClosed()
    {
        using var request=new HttpRequestMessage(HttpMethod.Put,"/api/v2/referrals/program");
        await Assert.ThrowsAsync<InvalidOperationException>(()=>ReferralActorSigner.SignAsync(request,"admin:123",new(){Enabled=true},default));
    }
}
