using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using NeoBanking.Api.Mor;
using NeoBanking.Api.Auth;
using Microsoft.Extensions.DependencyInjection;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Security;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;
public sealed class MorAccessTests
{
    [Theory]
    [InlineData("white_label_admin_mor", "white_label_admin_mor", true)]
    [InlineData("user_simple", "user_simple", true)]
    [InlineData("user_simple", "white_label_admin_mor", false)]
    [InlineData("white_label_admin_mor", "user_simple", false)]
    [InlineData("white_label_admin", "white_label_admin_mor", false)]
    [InlineData("user", "user_simple", false)]
    public async Task RoleComesFromTenantMembershipNotLocalAdminClaims(string upstreamRole, string requiredRole, bool allowed)
    {
        var proxy = new MembershipProxy(upstreamRole);
        var handler = new MorRoleHandler(new(proxy));
        var requirement = new MorRoleRequirement(requiredRole);
        var caller = new ClaimsPrincipal(new ClaimsIdentity([new("hoppa_user_id","101"),new(ClaimTypes.Role,"admin")],"test"));
        var context = new AuthorizationHandlerContext([requirement], caller, null);
        await handler.HandleAsync(context);
        Assert.Equal(allowed,context.HasSucceeded);
        Assert.Equal(1,proxy.Calls);
    }
    [Theory]
    [InlineData(null)] [InlineData("0")] [InlineData("-1")] [InlineData("abc")]
    public async Task MissingLinkedIdentityCannotUseInstallationKey(string? id)
    {
        var proxy = new MembershipProxy("user_simple");
        var caller = new ClaimsPrincipal(new ClaimsIdentity(id is null ? [] : new[] {new Claim("hoppa_user_id",id)},"test"));
        var result = await new MorIdentityResolver(proxy).Resolve(caller,default);
        Assert.False(result.IsSuccess); Assert.Equal(0,proxy.Calls);
    }
    [Fact]
    public async Task UserOutsideInstallationCannotChooseAnotherCompany()
    {
        var caller = new ClaimsPrincipal(new ClaimsIdentity([new("hoppa_user_id","999")],"test"));
        var result = await new MorIdentityResolver(new MembershipProxy("user_simple")).Resolve(caller,default);
        Assert.False(result.IsSuccess); Assert.Equal(403,result.Error!.StatusCode);
    }
    [Fact]
    public async Task MembershipProviderFailureRemainsAnError()
    {
        var proxy = new MembershipProxy("user_simple") { Status=503 };
        var caller = new ClaimsPrincipal(new ClaimsIdentity([new("hoppa_user_id","101")],"test"));
        var result = await new MorIdentityResolver(proxy).Resolve(caller,default);
        Assert.False(result.IsSuccess); Assert.Equal(503,result.Error!.StatusCode);
    }
    [Fact]
    public async Task MorAdminAccessDoesNotGrantGeneralAdministration()
    {
        var services = new ServiceCollection();
        services.AddLogging(); services.AddNeoBankingAuthorization();
        services.AddSingleton<IProxyHoppaRequestUseCase>(new MembershipProxy("white_label_admin_mor"));
        using var provider = services.BuildServiceProvider(); using var scope = provider.CreateScope();
        var authorization = scope.ServiceProvider.GetRequiredService<IAuthorizationService>();
        var caller = new ClaimsPrincipal(new ClaimsIdentity([new("hoppa_user_id","101"), new("company_installation_id",Guid.NewGuid().ToString()), new(ClaimTypes.Role,ApplicationRoles.User)],"test"));
        Assert.True((await authorization.AuthorizeAsync(caller,null,AuthorizationPolicyNames.MorAdmin)).Succeeded);
        Assert.False((await authorization.AuthorizeAsync(caller,null,AuthorizationPolicyNames.MorUser)).Succeeded);
        Assert.False((await authorization.AuthorizeAsync(caller,null,AuthorizationPolicyNames.Admin)).Succeeded);
    }

    private sealed class MembershipProxy(string role) : IProxyHoppaRequestUseCase
    {
        public int Calls {get;private set;}
        public int Status {get;init;} = 200;
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command, CancellationToken ct)
        {
            Calls++; Assert.Equal("/api/v2/mor/public/transactions",command.UpstreamPath);
            Assert.Equal("1",command.Query["pageSize"]);
            return Task.FromResult(Status!=200 ? ApplicationResult<JsonElement?>.Failure(new("test","unavailable",Status)) :
                ApplicationResult<JsonElement?>.Success(JsonSerializer.SerializeToElement(new {users=new[]{new{userId=101,role,name="Card Holder",email="user@example.test"}}})));
        }
    }
}
