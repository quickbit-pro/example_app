using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Controllers;
using NeoBanking.Api.Email;
using NeoBanking.Application.Company;
using NeoBanking.Application.DTOs.Auth;
using NeoBanking.Application.Email;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Email;
using NeoBanking.Infrastructure.Persistence;
using NeoBanking.Infrastructure.Security;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class RecoveryResendTests
{
    [Fact]
    public async Task ResendQueuesNewCodeAfterCooldown_AndNeverDeliversReplacedOrExpiredCodes()
    {
        await using var db = Database();
        var user = await User(db);
        var clock = new TestClock();
        var notifier = Notifier(db, clock);
        Assert.True(await notifier.SendPasswordResetAsync(user, default));
        await db.SaveChangesAsync();
        var firstMessage = await db.EmailMessages.SingleAsync();
        var firstCode = await db.UserVerificationCodes.SingleAsync();
        Assert.False(await EmailDispatcher.IsObsoleteRecoveryAsync(db, firstMessage, default));
        Assert.False(await notifier.SendPasswordResetAsync(user, default));
        await db.SaveChangesAsync();
        Assert.Equal(1, await db.EmailMessages.CountAsync());
        clock.Now = clock.Now.AddMinutes(2);
        Assert.True(await notifier.SendPasswordResetAsync(user, default));
        await db.SaveChangesAsync();
        Assert.Equal(2, await db.EmailMessages.CountAsync());
        Assert.NotNull(firstCode.ConsumedAt);
        Assert.True(await EmailDispatcher.IsObsoleteRecoveryAsync(db, firstMessage, default));
        var newest = await db.EmailMessages.SingleAsync(m => m.Id != firstMessage.Id);
        var active = await db.UserVerificationCodes.SingleAsync(c => c.ConsumedAt == null);
        Assert.False(await EmailDispatcher.IsObsoleteRecoveryAsync(db, newest, default));
        active.ExpiresAt = DateTimeOffset.UtcNow.AddSeconds(-1);
        await db.SaveChangesAsync();
        Assert.True(await EmailDispatcher.IsObsoleteRecoveryAsync(db, newest, default));
        Assert.Equal(VerificationCodeOutcome.Expired, await new UserVerificationCodeService(db)
            .VerifyAsync(user.Id, VerificationPurposes.PasswordReset, "000000", default));
    }

    [Fact]
    public async Task ReplacementCodeWorksOnce_AndPreviousCodeCannotResetPassword()
    {
        await using var db = Database();
        var user = await User(db);
        var clock = new TestClock();
        var codes = new UserVerificationCodeService(db, clock);
        var first = await codes.IssueAsync(user, VerificationPurposes.PasswordReset, TimeSpan.FromMinutes(15), TimeSpan.FromSeconds(60), default);
        await db.SaveChangesAsync();
        clock.Now = clock.Now.AddMinutes(2);
        var replacement = await codes.IssueAsync(user, VerificationPurposes.PasswordReset, TimeSpan.FromMinutes(15), TimeSpan.FromSeconds(60), default);
        await db.SaveChangesAsync();
        // A random six-digit replacement can legitimately equal its predecessor.
        if (first!.Code != replacement!.Code)
            Assert.Equal(VerificationCodeOutcome.Invalid, await codes.VerifyAsync(user.Id, VerificationPurposes.PasswordReset, first.Code, default));
        Assert.Equal(VerificationCodeOutcome.Valid, await codes.VerifyAsync(user.Id, VerificationPurposes.PasswordReset, replacement!.Code, default));
        await db.SaveChangesAsync();
        Assert.Equal(VerificationCodeOutcome.NotFound, await codes.VerifyAsync(user.Id, VerificationPurposes.PasswordReset, replacement.Code, default));
    }

    [Fact]
    public async Task KnownAndUnknownEmailsHaveSameResponse_AndCooldownIsNotClaimedAsDelivery()
    {
        await using var db = Database();
        var user = await User(db);
        var controller = Controller(db);
        VerificationCodeIssuedResponseDto Receipt(ActionResult<VerificationCodeIssuedResponseDto> result) =>
            Assert.IsType<VerificationCodeIssuedResponseDto>(Assert.IsType<AcceptedResult>(result.Result).Value);
        var known = Receipt(await controller.ForgotPassword(new() { Email = user.Email }, default));
        var suppressed = Receipt(await controller.ForgotPassword(new() { Email = user.Email }, default));
        var unknown = Receipt(await controller.ForgotPassword(new() { Email = "unknown@example.test" }, default));
        Assert.Equal(JsonSerializer.Serialize(known), JsonSerializer.Serialize(unknown));
        Assert.Equal(JsonSerializer.Serialize(known), JsonSerializer.Serialize(suppressed));
        Assert.Equal(60, known.RetryAfterSeconds);
        Assert.Equal("test-request", known.RequestId);
        Assert.DoesNotContain("has been sent", known.Message);
        Assert.Equal(1, await db.EmailMessages.CountAsync());
    }

    [Fact]
    public async Task DisabledTemplateCannotPersistAnUndeliverableCodeOrStartCooldown()
    {
        await using var db = Database();
        var user = await User(db);
        db.EmailTemplates.Add(new EmailTemplate { CompanyInstallationId = user.CompanyInstallationId,
            Key = EmailTemplateCatalog.PasswordReset, IsEnabled = false });
        await db.SaveChangesAsync();
        var controller = Controller(db);
        Assert.IsType<AcceptedResult>((await controller.ForgotPassword(new() { Email = user.Email }, default)).Result);
        await db.SaveChangesAsync(); // A later request-scoped save must remain harmless.
        db.ChangeTracker.Clear();
        Assert.Empty(await db.EmailMessages.ToListAsync());
        Assert.Empty(await db.UserVerificationCodes.ToListAsync());
    }

    private static NeoBankingDbContext Database() => new(new DbContextOptionsBuilder<NeoBankingDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
    private static async Task<ApplicationUser> User(NeoBankingDbContext db)
    {
        var user = new ApplicationUser { CompanyInstallationId = Guid.NewGuid(), Email = "member@example.test", EmailNormalized = "MEMBER@EXAMPLE.TEST" };
        user.Identities.Add(new UserIdentity { Provider = "local", UserId = user.Id, CompanyInstallationId = user.CompanyInstallationId });
        db.Users.Add(user);
        await db.SaveChangesAsync();
        return user;
    }
    private static AuthEmailNotifier Notifier(NeoBankingDbContext db, TimeProvider? clock = null) => new(
        new EmailOutbox(db, new EmailTemplateStore(db), new ContextAccessor(), NullLogger<EmailOutbox>.Instance),
        new UserVerificationCodeService(db, clock), Options.Create(new EmailOptions { ResendCooldownSeconds = 60 }));
    private static AuthRecoveryController Controller(NeoBankingDbContext db) => new(db, new PasswordHasher<ApplicationUser>(),
        new UserVerificationCodeService(db), new LoginAttemptTracker(), Notifier(db), NullLogger<AuthRecoveryController>.Instance)
        { ControllerContext = new() { HttpContext = new DefaultHttpContext { TraceIdentifier = "test-request" } } };
    private sealed class TestClock : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class ContextAccessor : ICompanyContextAccessor
    {
        public ICompanyContext Current => CompanyContext.Empty;
        public void SetCurrent(ICompanyContext context) { }
        public void Clear() { }
    }
}
