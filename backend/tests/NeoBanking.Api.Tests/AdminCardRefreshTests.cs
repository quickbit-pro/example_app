using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Admin;
using NeoBanking.Api.Controllers;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Admin;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AdminCardRefreshTests
{
    private sealed class RecordingSync : IAdminCustomerSyncService
    {
        public List<Guid> Synced { get; } = [];
        public Guid? Failing { get; set; }
        public Task SyncCompanyAsync(Guid companyInstallationId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<bool> SyncCustomerAsync(Guid companyInstallationId, Guid userId, CancellationToken cancellationToken)
        {
            if (userId == Failing) throw new HttpRequestException("provider down");
            Synced.Add(userId);
            return Task.FromResult(true);
        }
    }

    [Fact]
    public async Task RefreshesOnlyCardHoldersOldestFirstAndReportsTheRemainder()
    {
        await using var db = CreateDatabase();
        var company = Guid.NewGuid();
        var oldHolder = Seed(db, company, cards: 2, syncedAt: DateTimeOffset.UtcNow.AddHours(-5));
        var newHolder = Seed(db, company, cards: 1, syncedAt: DateTimeOffset.UtcNow.AddMinutes(-1));
        var neverSynced = Seed(db, company, cards: 1, syncedAt: null);
        Seed(db, company, cards: 0, syncedAt: DateTimeOffset.UtcNow.AddDays(-2));
        Seed(db, Guid.NewGuid(), cards: 3, syncedAt: null);
        await db.SaveChangesAsync();
        var sync = new RecordingSync();

        var first = Assert.IsType<OkObjectResult>(await Controller(db, company, sync).RefreshCards(null, 2, CancellationToken.None));
        Assert.Equal([neverSynced, oldHolder], sync.Synced);
        var body = Body(first);
        Assert.Equal(2, body.refreshed); Assert.Equal(0, body.failed); Assert.Equal(1, body.remaining);

        sync.Failing = newHolder;
        var second = Assert.IsType<OkObjectResult>(await Controller(db, company, sync).RefreshCards(null, 10, CancellationToken.None));
        var again = Body(second);
        Assert.Equal(2, again.refreshed); Assert.Equal(1, again.failed); Assert.Equal(0, again.remaining);
    }

    [Fact]
    public async Task RefreshesOneCustomerWhenFiltered()
    {
        await using var db = CreateDatabase();
        var company = Guid.NewGuid();
        var holder = Seed(db, company, cards: 1, syncedAt: null);
        await db.SaveChangesAsync();
        var sync = new RecordingSync();
        Assert.IsType<OkObjectResult>(await Controller(db, company, sync).RefreshCards(holder, null, CancellationToken.None));
        Assert.Equal([holder], sync.Synced);
    }

    private static (int refreshed, int failed, int remaining) Body(OkObjectResult result)
    {
        var value = result.Value!;
        int Read(string name) => (int)value.GetType().GetProperty(name)!.GetValue(value)!;
        return (Read("refreshed"), Read("failed"), Read("remaining"));
    }

    private static Guid Seed(NeoBankingDbContext db, Guid company, int cards, DateTimeOffset? syncedAt)
    {
        var user = new ApplicationUser { CompanyInstallationId = company, Email = $"{Guid.NewGuid():N}@example.test", EmailNormalized = "x", Status = "active" };
        db.Users.Add(user);
        db.AdminCustomerSnapshots.Add(new AdminCustomerSnapshot { CompanyInstallationId = company, UserId = user.Id, TotalCardCount = cards, ActiveCardCount = cards, LastSyncedAt = syncedAt });
        return user.Id;
    }

    private static AdminOperationsController Controller(NeoBankingDbContext db, Guid companyId, IAdminCustomerSyncService sync) => new(db, sync, new AdminKpiService(db, TimeProvider.System))
    {
        ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity([new Claim("company_installation_id", companyId.ToString()), new Claim("local_user_id", Guid.NewGuid().ToString())], "test"))
            }
        }
    };

    private static NeoBankingDbContext CreateDatabase() => new(
        new DbContextOptionsBuilder<NeoBankingDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString("N")).Options);
}
