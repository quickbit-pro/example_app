using System.Reflection;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AdminReferralsControllerTests
{
    [Fact]
    public async Task CommunityRoutesDoNotForwardUntrustedScopeOrActorQueries()
    {
        var proxy = new RecordingProxy(); var controller = Create(proxy);
        controller.Request.QueryString = new QueryString("?companyId=999&apiKey=untrusted&actorUserId=999");
        controller.HttpContext.User = new System.Security.Claims.ClaimsPrincipal(new System.Security.Claims.ClaimsIdentity(new[]
        { new System.Security.Claims.Claim(System.Security.Claims.ClaimTypes.NameIdentifier, "local-admin") }, "test"));
        controller.Request.Headers["X-Referral-Actor"] = "spoofed";
        var id = Guid.NewGuid();
        var policy = JsonSerializer.SerializeToElement(new { Enabled = true, Revision = 0, LeaderL2Bps = 1500 });
        var member = JsonSerializer.SerializeToElement(new { Plan = "COMMUNITY", ParentUserId = 321 });
        var revoke = JsonSerializer.SerializeToElement(new { Reason = "Agreement ended" });
        await controller.CommunityPolicy(id, default);
        await controller.UpdateCommunityPolicy(id, policy, default);
        await controller.CommunityMembers(id, default);
        await controller.EnableCommunity(id, 123, member, default);
        await controller.RevokeCommunity(id, 123, revoke, default);
        Assert.Equal(new[] { "GET policy", "PUT policy", "GET members", "POST members/123/enable", "POST members/123/revoke" },
            proxy.Requests.Select(r => $"{r.Method} {r.Path.Replace($"/api/v2/referrals/programs/{id:D}/community/", "")}"));
        Assert.All(proxy.Requests, r => {
            Assert.Equal("local-admin", r.Actor);
            Assert.All(r.Query.Values, Assert.Null);
            Assert.DoesNotContain("companyId", r.Query.Keys);
            Assert.DoesNotContain("apiKey", r.Query.Keys);
            Assert.DoesNotContain("actorUserId", r.Query.Keys);
        });
        Assert.Equal(1500, proxy.Requests[1].Body.GetProperty("LeaderL2Bps").GetInt32());
        Assert.Equal(321, proxy.Requests[3].Body.GetProperty("ParentUserId").GetInt32());
        Assert.Equal("Agreement ended", proxy.Requests[4].Body.GetProperty("Reason").GetString());
    }

    [Fact]
    public void AllReferralActionsRequireAdminPolicy()
    {
        var type = typeof(AdminReferralsController);
        Assert.Equal(AuthorizationPolicyNames.Admin, type.GetCustomAttribute<AuthorizeAttribute>()!.Policy);
        Assert.DoesNotContain(type.GetMethods(), m => m.GetCustomAttribute<AllowAnonymousAttribute>() != null);
    }

    [Fact]
    public async Task RoutesUseOnlyPublicReferralApiAndDeclaredQueries()
    {
        var proxy = new RecordingProxy(); var controller = Create(proxy);
        controller.Request.QueryString = new QueryString("?companyId=999&apiKey=untrusted&actorUserId=999");
        var id = Guid.NewGuid(); var body = JsonSerializer.SerializeToElement(new { Revision = 3, Status = "PAUSED" });
        await controller.Programs(default); await controller.Program(id, default); await controller.Overview(null, default);
        await controller.Create(body, default); await controller.Update(id, body, default);
        await controller.InviteBenefits(id, default); await controller.UpdateInviteBenefit(id, body, default);
        await controller.Members(id, default); await controller.Member(id, 123, body, default);
        await controller.Options("person@example.test", default);
        Assert.Equal(new[] { "GET programs", "GET program", "GET overview", "POST programs", "PUT program", "GET invite-benefits", "PUT invite-benefits", $"GET programs/{id:D}/members", $"PUT programs/{id:D}/members/123", "GET options" },
            proxy.Requests.Select(r => $"{r.Method} {r.Path.Replace("/api/v2/referrals/", "")}"));
        Assert.All(proxy.Requests, r => {
            Assert.StartsWith("/api/v2/referrals/", r.Path);
            Assert.DoesNotContain("companyId", r.Query.Keys);
            Assert.DoesNotContain("apiKey", r.Query.Keys);
        });
        Assert.Equal(id.ToString(), proxy.Requests[4].Query["programId"]);
        Assert.Equal(3, proxy.Requests[4].Body.GetProperty("Revision").GetInt32());
        Assert.Equal("PAUSED", proxy.Requests[4].Body.GetProperty("Status").GetString());
        Assert.Null(proxy.Requests[2].Query["programId"]);
        Assert.Equal("person@example.test", proxy.Requests[9].Query["search"]);
    }

    [Fact]
    public async Task V2ResourcesForwardWithDeclaredQueries()
    {
        var proxy = new RecordingProxy(); var controller = Create(proxy);
        controller.Request.QueryString = new QueryString("?companyId=999&apiKey=untrusted");
        var program = Guid.NewGuid(); var credit = Guid.NewGuid();
        var assignment = JsonSerializer.SerializeToElement(new { LevelId = Guid.NewGuid(), Active = true });
        var cancel = JsonSerializer.SerializeToElement(new { Reason = "Duplicate" });
        var from = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero); var to = new DateTimeOffset(2026, 3, 1, 0, 0, 0, TimeSpan.Zero);
        await controller.MemberReport(program, 123, default);
        await controller.LevelAssignments(program, default); await controller.LevelAssignment(program, 123, assignment, default);
        await controller.Rewards(program, "READY", "REFERRER", "CARD_TOPUP", 2, 1000, default);
        await controller.Metrics(program, from, to, default);
        await controller.Credits("FAILED", 0, 20, default);
        await controller.RetryCredit(credit, default); await controller.CancelCredit(credit, cancel, default);
        await controller.Reconciliation(default);
        Assert.Equal(new[] { $"GET programs/{program:D}/members/123/report", $"GET programs/{program:D}/level-assignments", $"PUT programs/{program:D}/level-assignments/123",
                "GET rewards", "GET metrics", "GET credits", $"POST credits/{credit:D}/retry", $"POST credits/{credit:D}/cancel", "GET reconciliation" },
            proxy.Requests.Select(r => $"{r.Method} {r.Path.Replace("/api/v2/referrals/", "")}"));
        Assert.All(proxy.Requests, r => {
            Assert.StartsWith("/api/v2/referrals/", r.Path);
            Assert.DoesNotContain("companyId", r.Query.Keys);
            Assert.DoesNotContain("apiKey", r.Query.Keys);
        });
        var rewards = proxy.Requests[3].Query;
        Assert.Equal(program.ToString(), rewards["programId"]); Assert.Equal("READY", rewards["status"]); Assert.Equal("REFERRER", rewards["beneficiaryRole"]);
        Assert.Equal("CARD_TOPUP", rewards["eventType"]); Assert.Equal("2", rewards["page"]); Assert.Equal("500", rewards["pageSize"]);
        var metrics = proxy.Requests[4].Query;
        Assert.Equal(program.ToString(), metrics["programId"]); Assert.Equal(from.ToString("O"), metrics["from"]); Assert.Equal(to.ToString("O"), metrics["to"]);
        var credits = proxy.Requests[5].Query;
        Assert.Equal("FAILED", credits["status"]); Assert.Equal("1", credits["page"]); Assert.Equal("20", credits["pageSize"]);
        Assert.Equal(assignment.GetProperty("LevelId").GetString(), proxy.Requests[2].Body.GetProperty("LevelId").GetString());
        Assert.Equal("Duplicate", proxy.Requests[7].Body.GetProperty("Reason").GetString());
    }

    [Fact]
    public async Task AnalyticsForwardsWithDeclaredQueries()
    {
        var proxy = new RecordingProxy(); var controller = Create(proxy);
        controller.Request.QueryString = new QueryString("?companyId=999&apiKey=untrusted");
        var program = Guid.NewGuid();
        var from = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero); var to = new DateTimeOffset(2026, 3, 31, 23, 59, 59, TimeSpan.Zero);
        await controller.Analytics(program, from, to, 25, default);
        await controller.Analytics(null, null, null, 0, default);
        await controller.Analytics(null, null, null, 5000, default);
        Assert.Equal(new[] { "GET analytics", "GET analytics", "GET analytics" }, proxy.Requests.Select(r => $"{r.Method} {r.Path.Replace("/api/v2/referrals/", "")}"));
        Assert.All(proxy.Requests, r => {
            Assert.StartsWith("/api/v2/referrals/", r.Path);
            Assert.DoesNotContain("companyId", r.Query.Keys);
            Assert.DoesNotContain("apiKey", r.Query.Keys);
            Assert.Equal(new[] { "from", "programId", "to", "top" }, r.Query.Keys.OrderBy(k => k));
        });
        var filtered = proxy.Requests[0].Query;
        Assert.Equal(program.ToString(), filtered["programId"]); Assert.Equal(from.ToString("O"), filtered["from"]); Assert.Equal(to.ToString("O"), filtered["to"]); Assert.Equal("25", filtered["top"]);
        var defaults = proxy.Requests[1].Query;
        Assert.Null(defaults["programId"]); Assert.Null(defaults["from"]); Assert.Null(defaults["to"]); Assert.Equal("1", defaults["top"]);
        Assert.Equal("100", proxy.Requests[2].Query["top"]);
    }

    [Fact]
    public async Task CampaignLinksForwardWithDeclaredQueriesAndStatusOnly()
    {
        var proxy = new RecordingProxy(); var controller = Create(proxy);
        controller.Request.QueryString = new QueryString("?companyId=999&apiKey=untrusted");
        var program = Guid.NewGuid(); var link = Guid.NewGuid();
        var body = JsonSerializer.SerializeToElement(new { Status = "PAUSED" });
        await controller.Links(program, 123, " active ", default);
        await controller.Links(null, 0, null, default);
        await controller.UpdateLink(link, body, default);
        await controller.LinkPerformance(link, " ALL ", default);
        await controller.LinkPerformance(link, null, default);
        Assert.Equal(new[] { "GET links", "GET links", $"PATCH links/{link:D}", $"GET links/{link:D}/performance", $"GET links/{link:D}/performance" },
            proxy.Requests.Select(r => $"{r.Method} {r.Path.Replace("/api/v2/referrals/", "")}"));
        Assert.All(proxy.Requests, r => {
            Assert.StartsWith("/api/v2/referrals/", r.Path);
            Assert.DoesNotContain("companyId", r.Query.Keys);
            Assert.DoesNotContain("apiKey", r.Query.Keys);
        });
        var filtered = proxy.Requests[0].Query;
        Assert.Equal(program.ToString(), filtered["programId"]); Assert.Equal("123", filtered["ownerUserId"]); Assert.Equal("ACTIVE", filtered["status"]);
        Assert.All(proxy.Requests[1].Query.Values, value => Assert.Null(value));
        Assert.Equal("PAUSED", proxy.Requests[2].Body.GetProperty("Status").GetString());
        // Addendum A: the period token is the only query; the platform scopes the link to the company.
        Assert.Equal("all", proxy.Requests[3].Query["range"]);
        Assert.Null(proxy.Requests[4].Query["range"]);
        Assert.DoesNotContain("ownerUserId", proxy.Requests[3].Query.Keys);
    }

    [Theory]
    [InlineData(401)] [InlineData(403)] [InlineData(404)] [InlineData(409)] [InlineData(422)]
    public async Task UpstreamFailureIsNotReportedAsSaved(int status)
    {
        var proxy = new RecordingProxy { Error = new("provider.rejected", "Save rejected", status, "PROGRAM_CHANGED") };
        var response = await Create(proxy).Update(Guid.NewGuid(), JsonSerializer.SerializeToElement(new { Revision = 1 }), default);
        var result = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(status, result.StatusCode);
        Assert.Contains("PROGRAM_CHANGED", JsonSerializer.Serialize(result.Value));
    }


    [Fact]
    public async Task VersionedBuildRoutesKeepTenantScopeOnTheServer()
    {
        var proxy = new RecordingProxy(); var c = Create(proxy);
        c.Request.QueryString = new QueryString("?companyId=999&actorUserId=999&apiKey=untrusted");
        var p = Guid.NewGuid(); var d = Guid.NewGuid();
        var body = JsonSerializer.SerializeToElement(new { PreviewHash = "review", IdempotencyKey = "publish", Reason = "New offer" });
        await c.Capabilities(default); await c.Simulate(p, body, default); await c.Versions(p, default);
        await c.Draft(p, body, default); await c.UpdateDraft(p, d, body, default);
        await c.Preview(p, d, body, default); await c.Publish(p, d, body, default);
        await c.Team(p, default); await c.Parent(p, 10, 11, default);
        Assert.Equal(new[] { "GET capabilities", $"POST programs/{p:D}/simulate", $"GET programs/{p:D}/versions",
            $"POST programs/{p:D}/drafts", $"PUT programs/{p:D}/drafts/{d:D}", $"POST programs/{p:D}/drafts/{d:D}/change-preview",
            $"POST programs/{p:D}/drafts/{d:D}/publish", $"GET programs/{p:D}/team", $"PUT programs/{p:D}/team/10/11" },
            proxy.Requests.Select(r => $"{r.Method} {r.Path.Replace("/api/v2/referrals/", "")}"));
        Assert.All(proxy.Requests, r => {
            Assert.DoesNotContain("companyId", r.Query.Keys); Assert.DoesNotContain("actorUserId", r.Query.Keys);
            Assert.DoesNotContain("apiKey", r.Query.Keys); Assert.All(r.Query.Values, value => Assert.Null(value));
        });
        Assert.Equal("publish", proxy.Requests[6].Body.GetProperty("IdempotencyKey").GetString());
    }

    [Fact]
    public async Task FeedbackRoutesForwardAllowedFiltersAndOnlyAuthenticatedActor()
    {
        var proxy=new RecordingProxy();var c=Create(proxy);var p=Guid.NewGuid();var relation=Guid.NewGuid();var review=Guid.NewGuid();
        c.HttpContext.User=new System.Security.Claims.ClaimsPrincipal(new System.Security.Claims.ClaimsIdentity(new[]
        {new System.Security.Claims.Claim(System.Security.Claims.ClaimTypes.NameIdentifier,"local-admin")},"test"));
        c.Request.Headers["X-Referral-Actor"]="spoofed";
        c.Request.QueryString=new("?companyId=999&actorId=spoofed&apiKey=secret");
        await c.Relationships(p,"friend","TOPUP","LINK",1,2,99,1000,default);
        await c.Relationship(relation,default);await c.Reviews(p,"FLAGGED",1,50,default);
        await c.ReviewDecision(review,JsonSerializer.SerializeToElement(new{decision="APPROVE",expectedRevision=1,idempotencyKey="same"}),default);
        await c.LevelLifecycle(p,1,default);await c.GeoPolicy(p,default);await c.BoostCapabilities(p,default);
        await c.AttributionReadiness(p,default);await c.AlertSettings(default);
        Assert.Equal("local-admin",proxy.Requests[3].Actor);
        Assert.All(proxy.Requests,x=>{Assert.DoesNotContain("companyId",x.Query.Keys);Assert.DoesNotContain("apiKey",x.Query.Keys);});
        Assert.Equal("200",proxy.Requests[0].Query["pageSize"]);
        Assert.Equal("99",proxy.Requests[0].Query["afterId"]);
        Assert.Equal("friend",proxy.Requests[0].Query["search"]);
        Assert.EndsWith($"reviews/{review:D}/decisions",proxy.Requests[3].Path);
    }

    private static AdminReferralsController Create(RecordingProxy proxy) => new(proxy) {
        ControllerContext = new() { HttpContext = new DefaultHttpContext() }
    };
    private sealed class RecordingProxy : IProxyHoppaRequestUseCase
    {
        public ApplicationError? Error { get; init; }
        public List<Recorded> Requests { get; } = [];
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(ProxyHoppaRequestCommand<TRequest> command, CancellationToken ct)
        {
            Requests.Add(new(command.Method, command.UpstreamPath, command.Query, JsonSerializer.SerializeToElement(command.Request),command.TrustedReferralActorId));
            return Task.FromResult(Error is null ? ApplicationResult<JsonElement?>.Success(JsonSerializer.SerializeToElement(new { Revision = 4 })) : ApplicationResult<JsonElement?>.Failure(Error));
        }
    }
    private sealed record Recorded(HttpMethod Method, string Path, IReadOnlyDictionary<string, string?> Query, JsonElement Body,string? Actor);
}
