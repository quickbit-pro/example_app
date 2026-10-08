using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Company;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.DTOs.Auth;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Email;
using NeoBanking.Infrastructure.Persistence;
using Npgsql;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AuthSessionTests
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private const string Password = "Example-only-password!37";

    [AuthDatabaseFact]
    public async Task IndependentSignInsCanRefreshAndReplayOnlyRevokesAffectedChain()
    {
        await using var fixture = await Database.Create();
        await using var db = fixture.Context();
        var user = await SeedUser(db);
        var controller = Controller(db, user);
        var phone = Token(await controller.Login(new() { Email = user.Email, Password = Password, DeviceName = "Phone" }, Ct));
        var laptop = Token(await controller.Login(new() { Email = user.Email, Password = Password, DeviceName = "Laptop" }, Ct));
        Assert.Equal(2, await db.RefreshSessions.CountAsync(x => x.RevokedAt == null));
        var phoneNext = Token(await controller.Refresh(new() { RefreshToken = phone.RefreshToken }, Ct));
        var phoneLatest = Token(await controller.Refresh(new() { RefreshToken = phoneNext.RefreshToken }, Ct));
        var laptopNext = Token(await controller.Refresh(new() { RefreshToken = laptop.RefreshToken }, Ct));

        Assert.IsType<UnauthorizedResult>((await controller.Refresh(new() { RefreshToken = phone.RefreshToken }, Ct)).Result);
        Assert.IsType<UnauthorizedResult>((await controller.Refresh(new() { RefreshToken = phoneLatest.RefreshToken }, Ct)).Result);
        Token(await controller.Refresh(new() { RefreshToken = laptopNext.RefreshToken }, Ct));
        var remaining = await db.RefreshSessions.SingleAsync(x => x.RevokedAt == null);
        Assert.Equal("Laptop", remaining.DeviceName);
    }

    [AuthDatabaseFact]
    public async Task LogoutWithoutRefreshTokenUsesJwtSessionIncludingLaterRotations()
    {
        await using var fixture = await Database.Create();
        await using var db = fixture.Context();
        var user = await SeedUser(db);
        var controller = Controller(db, user);
        var phone = Token(await controller.Login(new() { Email = user.Email, Password = Password }, Ct));
        var phoneId = (await db.RefreshSessions.SingleAsync()).Id;
        var laptop = Token(await controller.Login(new() { Email = user.Email, Password = Password }, Ct));
        var phoneNext = Token(await controller.Refresh(new() { RefreshToken = phone.RefreshToken }, Ct));
        controller = Controller(db, user, phoneId);

        Assert.IsType<NoContentResult>(await controller.Logout(null, Ct));
        Assert.IsType<UnauthorizedResult>((await controller.Refresh(new() { RefreshToken = phoneNext.RefreshToken }, Ct)).Result);
        Token(await controller.Refresh(new() { RefreshToken = laptop.RefreshToken }, Ct));
        Assert.Equal(1, await db.RefreshSessions.CountAsync(x => x.RevokedAt == null));
    }

    [AuthDatabaseFact]
    public async Task LogoutWithTokenOnlyEndsThatSignInAndMissingSessionDoesNotLogOutOtherDevices()
    {
        await using var fixture = await Database.Create();
        await using var db = fixture.Context();
        var user = await SeedUser(db);
        var controller = Controller(db, user);
        var phone = Token(await controller.Login(new() { Email = user.Email, Password = Password }, Ct));
        var laptop = Token(await controller.Login(new() { Email = user.Email, Password = Password }, Ct));
        await controller.Logout(null, Ct);
        Assert.Equal(2, await db.RefreshSessions.CountAsync(x => x.RevokedAt == null));
        await controller.Logout(new() { RefreshToken = phone.RefreshToken }, Ct);
        Assert.IsType<UnauthorizedResult>((await controller.Refresh(new() { RefreshToken = phone.RefreshToken }, Ct)).Result);
        Token(await controller.Refresh(new() { RefreshToken = laptop.RefreshToken }, Ct));
    }

    private static AuthTokenResponseDto Token(ActionResult<AuthTokenResponseDto> response) =>
        Assert.IsType<AuthTokenResponseDto>(Assert.IsType<OkObjectResult>(response.Result).Value);

    private static AuthController Controller(NeoBankingDbContext db, ApplicationUser user, Guid? sessionId = null)
    {
        var controller = new AuthController(db, new PasswordHasher<ApplicationUser>(), null!,
            Options.Create(new JwtOptions { Issuer = "test", Audience = "test", SigningKey = "test-only-signing-key-with-at-least-32-characters" }),
            Options.Create(new CompanyOptions()), Options.Create(new EmailOptions { RequireVerifiedEmailForLogin = false }),
            null!, new LoginAttemptTracker(), NullLogger<AuthController>.Instance);
        var claims = new List<Claim> { new("local_user_id", user.Id.ToString()), new("company_installation_id", user.CompanyInstallationId.ToString()) };
        if (sessionId.HasValue) claims.Add(new("sid", sessionId.Value.ToString()));
        controller.ControllerContext = new() { HttpContext = new DefaultHttpContext { User = new(new ClaimsIdentity(claims, "test")) } };
        return controller;
    }

    private static async Task<ApplicationUser> SeedUser(NeoBankingDbContext db)
    {
        var company = new CompanyInstallation { Slug = Guid.NewGuid().ToString(), DisplayName = "Test", LegalName = "Test" };
        var user = new ApplicationUser { CompanyInstallationId = company.Id, Email = "member@example.test", EmailNormalized = "MEMBER@EXAMPLE.TEST", DisplayName = "Test" };
        db.CompanyInstallations.Add(company);
        db.Users.Add(user);
        db.UserIdentities.Add(new() { CompanyInstallationId = company.Id, UserId = user.Id, Provider = "local", Subject = user.EmailNormalized,
            PasswordHash = new PasswordHasher<ApplicationUser>().HashPassword(user, Password) });
        await db.SaveChangesAsync();
        return user;
    }

    private sealed class Database(string connectionString) : IAsyncDisposable
    {
        public NeoBankingDbContext Context() => new(new DbContextOptionsBuilder<NeoBankingDbContext>().UseNpgsql(connectionString).Options);
        public static async Task<Database> Create()
        {
            var connection = new NpgsqlConnectionStringBuilder(Environment.GetEnvironmentVariable("AUTH_TEST_POSTGRES")) {
                Database = $"auth_test_{Guid.NewGuid():N}", Pooling = false
            };
            var fixture = new Database(connection.ConnectionString);
            await using var db = fixture.Context();
            await db.Database.MigrateAsync();
            return fixture;
        }
        public async ValueTask DisposeAsync()
        {
            await using var db = Context();
            await db.Database.EnsureDeletedAsync();
        }
    }
}

public sealed class AuthDatabaseFactAttribute : FactAttribute
{
    public AuthDatabaseFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("AUTH_TEST_POSTGRES")))
            Skip = "Set AUTH_TEST_POSTGRES to a local PostgreSQL connection with database creation privileges.";
    }
}
