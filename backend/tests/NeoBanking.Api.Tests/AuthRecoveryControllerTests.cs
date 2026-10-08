using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Logging.Abstractions;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.DTOs.Auth;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using NeoBanking.Infrastructure.Security;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AuthRecoveryControllerTests
{
    [Theory]
    [InlineData(4)]
    [InlineData(5)]
    public async Task VerifiedReset_ClearsPreviousFailures_AfterSavingPassword(int failures)
    {
        await using var fixture = await Fixture.Create(failures);

        var response = await fixture.Controller.ResetPassword(fixture.Request(), CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        Assert.Null(fixture.Attempts.LockedFor(Fixture.Email));
        // The previous failure count must also be cleared, not just its timer.
        fixture.Attempts.RecordFailure(Fixture.Email);
        Assert.Null(fixture.Attempts.LockedFor(Fixture.Email));
        Assert.NotNull(fixture.Attempts.LockedFor("other@example.test"));
        Assert.NotNull(fixture.Attempts.LockedFor($"2fa:{Fixture.Email}"));

        fixture.Db.ChangeTracker.Clear();
        var identity = await fixture.Db.UserIdentities.Include(item => item.User).SingleAsync();
        Assert.Equal(PasswordVerificationResult.Success,
            fixture.Hasher.VerifyHashedPassword(identity.User!, identity.PasswordHash!, Fixture.NewPassword));
        Assert.Equal(PasswordVerificationResult.Failed,
            fixture.Hasher.VerifyHashedPassword(identity.User!, identity.PasswordHash!, Fixture.OldPassword));
        Assert.NotNull((await fixture.Db.UserVerificationCodes.SingleAsync()).ConsumedAt);
        Assert.Equal("password_reset", (await fixture.Db.RefreshSessions.SingleAsync()).RevocationReason);
    }

    [Fact]
    public async Task InvalidCode_DoesNotClearLockoutOrChangePassword()
    {
        await using var fixture = await Fixture.Create(5);
        var wrongCode = fixture.Code == "000000" ? "111111" : "000000";

        var response = await fixture.Controller.ResetPassword(fixture.Request(wrongCode), CancellationToken.None);

        Assert.Equal(400, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.NotNull(fixture.Attempts.LockedFor(Fixture.Email));
        fixture.Db.ChangeTracker.Clear();
        var identity = await fixture.Db.UserIdentities.Include(item => item.User).SingleAsync();
        Assert.Equal(PasswordVerificationResult.Success,
            fixture.Hasher.VerifyHashedPassword(identity.User!, identity.PasswordHash!, Fixture.OldPassword));
        Assert.Null((await fixture.Db.RefreshSessions.SingleAsync()).RevokedAt);
    }

    [Fact]
    public async Task FailedSave_DoesNotClearLockout()
    {
        var failure = new FailSaveInterceptor();
        await using var fixture = await Fixture.Create(5, failure);
        failure.Fail = true;

        await Assert.ThrowsAsync<DbUpdateException>(() =>
            fixture.Controller.ResetPassword(fixture.Request(), CancellationToken.None));

        Assert.NotNull(fixture.Attempts.LockedFor(Fixture.Email));
    }

    private sealed class FailSaveInterceptor : SaveChangesInterceptor
    {
        public bool Fail { get; set; }

        public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
            DbContextEventData eventData, InterceptionResult<int> result,
            CancellationToken cancellationToken = default)
        {
            if (Fail) throw new DbUpdateException("Simulated persistence failure");
            return new(result);
        }
    }

    private sealed class Fixture : IAsyncDisposable
    {
        public const string Email = "person@example.test";
        public const string OldPassword = "OldPassword123!";
        public const string NewPassword = "NewPassword456!";
        public required NeoBankingDbContext Db { get; init; }
        public required AuthRecoveryController Controller { get; init; }
        public required LoginAttemptTracker Attempts { get; init; }
        public required PasswordHasher<ApplicationUser> Hasher { get; init; }
        public required string Code { get; init; }

        public ResetPasswordRequestDto Request(string? code = null) => new()
        {
            Email = "  Person@Example.Test ", Code = code ?? Code, NewPassword = NewPassword
        };

        public static async Task<Fixture> Create(int failures, IInterceptor? interceptor = null)
        {
            var options = new DbContextOptionsBuilder<NeoBankingDbContext>()
                .UseInMemoryDatabase(Guid.NewGuid().ToString());
            if (interceptor is not null) options.AddInterceptors(interceptor);
            var db = new NeoBankingDbContext(options.Options);
            var hasher = new PasswordHasher<ApplicationUser>();
            var user = new ApplicationUser
            {
                Id = Guid.NewGuid(), CompanyInstallationId = Guid.NewGuid(),
                Email = Email, EmailNormalized = Email.ToUpperInvariant()
            };
            user.Identities.Add(new UserIdentity
            {
                User = user, Provider = "local", Subject = user.EmailNormalized,
                CompanyInstallationId = user.CompanyInstallationId,
                PasswordHash = hasher.HashPassword(user, OldPassword)
            });
            user.RefreshSessions.Add(new RefreshSession
            {
                User = user, CompanyInstallationId = user.CompanyInstallationId,
                TokenHash = "test-session", ExpiresAt = DateTimeOffset.UtcNow.AddDays(1)
            });
            db.Users.Add(user);
            var codes = new UserVerificationCodeService(db);
            var issued = await codes.IssueAsync(user, VerificationPurposes.PasswordReset,
                TimeSpan.FromMinutes(10), TimeSpan.Zero, CancellationToken.None);
            await db.SaveChangesAsync();
            var attempts = new LoginAttemptTracker();
            for (var i = 0; i < failures; i++) attempts.RecordFailure(Email);
            for (var i = 0; i < 5; i++)
            {
                attempts.RecordFailure("other@example.test");
                attempts.RecordFailure($"2fa:{Email}");
            }
            var controller = new AuthRecoveryController(db, hasher, codes, attempts, null!,
                NullLogger<AuthRecoveryController>.Instance)
            {
                ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() }
            };
            return new Fixture
            {
                Db = db, Controller = controller, Attempts = attempts, Hasher = hasher, Code = issued!.Code
            };
        }

        public ValueTask DisposeAsync() => Db.DisposeAsync();
    }
}
