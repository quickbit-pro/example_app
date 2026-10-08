using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Company;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Auth;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Email;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AuthSignupReferralTests
{
    private const string Password = "Example-only-password!37";

    [Theory]
    [InlineData(true, "MANUAL_CODE", true)]
    [InlineData(true, "LINK", true)]
    [InlineData(null, "EMAIL_INVITATION", false)]
    [InlineData(false, "email_invitation", false)]
    [InlineData(null, "MANUAL_CODE", false)]
    [InlineData(false, "LINK", false)]
    [InlineData(null, null, false)]
    public void AcceptanceRule_SourceLabelCannotSupplyConsent(bool? accepted, string? source, bool expected)
    {
        Assert.Equal(expected, ReferralAttributionRules.IsAccepted(accepted, source));
    }

    [Theory]
    [InlineData("LINK", "LINK")]
    [InlineData(" link ", "LINK")]
    [InlineData("EMAIL_INVITATION", "EMAIL_INVITATION")]
    [InlineData("MANUAL_CODE", "MANUAL_CODE")]
    [InlineData("CAMPAIGN_LINK", "CAMPAIGN_LINK")]
    [InlineData("something-else", "MANUAL_CODE")]
    [InlineData(null, "MANUAL_CODE")]
    public void NormalizeSource_OnlyPassesKnownSources(string? value, string expected)
    {
        Assert.Equal(expected, ReferralAttributionRules.NormalizeSource(value));
    }

    [Fact]
    public async Task Signup_WithoutAcceptance_SkipsAttributionButCreatesAccount()
    {
        await using var db = CreateDatabase();
        await SeedDefaultCompany(db);
        var proxy = new RecordingProxy();
        var controller = CreateController(db, proxy);

        var response = await controller.Signup(
            SignupRequest(referralCode: "FRIEND1", referralSource: "LINK", referralAccepted: null, termsVersion: 2),
            CancellationToken.None);

        var created = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status201Created, created.StatusCode);
        var payload = JsonSerializer.SerializeToElement(created.Value);
        Assert.False(payload.GetProperty("referralAttributed").GetBoolean());
        Assert.Equal("auth.referral.not_accepted", payload.GetProperty("referralAttributionReason").GetString());
        Assert.DoesNotContain(proxy.Requests, request => request.Path.EndsWith("/referrals/attribution"));
        Assert.Contains(proxy.Requests, request => request.Path == "/api/v2/users/check-referral");
        Assert.Equal(1, await db.Users.CountAsync());
    }

    [Theory]
    [InlineData("LINK", "SIGNUP")]
    [InlineData("MANUAL_CODE", "SIGNUP")]
    [InlineData("EMAIL_INVITATION", "EMAIL_INVITATION")]
    public async Task Signup_WithAcceptedQuote_CommitsPendingIntentWithUserAndMapping(string source, string provenance)
    {
        await using var db=CreateDatabase(); await SeedDefaultCompany(db);
        var proxy=new RecordingProxy(); var controller=CreateController(db,proxy);
        var attempt=await Quote(controller,source);
        var response=await controller.Signup(AcceptedRequest(attempt,source),default);
        var created=Assert.IsType<ObjectResult>(response.Result); Assert.Equal(201,created.StatusCode);
        var body=JsonSerializer.SerializeToElement(created.Value);
        Assert.False(body.GetProperty("referralAttributed").GetBoolean());
        Assert.Equal("PENDING",body.GetProperty("referralAttributionStatus").GetString());
        var intent=Assert.Single(await db.ReferralAttributionIntents.Where(x=>x.Kind=="ATTRIBUTION").ToListAsync());
        Assert.Equal((await db.Users.SingleAsync()).Id,intent.UserId);
        Assert.Equal("777",intent.ProviderUserId); Assert.Equal(attempt,intent.SignupAttemptId);
        using var payload=JsonDocument.Parse(intent.PayloadJson);
        Assert.True(payload.RootElement.GetProperty("accepted").GetBoolean());
        // The engine binds DateTime and requires Kind.Utc. A DateTimeOffset
        // serialized with +00:00 instead of Z binds as Local and is rejected.
        var received = payload.RootElement.GetProperty("consentReceivedAt");
        Assert.Equal(DateTimeKind.Utc, received.GetDateTime().Kind);
        Assert.EndsWith("Z", received.GetString());
        Assert.Equal(provenance, payload.RootElement.GetProperty("provenance").GetString());
        Assert.Equal("terms-hash",payload.RootElement.GetProperty("termsHash").GetString());
        Assert.Equal("ACCOUNT_CREATED",(await db.ReferralSignupAttempts.SingleAsync()).State);
        Assert.DoesNotContain(proxy.Requests,x=>x.Path.Contains("attribution-commands")||x.Path.EndsWith("/attribution"));
    }

    [Fact]
    public async Task Signup_AcceptedWithoutQuote_CreatesAccountWithUnsentReviewIntent()
    {
        await using var db=CreateDatabase(); await SeedDefaultCompany(db); var proxy=new RecordingProxy();
        var response=await CreateController(db,proxy).Signup(SignupRequest("FRIEND1","LINK",true,1),default);
        Assert.Equal(201,Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Single(await db.Users.ToListAsync());
        var intent=Assert.Single(await db.ReferralAttributionIntents.Where(x=>x.Kind=="ATTRIBUTION").ToListAsync());
        Assert.Equal("NEEDS_REVIEW",intent.State); Assert.Equal("{}",intent.PayloadJson);
        Assert.DoesNotContain(proxy.Requests,x=>x.Path.Contains("attribution-commands"));
    }

    [Fact]
    public async Task Signup_SourceLabelCannotManufactureInvitationConsent()
    {
        await using var db=CreateDatabase(); await SeedDefaultCompany(db); var proxy=new RecordingProxy();
        var response=await CreateController(db,proxy).Signup(SignupRequest("FRIEND1","EMAIL_INVITATION",null,null),default);
        Assert.Equal(201,Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Empty(await db.ReferralAttributionIntents.Where(x=>x.Kind=="ATTRIBUTION").ToListAsync());
    }

    [Fact]
    public async Task Signup_LostUpstreamResponse_RetainsUncertainJournalAndPreventsRetry()
    {
        await using var db=CreateDatabase(); await SeedDefaultCompany(db);
        var proxy=new RecordingProxy{CreateThrows=true}; var controller=CreateController(db,proxy);
        var attempt=await Quote(controller,"LINK");
        var response=await controller.Signup(AcceptedRequest(attempt,"LINK"),default);
        Assert.Equal(409,Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Equal("CREATION_UNCERTAIN",(await db.ReferralSignupAttempts.SingleAsync()).State);
        Assert.Empty(await db.Users.ToListAsync());
        await controller.Signup(AcceptedRequest(attempt,"LINK"),default);
        Assert.Single(proxy.Requests,x=>x.Path=="/api/v2/users");
    }

    [Fact]
    public async Task Quote_RetryReturnsIdenticalTerms_ChangedPayloadConflicts()
    {
        await using var db=CreateDatabase(); await SeedDefaultCompany(db);var proxy=new RecordingProxy();var c=CreateController(db,proxy);
        var attempt=await Quote(c,"LINK");
        var retry=await c.ReferralQuote(new(){RegistrationAttemptId=attempt,ReferralCode="FRIEND1",Source="LINK"},default);
        Assert.IsType<OkObjectResult>(retry.Result);
        var conflict=await c.ReferralQuote(new(){RegistrationAttemptId=attempt,ReferralCode="OTHER",Source="LINK"},default);
        Assert.IsType<ConflictObjectResult>(conflict.Result);
        Assert.Single(proxy.Requests,x=>x.Path=="/api/v2/referral-attribution-quotes");
    }

    private static async Task<Guid> Quote(AuthController c,string source)
    {
        var id=Guid.NewGuid();
        Assert.IsType<OkObjectResult>((await c.ReferralQuote(new(){RegistrationAttemptId=id,ReferralCode="FRIEND1",Source=source},default)).Result);
        return id;
    }
    private static SignupRequestDto AcceptedRequest(Guid attempt,string source) => new()
    {
        Email="new-member@example.test",Password=Password,FirstName="New",LastName="Member",ReferralCode="FRIEND1",
        ReferralSource=source,ReferralAccepted=true,RegistrationAttemptId=attempt,
        ReferralQuoteId=Guid.Parse("22222222-2222-2222-2222-222222222222"),ReferralTermsHash="terms-hash",ReferralPolicyHash="policy-hash"
    };

    [Fact]
    public async Task CheckReferral_PassesThroughWelcomeAndTermsFields()
    {
        await using var db = CreateDatabase();
        var proxy = new RecordingProxy();
        var controller = CreateController(db, proxy);

        var response = await controller.CheckReferral(" FRIEND1 ", CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);
        var payload = JsonSerializer.SerializeToElement(ok.Value);
        Assert.True(payload.GetProperty("valid").GetBoolean());
        Assert.Equal("PERSONAL", payload.GetProperty("kind").GetString());
        Assert.Equal("Alex", payload.GetProperty("inviterDisplayName").GetString());
        Assert.Equal(3m, payload.GetProperty("welcomeAmount").GetDecimal());
        Assert.Equal("USD", payload.GetProperty("welcomeCurrency").GetString());
        Assert.Equal(2, payload.GetProperty("termsVersion").GetInt32());
        var request = Assert.Single(proxy.Requests);
        Assert.Equal("/api/v2/users/check-referral", request.Path);
        Assert.Equal("FRIEND1", request.Query["referralCode"]);
    }

    [Fact]
    public async Task CheckReferral_PassesThroughACampaignLinkDestinationAndOmitsItForPersonalCodes()
    {
        await using var db = CreateDatabase();
        var proxy = new RecordingProxy
        {
            CheckReferralBody = """{"Valid":true,"Kind":"CAMPAIGN_LINK","InviterDisplayName":"Maja","WelcomeAmount":3,"WelcomeCurrency":"USD","TermsVersion":2,"Destination":"Cards"}"""
        };
        var controller = CreateController(db, proxy);

        var response = await controller.CheckReferral("AUTUMN26", CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);
        var payload = JsonSerializer.SerializeToElement(ok.Value);
        Assert.Equal("CAMPAIGN_LINK", payload.GetProperty("kind").GetString());
        Assert.Equal("cards", payload.GetProperty("destination").GetString());

        var personal = await CreateController(db, new RecordingProxy()).CheckReferral("FRIEND1", CancellationToken.None);
        var personalPayload = JsonSerializer.SerializeToElement(Assert.IsType<OkObjectResult>(personal.Result).Value);
        Assert.Equal(JsonValueKind.Null, personalPayload.GetProperty("destination").ValueKind);
    }

    [Theory]
    [InlineData("""{"code":"CAMPAIGN_LINK_INACTIVE","message":"Link paused"}""")]
    [InlineData("""{"type":"https://api/problems/CAMPAIGN_LINK_INACTIVE","status":400}""")]
    public async Task CheckReferral_ReportsInactiveCampaignLinkAsItsOwnError(string upstreamBody)
    {
        await using var db = CreateDatabase();
        var proxy = new RecordingProxy
        {
            CheckReferralError = new ApplicationError("auth.referral.validation_failed", "We could not validate the referral code.", StatusCodes.Status400BadRequest, upstreamBody)
        };
        var controller = CreateController(db, proxy);

        var response = await controller.CheckReferral("AUTUMN26", CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status400BadRequest, problem.StatusCode);
        var payload = JsonSerializer.Serialize(problem.Value);
        Assert.Contains(AuthController.CampaignLinkInactiveCode, payload);
        Assert.Contains("CAMPAIGN_LINK_INACTIVE", payload);
        Assert.Contains("no longer active", payload);
    }

    [Fact]
    public async Task CheckReferral_KeepsOtherUpstreamFailures()
    {
        await using var db = CreateDatabase();
        var proxy = new RecordingProxy
        {
            CheckReferralError = new ApplicationError("auth.referral.validation_failed", "We could not validate the referral code.", StatusCodes.Status404NotFound, """{"code":"REFERRAL_CODE_UNKNOWN"}""")
        };
        var controller = CreateController(db, proxy);

        var response = await controller.CheckReferral("NOPE", CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status404NotFound, problem.StatusCode);
        Assert.DoesNotContain(AuthController.CampaignLinkInactiveCode, JsonSerializer.Serialize(problem.Value));
    }

    [Fact]
    public async Task CheckReferral_RejectsMissingCode()
    {
        await using var db = CreateDatabase();
        var proxy = new RecordingProxy();
        var controller = CreateController(db, proxy);

        var response = await controller.CheckReferral("  ", CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status400BadRequest, problem.StatusCode);
        Assert.Empty(proxy.Requests);
    }

    private static SignupRequestDto SignupRequest(string referralCode, string? referralSource, bool? referralAccepted, int? termsVersion) => new()
    {
        Email = "new-member@example.test",
        Password = Password,
        FirstName = "New",
        LastName = "Member",
        ReferralCode = referralCode,
        ReferralSource = referralSource,
        ReferralAccepted = referralAccepted,
        ReferralTermsVersion = termsVersion
    };

    private static NeoBankingDbContext CreateDatabase() => new(
        new DbContextOptionsBuilder<NeoBankingDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    private static async Task SeedDefaultCompany(NeoBankingDbContext db)
    {
        db.CompanyInstallations.Add(new CompanyInstallation { Slug = "default", DisplayName = "Test", LegalName = "Test" });
        await db.SaveChangesAsync();
    }

    private static AuthController CreateController(NeoBankingDbContext db, RecordingProxy proxy)
    {
        var controller = new AuthController(db, new PasswordHasher<ApplicationUser>(), proxy,
            Options.Create(new JwtOptions { Issuer = "test", Audience = "test", SigningKey = "test-only-signing-key-with-at-least-32-characters" }),
            Options.Create(new CompanyOptions { Features = new CompanyFeatureOptions { ReferralsEnabled = true } }),
            Options.Create(new EmailOptions { RequireVerifiedEmailForLogin = false }),
            null!, new LoginAttemptTracker(), NullLogger<AuthController>.Instance);
        controller.ControllerContext = new() { HttpContext = new DefaultHttpContext() };
        return controller;
    }

    /// <summary>Answers the three platform calls made during sign-up; records everything.</summary>
    private sealed class RecordingProxy : IProxyHoppaRequestUseCase
    {
        public bool CreateThrows { get; init; }
        public ApplicationError? AttributionError { get; init; }
        public ApplicationError? CheckReferralError { get; init; }

        /// <summary>Overrides the platform's check-referral answer (addendum A: campaign links carry a destination).</summary>
        public string? CheckReferralBody { get; init; }
        public List<RecordedRequest> Requests { get; } = [];

        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(
            ProxyHoppaRequestCommand<TRequest> command,
            CancellationToken cancellationToken)
        {
            var body = command.Request is null ? default : JsonSerializer.SerializeToElement(command.Request);
            Requests.Add(new RecordedRequest(command.Method, command.UpstreamPath, body, command.Query));

            if (command.UpstreamPath.EndsWith("/referrals/attribution") && AttributionError is not null)
            {
                return Task.FromResult(ApplicationResult<JsonElement?>.Failure(AttributionError));
            }

            if (command.UpstreamPath == "/api/v2/users/check-referral" && CheckReferralError is not null)
            {
                return Task.FromResult(ApplicationResult<JsonElement?>.Failure(CheckReferralError));
            }

            if(command.UpstreamPath=="/api/v2/users" && CreateThrows) throw new HttpRequestException("lost response");
            var json = command.UpstreamPath switch
            {
                "/api/v2/referral-attribution-quotes" => JsonSerializer.Serialize(new {quoteId="22222222-2222-2222-2222-222222222222",termsHash="terms-hash",policyHash="policy-hash",expiresAt=DateTimeOffset.UtcNow.AddMinutes(15)}),
                "/api/v2/users/check-referral" => CheckReferralBody ??
                    """{"valid":true,"kind":"PERSONAL","inviterDisplayName":"Alex","provider":"INTERLACE","welcomeAmount":3,"welcomeCurrency":"USD","termsVersion":2}""",
                "/api/v2/users" => """{"id":777,"email":"new-member@example.test"}""",
                _ => """{"ok":true}"""
            };
            using var document = JsonDocument.Parse(json);
            return Task.FromResult(ApplicationResult<JsonElement?>.Success(document.RootElement.Clone()));
        }
    }

    private sealed record RecordedRequest(
        HttpMethod Method,
        string Path,
        JsonElement Body,
        IReadOnlyDictionary<string, string?> Query);
}
