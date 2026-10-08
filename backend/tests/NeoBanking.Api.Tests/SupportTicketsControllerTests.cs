using System.Reflection;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Controllers;
using NeoBanking.Api.Notifications;
using NeoBanking.Api.Support;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Npgsql;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class SupportTicketsControllerTests
{
    private static readonly CancellationToken Ct = CancellationToken.None;

    [Fact]
    public void EndpointsRequireAuthenticationAndAdminPolicy()
    {
        Assert.Equal(AuthorizationPolicyNames.Admin,
            typeof(AdminSupportTicketsController).GetCustomAttribute<AuthorizeAttribute>()?.Policy);
        Assert.NotNull(typeof(MobileSupportTicketsController).GetCustomAttribute<AuthorizeAttribute>());
    }

    [SupportDatabaseFact]
    public async Task TicketRoundTrip_PersistsRepliesNotifiesAndReopens()
    {
        await using var fixture = await Database.Create();
        await using var db = fixture.Context();
        var user = await SeedUser(db);
        var customer = Mobile(db, user);
        var admin = Admin(db, user.CompanyInstallationId);
        var created = Detail(await customer.Create(new("  Card delivery  ", "  Where is my card?  "), Ct));
        Assert.Equal("Card delivery", created.Ticket.Subject);
        Assert.Equal("Where is my card?", Assert.Single(created.Messages).Body);
        Assert.False(created.Messages[0].IsAdmin);
        Assert.Equal("awaiting_support", created.Ticket.Status);
        db.ChangeTracker.Clear();

        var answered = Detail(await admin.Reply(created.Ticket.Id, new("Your card is on the way.", created.Ticket.Revision), Ct));
        Assert.Equal(2, answered.Messages.Count);
        Assert.True(answered.Messages[1].IsAdmin);
        Assert.Equal("awaiting_user", answered.Ticket.Status);
        var notification = await db.PushNotifications.SingleAsync();
        Assert.Equal(user.Id, notification.UserId);
        Assert.Equal($"/support/{created.Ticket.Id}", notification.Route);
        Assert.DoesNotContain("Your card is on the way", notification.Body);
        db.ChangeTracker.Clear();

        var stale = await admin.SetStatus(created.Ticket.Id, new("resolved", created.Ticket.Revision), Ct);
        Assert.IsType<ConflictObjectResult>(stale.Result);
        Assert.Equal(2, await db.SupportTicketMessages.CountAsync());
        db.ChangeTracker.Clear();

        var resolved = Detail(await admin.SetStatus(created.Ticket.Id, new("resolved", answered.Ticket.Revision), Ct));
        Assert.Equal("resolved", resolved.Ticket.Status);
        db.ChangeTracker.Clear();
        var reopened = Detail(await customer.Reply(created.Ticket.Id, new("I still need the tracking number.", resolved.Ticket.Revision), Ct));
        Assert.Equal("awaiting_support", reopened.Ticket.Status);
        Assert.Equal(3, reopened.Messages.Count);
        Assert.False(reopened.Messages[2].IsAdmin);
        db.ChangeTracker.Clear();
        var reloaded = Detail(await customer.Get(created.Ticket.Id, Ct));
        Assert.Equal(reopened.Messages, reloaded.Messages);
        Assert.Null(reloaded.Ticket.CustomerEmail);
        Assert.Null(reloaded.Ticket.CustomerId);
        Assert.Equal(user.Id, Detail(await admin.Get(created.Ticket.Id, Ct)).Ticket.CustomerId);
        Assert.Equal(user.Email, Detail(await admin.Get(created.Ticket.Id, Ct)).Ticket.CustomerEmail);
        var page = Assert.IsType<SupportTicketPage>(Assert.IsType<OkObjectResult>((await customer.List(cancellationToken: Ct)).Result).Value);
        Assert.Equal(created.Ticket.Id, Assert.Single(page.Items).Id);
        Assert.Equal(1, page.TotalCount);
    }

    [SupportDatabaseFact]
    public async Task OtherUsersAndCompaniesCannotReadReplyOrResolveTickets()
    {
        await using var fixture = await Database.Create();
        await using var db = fixture.Context();
        var owner = await SeedUser(db);
        var stranger = await SeedUser(db, owner.CompanyInstallationId);
        var otherCompanyUser = await SeedUser(db);
        var created = Detail(await Mobile(db, owner).Create(new("Private issue", "Only my support team should see this."), Ct));
        db.ChangeTracker.Clear();
        foreach (var actor in new[] { stranger, otherCompanyUser })
        {
            var mobile = Mobile(db, actor);
            Assert.IsType<NotFoundResult>((await mobile.Get(created.Ticket.Id, Ct)).Result);
            Assert.IsType<NotFoundResult>((await mobile.Reply(created.Ticket.Id, new("intrusion", created.Ticket.Revision), Ct)).Result);
            var page = Assert.IsType<SupportTicketPage>(Assert.IsType<OkObjectResult>((await mobile.List(cancellationToken: Ct)).Result).Value);
            Assert.Empty(page.Items);
        }
        var otherAdmin = Admin(db, otherCompanyUser.CompanyInstallationId);
        Assert.IsType<NotFoundResult>((await otherAdmin.Get(created.Ticket.Id, Ct)).Result);
        Assert.IsType<NotFoundResult>((await otherAdmin.Reply(created.Ticket.Id, new("intrusion", created.Ticket.Revision), Ct)).Result);
        Assert.IsType<NotFoundResult>((await otherAdmin.SetStatus(created.Ticket.Id, new("resolved", created.Ticket.Revision), Ct)).Result);
        Assert.Single(await db.SupportTicketMessages.ToListAsync());
        Assert.Empty(await db.PushNotifications.ToListAsync());
    }

    [SupportDatabaseFact]
    public async Task RejectsInvalidInputAndConcurrentStatusOverwrite()
    {
        await using var fixture = await Database.Create();
        await using var db = fixture.Context();
        var user = await SeedUser(db);
        var customer = Mobile(db, user);
        Assert.IsType<BadRequestObjectResult>((await customer.Create(new("   ", "body"), Ct)).Result);
        Assert.IsType<BadRequestObjectResult>((await customer.Create(new(new string('x', 161), "body"), Ct)).Result);
        Assert.IsType<BadRequestObjectResult>((await customer.Create(new("subject", new string('x', 8001)), Ct)).Result);
        var created = Detail(await customer.Create(new("Question", "Help please"), Ct));
        Assert.IsType<BadRequestObjectResult>((await customer.Reply(created.Ticket.Id, new("  ", created.Ticket.Revision), Ct)).Result);
        Assert.IsType<BadRequestObjectResult>((await Admin(db, user.CompanyInstallationId).SetStatus(created.Ticket.Id, new("bogus", created.Ticket.Revision), Ct)).Result);
        db.ChangeTracker.Clear();
        await using var staleDb = fixture.Context();
        var staleTicket = await staleDb.SupportTickets.SingleAsync();
        Detail(await customer.Reply(created.Ticket.Id, new("More details", created.Ticket.Revision), Ct));
        staleTicket.Status = "resolved";
        staleTicket.Revision = Guid.NewGuid();
        await Assert.ThrowsAsync<DbUpdateConcurrencyException>(() => staleDb.SaveChangesAsync());
        db.ChangeTracker.Clear();
        Assert.Equal("awaiting_support", (await db.SupportTickets.SingleAsync()).Status);
    }

    private static SupportTicketDetail Detail(ActionResult<SupportTicketDetail> result) =>
        Assert.IsType<SupportTicketDetail>(Assert.IsAssignableFrom<ObjectResult>(result.Result).Value);

    private static MobileSupportTicketsController Mobile(NeoBankingDbContext db, ApplicationUser user) =>
        WithIdentity(new MobileSupportTicketsController(db), user.CompanyInstallationId, user.Id);
    private static AdminSupportTicketsController Admin(NeoBankingDbContext db, Guid companyId) =>
        WithIdentity(new AdminSupportTicketsController(db, new PushNotificationOutbox(db)), companyId, Guid.NewGuid());
    private static T WithIdentity<T>(T controller, Guid companyId, Guid userId) where T : ControllerBase
    {
        controller.ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext {
            User = new ClaimsPrincipal(new ClaimsIdentity([
                new Claim("company_installation_id", companyId.ToString()), new Claim("local_user_id", userId.ToString())
            ], "test"))
        }};
        return controller;
    }
    private static async Task<ApplicationUser> SeedUser(NeoBankingDbContext db, Guid? companyId = null)
    {
        if (companyId is null)
        {
            var company = new CompanyInstallation { Slug = Guid.NewGuid().ToString(), DisplayName = "Support test", LegalName = "Support test" };
            db.CompanyInstallations.Add(company);
            companyId = company.Id;
        }
        var email = $"{Guid.NewGuid()}@example.test";
        var user = new ApplicationUser { CompanyInstallationId = companyId.Value, Email = email, EmailNormalized = email.ToUpperInvariant(), DisplayName = "Test customer" };
        db.Users.Add(user);
        await db.SaveChangesAsync();
        return user;
    }

    // A fresh, disposable database per test. Never uses the application's configured database.
    private sealed class Database(string connectionString) : IAsyncDisposable
    {
        public NeoBankingDbContext Context() => new(new DbContextOptionsBuilder<NeoBankingDbContext>().UseNpgsql(connectionString).Options);
        public static async Task<Database> Create()
        {
            var connection = new NpgsqlConnectionStringBuilder(Environment.GetEnvironmentVariable("SUPPORT_TEST_POSTGRES")) {
                Database = $"support_test_{Guid.NewGuid():N}", Pooling = false
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

public sealed class SupportDatabaseFactAttribute : FactAttribute
{
    public SupportDatabaseFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SUPPORT_TEST_POSTGRES")))
            Skip = "Set SUPPORT_TEST_POSTGRES to a local PostgreSQL connection with database creation privileges.";
    }
}
