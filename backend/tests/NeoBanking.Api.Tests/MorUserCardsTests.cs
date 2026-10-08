using System.ComponentModel.DataAnnotations;
using System.Reflection;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.DTOs.Mor;
using NeoBanking.Api.Mor;
using NeoBanking.Application.Common;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;
namespace NeoBanking.Api.Tests;
public sealed class MorUserCardsTests
{
    [Fact]
    public void UserSurfaceRequiresMorRoleAndExposesNoAdminActions()
    {
        Assert.Equal(AuthorizationPolicyNames.MorUser,typeof(MorUserCardsController).GetCustomAttribute<AuthorizeAttribute>()!.Policy);
        Assert.DoesNotContain(typeof(MorUserCardsController).GetMethods(),m=>new[]{"OrderCards","LoadCard","UnloadCard","AssignCard","CancelCard","CreateUser"}.Contains(m.Name));
    }
    [Theory]
    [InlineData(true)] [InlineData(false)]
    public async Task FreezeDerivesActorAndRechecksAssignment(bool freeze)
    {
        var proxy=new Proxy(); var controller=Create(proxy);
        controller.Request.QueryString=new("?userId=999&companyId=999");
        if(freeze) await controller.Freeze(42,default); else await controller.Unfreeze(42,default);
        Assert.Equal("/api/v2/mor/public/users/101/cards",proxy.Requests[0].Path);
        Assert.Equal(freeze?"/api/v2/cards/42/freeze":"/api/v2/cards/42/enable",proxy.Requests[1].Path);
        Assert.Equal("101",proxy.Requests[1].Query["userId"]);
        Assert.DoesNotContain("companyId",proxy.Requests[1].Query.Keys);
    }
    [Theory]
    [InlineData(999,101)] [InlineData(42,999)]
    public async Task AnotherUsersCardCannotBeOperated(int requestedCard,int assignedUser)
    {
        var proxy=new Proxy{AssignedUser=assignedUser};var result=await Create(proxy).Freeze(requestedCard,default);
        Assert.Equal(404,Assert.IsType<ObjectResult>(result.Result).StatusCode); Assert.Single(proxy.Requests);
    }
    [Fact]
    public async Task WidgetRequiresReverificationBeforeProviderCall()
    {
        var proxy=new Proxy();var verifier=new Verifier{Error=new("denied","Invalid password",403)};
        var response=await Create(proxy,verifier).Widget(42,new("test-secret",null),default);
        Assert.Equal(403,Assert.IsType<ObjectResult>(response.Result).StatusCode);Assert.Single(proxy.Requests);Assert.Equal(1,verifier.Calls);
    }
    [Fact]
    public async Task WidgetNeverForwardsPasswordAndIsNotCached()
    {
        var proxy=new Proxy();var controller=Create(proxy);
        await controller.Widget(42,new("test-secret","123456"),default);
        Assert.Equal("/api/v2/cards/42/widget",proxy.Requests.Last().Path);
        Assert.Equal(JsonValueKind.Null,proxy.Requests.Last().Body.ValueKind);
        Assert.Contains("no-store",controller.Response.Headers.CacheControl.ToString());
    }
    [Fact]
    public async Task ExplicitFeatureSwitchCanDisableLoadRequests()
    {
        var proxy=new Proxy();var response=await Create(proxy,enabled:false).RequestLoad(42,new(10,"Lunch"),default);
        Assert.Equal(501,Assert.IsType<ObjectResult>(response.Result).StatusCode);Assert.Single(proxy.Requests);
    }
    [Fact]
    public async Task DeployedCardholderFeaturesAreEnabledByDefault()
    {
        var response = await Create(new Proxy()).Cards(default);
        var data = Assert.IsType<JsonElement>(Assert.IsType<OkObjectResult>(response.Result).Value);
        Assert.True(data.GetProperty("capabilities").GetProperty("transactions").GetBoolean());
        Assert.True(data.GetProperty("capabilities").GetProperty("loadRequests").GetBoolean());
    }
    [Fact]
    public async Task UserHistoryAndRequestsKeepAssignedActorAndPayload()
    {
        var proxy=new Proxy();var controller=Create(proxy);
        await controller.Transactions(42,25,50,default);await controller.RequestLoad(42,new(50,"Lunch"),default);
        Assert.Equal("/api/v2/mor/public/users/101/cards/42/transactions",proxy.Requests[1].Path);
        Assert.Equal("50",proxy.Requests[1].Query["offset"]);
        Assert.Equal("/api/v2/mor/public/users/101/cards/42/load-requests",proxy.Requests[3].Path);
        Assert.Equal(50,proxy.Requests[3].Body.GetProperty("Amount").GetDecimal());
    }
    [Theory]
    [InlineData(0)] [InlineData(250001)]
    public void LoadRequestAmountIsBounded(decimal amount) { var body = new MorLoadRequest(amount,null); Assert.False(Validator.TryValidateObject(body,new ValidationContext(body),[],true)); }
    private static MorUserCardsController Create(Proxy proxy,Verifier? verifier=null,bool? enabled=null)
    {
        var config=new ConfigurationBuilder().AddInMemoryCollection(enabled is null ? new Dictionary<string,string?>() : new Dictionary<string,string?>{["Mor:UserTransactionsEnabled"]=enabled.Value.ToString(),["Mor:UserLoadRequestsEnabled"]=enabled.Value.ToString()}).Build();
        return new(proxy,config,verifier??new Verifier()){ControllerContext=new(){HttpContext=new DefaultHttpContext{User=new ClaimsPrincipal(new ClaimsIdentity([new("hoppa_user_id","101")],"test"))}}};
    }
    private sealed class Verifier : IMorCardRevealVerifier
    {
        public ApplicationError? Error {get;init;} public int Calls {get;private set;}
        public Task<ApplicationError?> Verify(ClaimsPrincipal user,string password,string? code,CancellationToken ct){Calls++;return Task.FromResult(Error);}
    }
    private sealed record Request(string Path,IReadOnlyDictionary<string,string?> Query,JsonElement Body);
    private sealed class Proxy : IProxyHoppaRequestUseCase
    {
        public int AssignedUser{get;init;}=101; public List<Request> Requests{get;}=[];
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command,CancellationToken ct)
        {
            Requests.Add(new(command.UpstreamPath,command.Query,JsonSerializer.SerializeToElement(command.Request)));
            var payload=command.UpstreamPath.EndsWith("/users/101/cards") ? JsonSerializer.SerializeToElement(new{cards=new[]{new{id=42,assignedUserId=AssignedUser}}}) : JsonSerializer.SerializeToElement(new{success=true});
            return Task.FromResult(ApplicationResult<JsonElement?>.Success(payload));
        }
    }
}
