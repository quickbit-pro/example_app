using System.Text.Json;
using NeoBanking.Application.Common;
using NeoBanking.Application.Interfaces;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Referrals;
using Xunit;

namespace NeoBanking.Api.Tests;

public class ReferralAttributionDispatcherTests
{
    [Theory]
    [InlineData(200,0)] [InlineData(503,0)] [InlineData(403,0)] [InlineData(404,1)]
    public async Task DeliveryPostsOnlyWhenReceiptIsMissing(int lookupStatus,int posts)
    {
        var client=new Client(lookupStatus);
        var id=Guid.NewGuid(); var intent=new ReferralAttributionIntent{Id=id,ProviderUserId="123",PayloadJson=JsonSerializer.Serialize(new{commandId=id,quoteId=Guid.NewGuid(),accepted=true})};
        await ReferralAttributionDispatcher.LookupOrDeliverAsync(client,intent,default);
        Assert.Equal(posts,client.Methods.Count(x=>x==HttpMethod.Post));
        Assert.Equal(HttpMethod.Get,client.Methods[0]);
        Assert.EndsWith(id.ToString("D"),client.Paths[0]);
        if(posts==1) Assert.Equal(id,client.Body!.Value.GetProperty("commandId").GetGuid());
    }
    [Theory]
    [InlineData("COMMITTED","APPLIED")] [InlineData("NEEDS_REVIEW","NEEDS_REVIEW")]
    [InlineData("REJECTED","REJECTED")] [InlineData("ok","PENDING")] [InlineData(null,"PENDING")]
    public void UnknownEngineResultNeverBecomesSuccessful(string? value,string expected)=>Assert.Equal(expected,ReferralAttributionDispatcher.Outcome(value));
    private sealed class Client(int status):IHoppaClient
    {
        public List<HttpMethod> Methods {get;}=[]; public List<string> Paths {get;}=[]; public JsonElement? Body;
        public Task<ApplicationResult<TResponse>> SendAsync<TRequest,TResponse>(HoppaRequest<TRequest> request,CancellationToken ct)
        {
            Methods.Add(request.Method);Paths.Add(request.Path);
            if(request.Method==HttpMethod.Post)Body=JsonSerializer.SerializeToElement(request.Body);
            if(request.Method==HttpMethod.Get&&status!=200)return Task.FromResult(ApplicationResult<TResponse>.Failure(new("lookup.failed","failure",status)));
            return Task.FromResult(ApplicationResult<TResponse>.Success(JsonSerializer.Deserialize<TResponse>("{\"status\":\"COMMITTED\"}")!));
        }
    }
}
