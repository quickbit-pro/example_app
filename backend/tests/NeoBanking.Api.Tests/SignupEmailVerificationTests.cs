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
using NeoBanking.Api.Email;
using NeoBanking.Application.Common;
using NeoBanking.Application.Company;
using NeoBanking.Application.DTOs.Auth;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Email;
using NeoBanking.Infrastructure.Persistence;
using NeoBanking.Infrastructure.Security;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class SignupEmailVerificationTests
{
    private const string Email = "new@example.test";

    [Fact]
    public async Task RequestCode_CreatesOnlyPendingPlaceholderAndMail_NoIdentitySessionOrUpstreamUser()
    {
        await using var db = await Database(); var proxy = new Proxy();
        var result = await Controller(db, proxy).RequestSignupEmailCode(new() { Email = Email }, default);
        Assert.IsType<AcceptedResult>(result.Result);
        var user = await db.Users.SingleAsync();
        Assert.Equal("pending_signup", user.Status);
        Assert.Null(user.EmailVerifiedAt);
        Assert.Empty(await db.UserIdentities.ToListAsync());
        Assert.Empty(await db.RefreshSessions.ToListAsync());
        Assert.Empty(await db.ProviderMappings.ToListAsync());
        Assert.Single(await db.EmailMessages.ToListAsync());
        var proof = await db.UserVerificationCodes.SingleAsync();
        Assert.Equal(SignupEmailTestSeed.Purpose, proof.Purpose);
        Assert.Equal(64, proof.CodeHash.Length);
        Assert.Equal(0, proxy.Creates);
    }

    [Fact]
    public async Task RequestCode_ExistingAccountAndImmediateResendAreEnumerationSafeAndDoNotReplaceIdentity()
    {
        await using var db = await Database(); var proxy = new Proxy(); var controller = Controller(db, proxy);
        var first = await controller.RequestSignupEmailCode(new() { Email = Email }, default);
        var second = await controller.RequestSignupEmailCode(new() { Email = Email }, default);
        Assert.Equal(JsonSerializer.Serialize(Assert.IsType<AcceptedResult>(first.Result).Value),
            JsonSerializer.Serialize(Assert.IsType<AcceptedResult>(second.Result).Value));
        Assert.Single(await db.EmailMessages.ToListAsync());
        var user = await db.Users.SingleAsync(); user.Status = "active";
        user.Identities.Add(new() { CompanyInstallationId = user.CompanyInstallationId, Provider = "local", Subject = Email.ToUpperInvariant(), PasswordHash = "existing-hash" });
        await db.SaveChangesAsync();
        var existing = await controller.RequestSignupEmailCode(new() { Email = Email }, default);
        Assert.Equal(JsonSerializer.Serialize(Assert.IsType<AcceptedResult>(first.Result).Value),
            JsonSerializer.Serialize(Assert.IsType<AcceptedResult>(existing.Result).Value));
        Assert.Equal("existing-hash", (await db.UserIdentities.SingleAsync()).PasswordHash);
        Assert.Single(await db.EmailMessages.ToListAsync());
    }

    [Theory]
    [InlineData(null)]
    [InlineData("000000")]
    public async Task Signup_WithoutCorrectMailboxCodeCannotCreateAccount(string? code)
    {
        await using var db = await Database(); await SignupEmailTestSeed.Prepare(db, Email); var proxy = new Proxy();
        var response = await Controller(db, proxy).Signup(Request(code), default);
        Assert.Equal(400, Assert.IsType<BadRequestObjectResult>(response.Result).StatusCode);
        Assert.Equal(0, proxy.Creates);
        Assert.Empty(await db.ProviderMappings.ToListAsync());
        Assert.Empty(await db.UserIdentities.ToListAsync());
        Assert.Empty(await db.ReferralSignupAttempts.ToListAsync());
        Assert.Equal("pending_signup", (await db.Users.SingleAsync()).Status);
    }

    [Fact]
    public async Task Signup_CorrectCodeCreatesOnceAndCannotBeReplayed()
    {
        await using var db = await Database(); await SignupEmailTestSeed.Prepare(db, Email); var proxy = new Proxy();
        var controller = Controller(db, proxy);
        var response = await controller.Signup(Request(SignupEmailTestSeed.Code), default);
        Assert.Equal(201, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        var body = JsonSerializer.SerializeToElement(((ObjectResult)response.Result!).Value);
        Assert.False(body.GetProperty("emailVerificationRequired").GetBoolean());
        Assert.NotNull((await db.Users.SingleAsync()).EmailVerifiedAt);
        Assert.Equal("active", (await db.Users.SingleAsync()).Status);
        Assert.NotNull((await db.UserVerificationCodes.SingleAsync()).ConsumedAt);
        Assert.NotEqual(Request(SignupEmailTestSeed.Code).Password, (await db.UserIdentities.SingleAsync()).PasswordHash);
        await controller.Signup(Request(SignupEmailTestSeed.Code), default);
        Assert.Equal(1, proxy.Creates);
    }

    [Fact]
    public async Task Signup_ExpiredOrExhaustedCodeCannotCreateAccount()
    {
        await using var db = await Database(); var user = await SignupEmailTestSeed.Prepare(db, Email); var proxy = new Proxy();
        var service = new UserVerificationCodeService(db);
        for (var i = 0; i < 5; i++)
            await service.VerifyAndConsumeAsync(user.Id, SignupEmailTestSeed.Purpose, "000000", default);
        Assert.Equal(VerificationCodeOutcome.Locked, await service.VerifyAndConsumeAsync(user.Id, SignupEmailTestSeed.Purpose, SignupEmailTestSeed.Code, default));
        Assert.Equal(5, (await db.UserVerificationCodes.SingleAsync()).AttemptCount);
        await SignupEmailTestSeed.Prepare(db, Email);
        var latest = await db.UserVerificationCodes.SingleAsync(x => x.ConsumedAt == null); latest.ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(-1);
        await db.SaveChangesAsync();
        var result = await Controller(db, proxy).Signup(Request(SignupEmailTestSeed.Code), default);
        Assert.IsType<BadRequestObjectResult>(result.Result);
        Assert.Equal(0, proxy.Creates);
    }

    [Fact]
    public async Task Signup_CodeCannotBeUsedForAnotherEmail()
    {
        await using var db = await Database(); await SignupEmailTestSeed.Prepare(db, "different@example.test"); var proxy = new Proxy();
        var result = await Controller(db, proxy).Signup(Request(SignupEmailTestSeed.Code), default);
        Assert.IsType<BadRequestObjectResult>(result.Result);
        Assert.Equal(0, proxy.Creates);
    }

    [Theory]
    [InlineData(null, 400, "auth.signup.country_required")]
    [InlineData("si", 403, "auth.signup.country_blocked")]
    [InlineData("Slovenia", 400, "auth.signup.country_invalid")]
    public async Task Signup_ResidencePolicyFailurePreservesProofAndCreatesNoReservation(string? country, int status, string code)
    {
        await using var db = await Database(); await SignupEmailTestSeed.Prepare(db, Email);
        var proxy = new Proxy { BlockedCountries = ["SI"] };
        var result = Assert.IsType<ObjectResult>((await Controller(db, proxy).Signup(Request(SignupEmailTestSeed.Code, country), default)).Result);
        Assert.Equal(status, result.StatusCode);
        Assert.Contains(code, JsonSerializer.Serialize(result.Value));
        Assert.Equal(0, proxy.Creates);
        Assert.Null((await db.UserVerificationCodes.SingleAsync()).ConsumedAt);
        Assert.Empty(await db.ReferralSignupAttempts.ToListAsync());
        Assert.Empty(await db.UserIdentities.ToListAsync());
    }

    [Fact]
    public async Task Signup_UsesPolicyEnforcingRouteWithExplicitCountryAndReferral()
    {
        await using var db = await Database(); await SignupEmailTestSeed.Prepare(db, Email);
        var proxy = new Proxy { BlockedCountries = ["SI"] };
        var result = await Controller(db, proxy).Signup(Request(SignupEmailTestSeed.Code, " gb ", " FRIEND1 "), default);
        Assert.Equal(201, Assert.IsType<ObjectResult>(result.Result).StatusCode);
        var upstream = Assert.Single(proxy.Posts);
        Assert.Equal("/api/v2/users/self-registration", upstream.Path);
        Assert.Equal("GB", upstream.Body.GetProperty("CountryCode").GetString());
        Assert.Equal("FRIEND1", upstream.Body.GetProperty("ReferralCode").GetString());
        Assert.False(upstream.Body.TryGetProperty("CompanyId", out _));
        Assert.False(upstream.Body.TryGetProperty("Password", out _));
    }

    [Theory]
    [InlineData("SELF_REGISTRATION_DISABLED", 403, "auth.signup.registration_disabled")]
    [InlineData("REFERRAL_CODE_INVALID", 400, "auth.referral.invalid")]
    [InlineData("REGISTRATION_COUNTRY_BLOCKED", 403, "auth.signup.country_blocked")]
    public async Task Signup_FinalPolicyRefusalAllowsFreshVerifiedAttempt(string upstreamCode, int status, string publicCode)
    {
        await using var db = await Database(); await SignupEmailTestSeed.Prepare(db, Email);
        var proxy = new Proxy { CreateError = new("upstream_failure", "Rejected", status, JsonSerializer.Serialize(new { code = upstreamCode })) };
        var rejected = Assert.IsType<ObjectResult>((await Controller(db, proxy).Signup(Request(SignupEmailTestSeed.Code), default)).Result);
        Assert.Equal(status, rejected.StatusCode);
        Assert.Contains(publicCode, JsonSerializer.Serialize(rejected.Value));
        var attempt = Assert.Single(await db.ReferralSignupAttempts.ToListAsync());
        Assert.Equal("REJECTED", attempt.State);
        Assert.Null(attempt.EmailNormalized);
        Assert.Equal("pending_signup", (await db.Users.SingleAsync()).Status);
        Assert.Empty(await db.UserIdentities.ToListAsync());
        await SignupEmailTestSeed.Prepare(db, Email);
        proxy.CreateError = null;
        Assert.Equal(201, Assert.IsType<ObjectResult>((await Controller(db, proxy).Signup(Request(SignupEmailTestSeed.Code), default)).Result).StatusCode);
    }

    private static SignupRequestDto Request(string? code, string? country = null, string? referral = null) => new()
    { Email = Email, Password = "Example-only-password!37", EmailVerificationCode = code, CountryCode = country, ReferralCode = referral };

    private static async Task<NeoBankingDbContext> Database()
    {
        var db = new NeoBankingDbContext(new DbContextOptionsBuilder<NeoBankingDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.CompanyInstallations.Add(new() { Slug = "default", DisplayName = "Test", LegalName = "Test" }); await db.SaveChangesAsync(); return db;
    }
    private static AuthController Controller(NeoBankingDbContext db, Proxy proxy)
    {
        var notifier = new AuthEmailNotifier(new EmailOutbox(db, new EmailTemplateStore(db), new ContextAccessor(), NullLogger<EmailOutbox>.Instance),
            new UserVerificationCodeService(db), Options.Create(new EmailOptions()));
        return new AuthController(db, new PasswordHasher<ApplicationUser>(), proxy,
            Options.Create(new JwtOptions { Issuer = "test", Audience = "test", SigningKey = "test-only-signing-key-with-at-least-32-characters" }),
            Options.Create(new CompanyOptions { Features = new() { EqualsMoneyEnabled = false, ReferralsEnabled = false } }),
            Options.Create(new EmailOptions()), notifier, new LoginAttemptTracker(), NullLogger<AuthController>.Instance)
            { ControllerContext = new() { HttpContext = new DefaultHttpContext() } };
    }
    private sealed class Proxy : IProxyHoppaRequestUseCase
    {
        public int Creates { get; private set; }
        public string[] BlockedCountries { get; init; } = [];
        public ApplicationError? CreateError { get; set; }
        public List<(string Path, JsonElement Body)> Posts { get; } = [];
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command, CancellationToken cancellationToken)
        {
            if (command.UpstreamPath == "/api/v2/users") throw new InvalidOperationException("Signup must use the policy-enforcing route.");
            if (command.Method == HttpMethod.Post && command.UpstreamPath == "/api/v2/users/self-registration")
            {
                Creates++;
                Posts.Add((command.UpstreamPath, JsonSerializer.SerializeToElement(command.Request)));
                if (CreateError is not null) return Task.FromResult(ApplicationResult<JsonElement?>.Failure(CreateError));
            }
            var json = command.UpstreamPath switch
            {
                "/api/v2/users/registration-policy" => JsonSerializer.Serialize(new
                {
                    companyId = 1, allowsSelfRegistration = true, requireExternalWallet = false, needsReferralCode = false,
                    referralCodeOptional = true, referralProgramEnabled = true, blockedCountries = BlockedCountries
                }),
                "/api/v2/users/check-referral" => """{"valid":true}""",
                _ => """{"id":"00000000-0000-7000-8000-000000000777"}"""
            };
            return Task.FromResult(ApplicationResult<JsonElement?>.Success(JsonSerializer.Deserialize<JsonElement>(json)));
        }
    }
    private sealed class ContextAccessor : ICompanyContextAccessor
    {
        public ICompanyContext Current => CompanyContext.Empty;
        public void SetCurrent(ICompanyContext context) { }
        public void Clear() { }
    }
}
