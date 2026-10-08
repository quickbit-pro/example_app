using System.Net.Http;
using System.Reflection;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobileRewardsControllerTests
{
    [Fact]
    public async Task CommunityRoutesUseAuthenticatedUserAndClampPaging()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);
        controller.Request.QueryString = new QueryString("?userId=999&companyId=999&actorUserId=999");
        var program = Guid.NewGuid();
        await controller.Community(program, default);
        await controller.CommunityEarnings(program, 0, 1000, default);
        Assert.Equal("/api/v2/users/10466/referrals/community", proxy.Requests[0].Path);
        var earnings = proxy.Requests[1];
        Assert.Equal("/api/v2/users/10466/referrals/community/earnings", earnings.Path);
        Assert.Equal("1", earnings.Query["page"]);
        Assert.Equal("100", earnings.Query["pageSize"]);
        Assert.All(proxy.Requests, r => {
            Assert.Equal(program.ToString("D"), r.Query["programId"]);
            Assert.DoesNotContain("userId", r.Query.Keys);
            Assert.DoesNotContain("companyId", r.Query.Keys);
            Assert.DoesNotContain("actorUserId", r.Query.Keys);
        });
    }

    [Fact]
    public async Task SendReferralInvitation_ProxiesRecipientToHoppa()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);

        var response = await controller.SendReferralInvitation(
            new MobileRewardsController.ReferralInvitationRequest
            {
                RecipientEmail = " friend@example.test ",
                RecipientName = " Friend "
            },
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("/api/v2/users/10466/referrals/invitations", request.Path);
        Assert.Equal("friend@example.test", request.Body.GetProperty("RecipientEmail").GetString());
        Assert.Equal("Friend", request.Body.GetProperty("RecipientName").GetString());
    }

    [Fact]
    public async Task SendReferralInvitation_RejectsMissingEmail()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);

        var response = await controller.SendReferralInvitation(
            new MobileRewardsController.ReferralInvitationRequest(),
            CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status400BadRequest, problem.StatusCode);
        Assert.Empty(proxy.Requests);
    }

    [Fact]
    public async Task GetReferralRewards_ForwardsToRewardsWithPagingAndProgram()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);
        var programId = Guid.NewGuid();

        var response = await controller.GetReferralRewards(programId, 2, 500, CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Get, request.Method);
        Assert.Equal("/api/v2/users/10466/referrals/rewards", request.Path);
        Assert.Equal(programId.ToString("D"), request.Query["programId"]);
        Assert.Equal("2", request.Query["page"]);
        Assert.Equal("100", request.Query["pageSize"]);
    }

    [Fact]
    public async Task GetReferralCommissions_IsAnAliasOfRewards()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);

        var response = await controller.GetReferralCommissions(null, 0, 25, CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal("/api/v2/users/10466/referrals/rewards", request.Path);
        Assert.Null(request.Query["programId"]);
        Assert.Equal("1", request.Query["page"]);
        Assert.Equal("25", request.Query["pageSize"]);
    }

    [Fact]
    public async Task GetReferralFriends_ForwardsToFriends()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);

        var response = await controller.GetReferralFriends(null, 1, 10, CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Get, request.Method);
        Assert.Equal("/api/v2/users/10466/referrals/friends", request.Path);
        Assert.Equal("10", request.Query["pageSize"]);
    }

    [Fact]
    public async Task GetReferralAnalytics_ForwardsPeriodAndProgramToAnalytics()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);
        var programId = Guid.NewGuid();

        var response = await controller.GetReferralAnalytics(
            programId,
            " Month ",
            "2026-09-01T00:00:00Z",
            "2026-09-15T00:00:00Z",
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Get, request.Method);
        Assert.Equal("/api/v2/users/10466/referrals/analytics", request.Path);
        Assert.Equal(programId.ToString("D"), request.Query["programId"]);
        Assert.Equal("month", request.Query["range"]);
        Assert.Equal("2026-09-01T00:00:00Z", request.Query["from"]);
        Assert.Equal("2026-09-15T00:00:00Z", request.Query["to"]);

        // Blanks are dropped so the platform applies its own default period.
        proxy.Requests.Clear();
        await controller.GetReferralAnalytics(null, "", " ", null, CancellationToken.None);
        var defaulted = Assert.Single(proxy.Requests);
        Assert.All(defaulted.Query.Values, Assert.Null);
    }

    [Fact]
    public async Task AcceptReferralTerms_ForwardsTermsVersion()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);

        var response = await controller.AcceptReferralTerms(
            new MobileRewardsController.ReferralTermsAcceptanceRequest { TermsVersion = 3 },
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("/api/v2/users/10466/referrals/terms-acceptance", request.Path);
        Assert.Equal(3, request.Body.GetProperty("TermsVersion").GetInt32());
    }

    [Theory]
    [InlineData(null)]
    [InlineData(0)]
    public async Task AcceptReferralTerms_RejectsMissingVersion(int? termsVersion)
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);

        var response = await controller.AcceptReferralTerms(
            new MobileRewardsController.ReferralTermsAcceptanceRequest { TermsVersion = termsVersion },
            CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status400BadRequest, problem.StatusCode);
        Assert.Empty(proxy.Requests);
    }

    [Fact]
    public async Task GetCampaignLinks_ForwardsProgramAndStatus()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);
        var programId = Guid.NewGuid();

        var response = await controller.GetCampaignLinks(programId, " paused ", CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Get, request.Method);
        Assert.Equal("/api/v2/users/10466/referrals/links", request.Path);
        Assert.Equal(programId.ToString("D"), request.Query["programId"]);
        Assert.Equal("PAUSED", request.Query["status"]);

        proxy.Requests.Clear();
        await controller.GetCampaignLinks(null, "", CancellationToken.None);
        Assert.All(Assert.Single(proxy.Requests).Query.Values, Assert.Null);
    }

    [Fact]
    public async Task CreateCampaignLink_ForwardsTrimmedShape()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);
        var programId = Guid.NewGuid();
        var expires = new DateTimeOffset(2026, 12, 31, 0, 0, 0, TimeSpan.Zero);

        var response = await controller.CreateCampaignLink(
            new MobileRewardsController.CampaignLinkCreateRequest
            {
                ProgramId = programId,
                Name = " Autumn newsletter ",
                Code = " AUTUMN26 ",
                Channel = " Email ",
                Locale = "de",
                Destination = "",
                ExpiresAt = expires
            },
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("/api/v2/users/10466/referrals/links", request.Path);
        Assert.Equal(programId.ToString("D"), request.Body.GetProperty("ProgramId").GetString());
        Assert.Equal("Autumn newsletter", request.Body.GetProperty("Name").GetString());
        Assert.Equal("AUTUMN26", request.Body.GetProperty("Code").GetString());
        Assert.Equal("email", request.Body.GetProperty("Channel").GetString());
        Assert.Equal("de", request.Body.GetProperty("Locale").GetString());
        Assert.Equal(JsonValueKind.Null, request.Body.GetProperty("Destination").ValueKind);
        Assert.Equal(expires, request.Body.GetProperty("ExpiresAt").GetDateTimeOffset());
    }

    [Theory]
    [InlineData(null, "social")]
    [InlineData(" ", "social")]
    [InlineData("Launch", null)]
    [InlineData("Launch", "")]
    public async Task CreateCampaignLink_RejectsMissingNameOrChannel(string? name, string? channel)
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);

        var response = await controller.CreateCampaignLink(
            new MobileRewardsController.CampaignLinkCreateRequest { Name = name, Channel = channel },
            CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status400BadRequest, problem.StatusCode);
        Assert.Empty(proxy.Requests);
    }

    [Fact]
    public async Task UpdateCampaignLink_ForwardsStatusAndName()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);
        var linkId = Guid.NewGuid();

        var response = await controller.UpdateCampaignLink(
            linkId,
            new MobileRewardsController.CampaignLinkUpdateRequest { Status = " paused ", Name = " Renamed " },
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Patch, request.Method);
        Assert.Equal($"/api/v2/users/10466/referrals/links/{linkId:D}", request.Path);
        Assert.Equal("PAUSED", request.Body.GetProperty("Status").GetString());
        Assert.Equal("Renamed", request.Body.GetProperty("Name").GetString());
        Assert.Equal(JsonValueKind.Null, request.Body.GetProperty("ExpiresAt").ValueKind);
    }

    [Fact]
    public async Task UpdateCampaignLink_ClearsExpiryOnRequest()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);

        await controller.UpdateCampaignLink(
            Guid.NewGuid(),
            new MobileRewardsController.CampaignLinkUpdateRequest { ClearExpiresAt = true, ExpiresAt = DateTimeOffset.UtcNow },
            CancellationToken.None);

        var request = Assert.Single(proxy.Requests);
        Assert.True(request.Body.GetProperty("ClearExpiresAt").GetBoolean());
        Assert.Equal(JsonValueKind.Null, request.Body.GetProperty("ExpiresAt").ValueKind);
    }

    [Theory]
    [InlineData(409, """{"message":"That code is already in use.","code":"CAMPAIGN_CODE_TAKEN","status":409}""", "mobile.referrals.links.campaign_code_taken", "That code is already in use.")]
    [InlineData(400, """{"Message":"Name must be 1-80 characters.","Code":"CAMPAIGN_NAME_INVALID","Status":400}""", "mobile.referrals.links.campaign_name_invalid", "Name must be 1-80 characters.")]
    [InlineData(409, """{"message":"You already have 25 active links.","code":"CAMPAIGN_LINK_LIMIT"}""", "mobile.referrals.links.campaign_link_limit", "You already have 25 active links.")]
    public async Task CampaignLinkRuleBreaches_SurfaceThePlatformMessage(int status, string upstreamBody, string expectedCode, string expectedMessage)
    {
        var proxy = new RecordingProxy
        {
            Error = new ApplicationError("mobile.rewards.referrals.failed", "We could not process the referral request.", status, upstreamBody)
        };
        var controller = CreateController(proxy);

        var response = await controller.CreateCampaignLink(
            new MobileRewardsController.CampaignLinkCreateRequest { Name = "Autumn", Channel = "email" },
            CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(status, problem.StatusCode);
        var payload = JsonSerializer.Serialize(problem.Value);
        Assert.Contains(expectedCode, payload);
        Assert.Contains(expectedMessage, payload);
    }

    [Fact]
    public async Task OtherUpstreamFailures_PassThroughUnchanged()
    {
        var proxy = new RecordingProxy
        {
            Error = new ApplicationError("mobile.rewards.referrals.failed", "We could not process the referral request.", 503, "not json at all")
        };
        var controller = CreateController(proxy);

        var response = await controller.GetCampaignLinks(null, null, CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(503, problem.StatusCode);
        Assert.Contains("mobile.rewards.referrals.failed", JsonSerializer.Serialize(problem.Value));
    }

    [Fact]
    public async Task UpdateCampaignLink_ForwardsDestination()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);
        var linkId = Guid.NewGuid();

        var response = await controller.UpdateCampaignLink(
            linkId,
            new MobileRewardsController.CampaignLinkUpdateRequest { Destination = " Cards " },
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Patch, request.Method);
        Assert.Equal($"/api/v2/users/10466/referrals/links/{linkId:D}", request.Path);
        Assert.Equal("cards", request.Body.GetProperty("Destination").GetString());
        Assert.Equal(JsonValueKind.Null, request.Body.GetProperty("Status").ValueKind);
    }

    // ---- addendum A: campaign link clicks ----

    [Fact]
    public void RecordCampaignLinkClick_IsAnonymousLikeCheckReferral()
    {
        var method = typeof(MobileRewardsController).GetMethod(nameof(MobileRewardsController.RecordCampaignLinkClick))!;
        Assert.NotNull(method.GetCustomAttribute<AllowAnonymousAttribute>());
        Assert.Equal("referrals/links/{code}/clicks", method.GetCustomAttribute<HttpPostAttribute>()!.Template);
    }

    [Fact]
    public async Task RecordCampaignLinkClick_ForwardsVisitorLocaleAndUserAgentToTheCompanyRoute()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);
        controller.Request.Headers.UserAgent = "Mozilla/5.0 (Example test)";

        var response = await controller.RecordCampaignLinkClick(
            " autumn26 ",
            new MobileRewardsController.CampaignLinkClickRequest { VisitorId = " 3f7c1a9e-visitor ", Locale = "de" },
            CancellationToken.None);

        Assert.IsType<NoContentResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("/api/v2/referrals/links/AUTUMN26/clicks", request.Path);
        Assert.Equal("3f7c1a9e-visitor", request.Body.GetProperty("VisitorId").GetString());
        Assert.Equal("de", request.Body.GetProperty("Locale").GetString());
        Assert.Equal("Mozilla/5.0 (Example test)", request.Body.GetProperty("UserAgentHint").GetString());
    }

    [Fact]
    public async Task RecordCampaignLinkClick_WithoutVisitorSendsNullsAndTruncatesLongValues()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);
        controller.Request.Headers.UserAgent = new string('a', 300);

        var response = await controller.RecordCampaignLinkClick(
            "AUTUMN26",
            new MobileRewardsController.CampaignLinkClickRequest { VisitorId = new string('v', 80), Locale = "too-long-locale" },
            CancellationToken.None);

        Assert.IsType<NoContentResult>(response.Result);
        var body = Assert.Single(proxy.Requests).Body;
        Assert.Equal(64, body.GetProperty("VisitorId").GetString()!.Length);
        Assert.Equal(JsonValueKind.Null, body.GetProperty("Locale").ValueKind);
        Assert.Equal(256, body.GetProperty("UserAgentHint").GetString()!.Length);

        var bare = await CreateController(proxy).RecordCampaignLinkClick("AUTUMN26", null, CancellationToken.None);
        Assert.IsType<NoContentResult>(bare.Result);
        var bareBody = proxy.Requests[1].Body;
        Assert.Equal(JsonValueKind.Null, bareBody.GetProperty("VisitorId").ValueKind);
        Assert.Equal(JsonValueKind.Null, bareBody.GetProperty("UserAgentHint").ValueKind);
    }

    [Theory]
    [InlineData(" ")]
    [InlineData("abc")]
    [InlineData("bad code!")]
    [InlineData("a-code-that-is-far-too-long-for-a-campaign")]
    public async Task RecordCampaignLinkClick_RejectsCodesOutsideThePlatformRule(string code)
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);

        var response = await controller.RecordCampaignLinkClick(code, null, CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status400BadRequest, problem.StatusCode);
        Assert.Empty(proxy.Requests);
    }

    [Fact]
    public async Task RecordCampaignLinkClick_Answers204WhenThePlatformPredatesClicks()
    {
        var proxy = new RecordingProxy
        {
            Error = new ApplicationError("mobile.referrals.links.click_failed", "We could not record the visit.", StatusCodes.Status404NotFound)
        };
        var controller = CreateController(proxy);

        var response = await controller.RecordCampaignLinkClick("AUTUMN26", null, CancellationToken.None);

        Assert.IsType<NoContentResult>(response.Result);
        Assert.Single(proxy.Requests);
    }

    [Fact]
    public async Task RecordCampaignLinkClick_PassesOtherFailuresThrough()
    {
        var proxy = new RecordingProxy
        {
            Error = new ApplicationError("mobile.referrals.links.click_failed", "We could not record the visit.", 503)
        };
        var controller = CreateController(proxy);

        var response = await controller.RecordCampaignLinkClick("AUTUMN26", null, CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(503, problem.StatusCode);
    }

    [Fact]
    public async Task RecordCampaignLinkClick_Returns404WhenReferralsDisabled()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy, referralsEnabled: false);

        var response = await controller.RecordCampaignLinkClick("AUTUMN26", null, CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status404NotFound, problem.StatusCode);
        Assert.Empty(proxy.Requests);
    }

    [Fact]
    public async Task UpdateCampaignLink_RejectsEmptyChange()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);

        var response = await controller.UpdateCampaignLink(
            Guid.NewGuid(),
            new MobileRewardsController.CampaignLinkUpdateRequest(),
            CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status400BadRequest, problem.StatusCode);
        Assert.Empty(proxy.Requests);
    }

    [Fact]
    public async Task GetCampaignLinkPerformance_ForwardsRange()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);
        var linkId = Guid.NewGuid();

        var response = await controller.GetCampaignLinkPerformance(linkId, " ALL ", CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Get, request.Method);
        Assert.Equal($"/api/v2/users/10466/referrals/links/{linkId:D}/performance", request.Path);
        Assert.Equal("all", request.Query["range"]);
    }

    [Fact]
    public async Task CampaignLinkRoutes_Return404WhenReferralsDisabled()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy, referralsEnabled: false);

        var response = await controller.GetCampaignLinks(null, null, CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status404NotFound, problem.StatusCode);
        Assert.Empty(proxy.Requests);
    }

    [Fact]
    public async Task ReferralRoutes_Return404WhenReferralsDisabled()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy, referralsEnabled: false);

        var response = await controller.GetReferralFriends(null, 1, 25, CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status404NotFound, problem.StatusCode);
        Assert.Empty(proxy.Requests);
    }

    private static MobileRewardsController CreateController(RecordingProxy proxy, bool referralsEnabled = true)
    {
        var options = Options.Create(new CompanyOptions
        {
            Features = new CompanyFeatureOptions { ReferralsEnabled = referralsEnabled }
        });

        return new MobileRewardsController(proxy, options)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(
                        new ClaimsIdentity([new Claim("hoppa_user_id", "10466")], "test"))
                }
            }
        };
    }

    private sealed class RecordingProxy : IProxyHoppaRequestUseCase
    {
        public ApplicationError? Error { get; init; }
        public List<RecordedRequest> Requests { get; } = [];

        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(
            ProxyHoppaRequestCommand<TRequest> command,
            CancellationToken cancellationToken)
        {
            var body = command.Request is null
                ? default
                : JsonSerializer.SerializeToElement(command.Request);
            Requests.Add(new RecordedRequest(command.Method, command.UpstreamPath, body, command.Query));
            if (Error is not null)
            {
                return Task.FromResult(ApplicationResult<JsonElement?>.Failure(Error));
            }
            using var document = JsonDocument.Parse("""{"message":"Invitation sent"}""");
            return Task.FromResult(ApplicationResult<JsonElement?>.Success(
                document.RootElement.Clone()));
        }
    }

    private sealed record RecordedRequest(
        HttpMethod Method,
        string Path,
        JsonElement Body,
        IReadOnlyDictionary<string, string?> Query);
}
