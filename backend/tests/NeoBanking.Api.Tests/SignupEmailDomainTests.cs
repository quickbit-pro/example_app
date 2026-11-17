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

public sealed class SignupEmailDomainTests
{
    private const string Password = "Example-only-password!37";

    [Theory]
    [InlineData("i1306dqq32yyc@mailinator.com")]
    [InlineData("Someone@MAILINATOR.COM")]
    [InlineData("someone@inbox.mailinator.com")]
    [InlineData("someone@mailinator.com.")]
    [InlineData("someone@yopmail.com")]
    [InlineData("someone@guerrillamail.com")]
    [InlineData("someone@deltajohnsons.com")]
    public void BundledList_BlocksThrowawayProviders(string email)
    {
        Assert.True(BlockedEmailDomains.IsBlocked(email, new EmailOptions()));
    }

    [Theory]
    [InlineData("someone@gmail.com")]
    [InlineData("someone@outlook.com")]
    [InlineData("someone@icloud.com")]
    [InlineData("someone@proton.me")]
    [InlineData("someone@mailinator.com.example.test")]
    [InlineData("someone@safe-yopmail.test")]
    [InlineData("new-member@example.test")]
    [InlineData("no-domain")]
    [InlineData("")]
    [InlineData(null)]
    public void BundledList_LeavesOrdinaryAddressesAlone(string? email)
    {
        Assert.False(BlockedEmailDomains.IsBlocked(email, new EmailOptions()));
    }

    [Fact]
    public void Options_AddExemptAndSwitchOffTheList()
    {
        Assert.True(BlockedEmailDomains.IsBlocked(
            "someone@corp.example.test", new EmailOptions { BlockedSignupDomains = "other.test, Example.Test" }));
        Assert.False(BlockedEmailDomains.IsBlocked(
            "someone@inbox.mailinator.com", new EmailOptions { AllowedSignupDomains = "mailinator.com" }));
        Assert.False(BlockedEmailDomains.IsBlocked(
            "someone@mailinator.com", new EmailOptions { BlockDisposableSignupDomains = false }));
        // The most specific entry wins in both directions.
        var mixed = new EmailOptions { AllowedSignupDomains = "qa.mailinator.com", BlockedSignupDomains = "bad.example.test" };
        Assert.False(BlockedEmailDomains.IsBlocked("someone@qa.mailinator.com", mixed));
        Assert.True(BlockedEmailDomains.IsBlocked("someone@mailinator.com", mixed));
        Assert.True(BlockedEmailDomains.IsBlocked("someone@bad.example.test", mixed));
        Assert.False(BlockedEmailDomains.IsBlocked("someone@example.test", mixed));
    }

    [Fact]
    public async Task Signup_RejectsAThrowawayAddressBeforeAnythingIsCreated()
    {
        await using var db = CreateDatabase();
        var proxy = new CountingProxy();
        var controller = CreateController(db, proxy, new EmailOptions());

        var response = await controller.Signup(Request("i1306dqq32yyc@mailinator.com"), CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status400BadRequest, problem.StatusCode);
        Assert.Contains("auth.signup.email_domain_blocked", JsonSerializer.Serialize(problem.Value));
        Assert.Equal(0, proxy.Calls);
        Assert.Empty(db.Users);
        Assert.Empty(db.ReferralSignupAttempts);
    }

    [Fact]
    public async Task EmailCode_RejectsAThrowawayAddressBeforeAPlaceholderIsStored()
    {
        await using var db = CreateDatabase();
        var proxy = new CountingProxy();
        var controller = CreateController(db, proxy, new EmailOptions());

        var response = await controller.RequestSignupEmailCode(
            new SignupEmailCodeRequestDto { Email = "i1306dqq32yyc@mailinator.com" }, CancellationToken.None);

        var problem = Assert.IsType<BadRequestObjectResult>(response.Result);
        Assert.Contains("auth.signup.email_domain_blocked", JsonSerializer.Serialize(problem.Value));
        Assert.Equal(0, proxy.Calls);
        Assert.Empty(db.Users);
    }

    [Fact]
    public async Task EmailCode_LetsAnExemptDomainThroughToTheRegistrationPolicy()
    {
        await using var db = CreateDatabase();
        var proxy = new CountingProxy();
        var controller = CreateController(db, proxy, new EmailOptions { AllowedSignupDomains = "mailinator.com" });

        var response = await controller.RequestSignupEmailCode(
            new SignupEmailCodeRequestDto { Email = "i1306dqq32yyc@mailinator.com" }, CancellationToken.None);

        // The stub platform has no registration policy, so the request stops there, past the domain check.
        Assert.DoesNotContain("auth.signup.email_domain_blocked", JsonSerializer.Serialize(((ObjectResult)response.Result!).Value));
        Assert.Equal(1, proxy.Calls);
    }

    private static SignupRequestDto Request(string email) => new()
    {
        Email = email,
        Password = Password,
        FirstName = "Ivy",
        LastName = "Tester"
    };

    private static NeoBankingDbContext CreateDatabase()
    {
        var db = new NeoBankingDbContext(
            new DbContextOptionsBuilder<NeoBankingDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.CompanyInstallations.Add(new CompanyInstallation { Slug = "default", DisplayName = "Test", LegalName = "Test" });
        db.SaveChanges();
        return db;
    }

    private static AuthController CreateController(NeoBankingDbContext db, CountingProxy proxy, EmailOptions email)
    {
        var controller = new AuthController(db, new PasswordHasher<ApplicationUser>(), proxy,
            Options.Create(new JwtOptions { Issuer = "test", Audience = "test", SigningKey = "test-only-signing-key-with-at-least-32-characters" }),
            // Equals consent has its own tests; switch it off so the request reaches the provider call.
            Options.Create(new CompanyOptions { Features = new CompanyFeatureOptions { EqualsMoneyEnabled = false } }),
            Options.Create(email),
            null!, new LoginAttemptTracker(), NullLogger<AuthController>.Instance);
        controller.ControllerContext = new() { HttpContext = new DefaultHttpContext() };
        return controller;
    }

    private sealed class CountingProxy : IProxyHoppaRequestUseCase
    {
        public int Calls { get; private set; }

        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(
            ProxyHoppaRequestCommand<TRequest> command,
            CancellationToken cancellationToken)
        {
            Calls++;
            using var document = JsonDocument.Parse("""{"id":777}""");
            return Task.FromResult(ApplicationResult<JsonElement?>.Success(document.RootElement.Clone()));
        }
    }
}
