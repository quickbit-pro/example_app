using System.Text.Json;
using System.Text;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Controllers;
using NeoBanking.Api.Notifications;
using NeoBanking.Infrastructure.Hoppa;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using NeoBanking.Application.Common;
using NeoBanking.Application.Interfaces;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Admin;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AdminCustomerSyncTests
{
    [Fact]
    public async Task WorkerCachesCustomers_ThenRefreshesOnlyChangedOrExpiredCustomers()
    {
        await using var db = Database();
        var (company, first) = await Seed(db);
        var second = await AddUser(db, company, "202");
        var clock = new TestClock();
        var hoppa = new FakeHoppa();
        var service = Service(db, hoppa, clock);
        await service.SyncCompanyAsync(company, default);
        Assert.Equal(2, hoppa.CardCalls);
        Assert.Equal(0, hoppa.DiscoveryCalls);

        clock.Advance(1);
        // A new scope/restart still uses the persisted per-customer cache.
        db.ChangeTracker.Clear();
        await Service(db, hoppa, clock).SyncCompanyAsync(company, default);
        Assert.Equal(2, hoppa.CardCalls);
        Assert.Equal(0, hoppa.DiscoveryCalls);

        var changed = await db.AdminCustomerSnapshots.SingleAsync(s => s.UserId == first);
        changed.SyncRequestedAt = clock.GetUtcNow();
        await db.SaveChangesAsync();
        await service.SyncCompanyAsync(company, default);
        Assert.Equal(3, hoppa.CardCalls);
        Assert.Equal(clock.GetUtcNow(), changed.LastSyncAttemptAt);
        Assert.NotEqual(clock.GetUtcNow(), (await db.AdminCustomerSnapshots.SingleAsync(s => s.UserId == second)).LastSyncAttemptAt);

        clock.Advance(15);
        await service.SyncCompanyAsync(company, default);
        Assert.Equal(5, hoppa.CardCalls);
        Assert.Equal(0, hoppa.DiscoveryCalls);
    }

    [Theory]
    [InlineData(429)]
    [InlineData(503)]
    public async Task FailuresKeepGoodData_AndBackOffDespiteManualRefreshAndDirtyEvents(int status)
    {
        await using var db = Database();
        var (company, user) = await Seed(db);
        var clock = new TestClock();
        var hoppa = new FakeHoppa();
        var service = Service(db, hoppa, clock);
        await service.SyncCustomerAsync(company, user, default);
        var snapshot = await db.AdminCustomerSnapshots.SingleAsync();
        var cards = snapshot.CardSummaryJson;
        var ledger = await db.AdminTransactions.CountAsync();
        var inflow = snapshot.TransactionInflow30dJson;
        var balances = snapshot.BalanceSummaryJson;
        var accounts = snapshot.AccountSummaryJson;
        var lastSuccess = snapshot.LastSyncedAt;
        Assert.Equal(1, snapshot.TotalCardCount);

        clock.Advance(1);
        hoppa.FailureStatus = status;
        await service.SyncCustomerAsync(company, user, default);
        Assert.Equal(cards, snapshot.CardSummaryJson);
        Assert.Equal(inflow, snapshot.TransactionInflow30dJson);
        Assert.Equal(accounts, snapshot.AccountSummaryJson);
        Assert.Equal(balances, snapshot.BalanceSummaryJson);
        Assert.Equal(ledger, await db.AdminTransactions.CountAsync());
        Assert.Equal(1, snapshot.TotalCardCount);
        Assert.Equal(lastSuccess, snapshot.LastSyncedAt);
        Assert.Equal(clock.GetUtcNow().AddMinutes(2), snapshot.NextSyncAt);
        var calls = hoppa.CardCalls;
        snapshot.SyncRequestedAt = clock.GetUtcNow().AddSeconds(1);
        await db.SaveChangesAsync();
        clock.Advance(1);
        await service.SyncCustomerAsync(company, user, default);
        await service.SyncCompanyAsync(company, default);
        Assert.Equal(calls, hoppa.CardCalls);

        clock.Advance(1);
        await service.SyncCompanyAsync(company, default);
        Assert.Equal(calls + 1, hoppa.CardCalls);
        Assert.Equal(clock.GetUtcNow().AddMinutes(4), snapshot.NextSyncAt);
        Assert.Equal(2, snapshot.ConsecutiveSyncFailures);

        clock.Advance(4);
        hoppa.FailureStatus = null;
        await service.SyncCompanyAsync(company, default);
        Assert.Equal(0, snapshot.ConsecutiveSyncFailures);
        Assert.Null(snapshot.LastSyncError);
        Assert.Equal(clock.GetUtcNow().AddMinutes(15), snapshot.NextSyncAt);
    }

    [Fact]
    public async Task ManualRefreshBypassesFreshCache_ButCannotReadAnotherCompany()
    {
        await using var db = Database();
        var (company, user) = await Seed(db);
        var clock = new TestClock();
        var hoppa = new FakeHoppa();
        var service = Service(db, hoppa, clock);
        await service.SyncCustomerAsync(company, user, default);
        clock.Advance(1);
        await service.SyncCustomerAsync(company, user, default);
        Assert.Equal(2, hoppa.CardCalls);
        Assert.False(await service.SyncCustomerAsync(Guid.NewGuid(), user, default));
        Assert.Equal(2, hoppa.CardCalls);
    }

    [Fact]
    public async Task ConcurrentRefreshesShareOneFetch_AndEventDuringFetchIsNotLost()
    {
        var options = new DbContextOptionsBuilder<NeoBankingDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options;
        await using var firstDb = new NeoBankingDbContext(options);
        var (company, user) = await Seed(firstDb);
        var clock = new TestClock();
        var hoppa = new FakeHoppa();
        await Service(firstDb, hoppa, clock).SyncCustomerAsync(company, user, default);
        clock.Advance(1);
        hoppa.Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        hoppa.Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var first = Service(firstDb, hoppa, clock).SyncCustomerAsync(company, user, timeout.Token);
        await hoppa.Started.Task.WaitAsync(timeout.Token);
        clock.Advance(1); // second request arrives after the first fetch started
        await using var secondDb = new NeoBankingDbContext(options);
        var second = Service(secondDb, hoppa, clock).SyncCustomerAsync(company, user, timeout.Token);
        await using (var eventDb = new NeoBankingDbContext(options))
        {
            var snapshot = await eventDb.AdminCustomerSnapshots.SingleAsync();
            snapshot.SyncRequestedAt = clock.GetUtcNow().AddSeconds(1);
            await eventDb.SaveChangesAsync();
        }
        hoppa.Release.SetResult();
        await Task.WhenAll(first, second);
        Assert.Equal(2, hoppa.CardCalls); // initial fetch plus the shared refresh
        clock.Advance(1);
        await Service(secondDb, hoppa, clock).SyncCompanyAsync(company, default);
        Assert.Equal(3, hoppa.CardCalls);
    }

    [Fact]
    public async Task CancellationDoesNotEraseCacheOrRecordFailure()
    {
        await using var db = Database();
        var (company, user) = await Seed(db);
        var hoppa = new FakeHoppa();
        var clock = new TestClock();
        var service = Service(db, hoppa, clock);
        await service.SyncCustomerAsync(company, user, default);
        using var canceled = new CancellationTokenSource();
        canceled.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => service.SyncCustomerAsync(company, user, canceled.Token));
        Assert.Equal(1, hoppa.CardCalls);
        Assert.Equal(0, (await db.AdminCustomerSnapshots.SingleAsync()).ConsecutiveSyncFailures);
    }

    [Fact]
    public async Task CustomerWithoutBudgetsStillProjectsBankAccounts()
    {
        await using var db = Database();
        var (company, user) = await Seed(db);
        var hoppa = new FakeHoppa { MissingBudgets = true };
        await Service(db, hoppa, new TestClock()).SyncCustomerAsync(company, user, default);
        var snapshot = await db.AdminCustomerSnapshots.SingleAsync();
        Assert.Equal(1, snapshot.AccountCount);
        Assert.Contains("EUR", snapshot.BalanceSummaryJson);
        Assert.Null(snapshot.LastSyncError);
    }

    [Fact]
    public async Task SignedWebhookInvalidatesOnlyItsCustomer_AndKeepsRetrySchedule()
    {
        await using var db = Database();
        var (company, user) = await Seed(db);
        var other = await AddUser(db, company, "202");
        var future = DateTimeOffset.UtcNow.AddMinutes(10);
        db.AdminCustomerSnapshots.AddRange(
            new AdminCustomerSnapshot { CompanyInstallationId = company, UserId = user,
                LastSyncAttemptAt = DateTimeOffset.UtcNow.AddMinutes(-1), NextSyncAt = future, ConsecutiveSyncFailures = 1 },
            new AdminCustomerSnapshot { CompanyInstallationId = company, UserId = other, NextSyncAt = future });
        await db.SaveChangesAsync();
        const string secret = "test-only-webhook-secret";
        const string body = """{"eventId":"evt-1","eventType":"card.updated","data":{"userId":"101","cardId":"card-1","status":"active"}}""";
        var context = new DefaultHttpContext();
        context.Request.Body = new MemoryStream(Encoding.UTF8.GetBytes(body));
        context.Request.Headers["X-Hoppacard-Signature"] = Convert.ToHexString(
            HMACSHA256.HashData(Encoding.UTF8.GetBytes(secret), Encoding.UTF8.GetBytes(body)));
        var controller = new WebhooksController(db, Options.Create(new HoppaOptions { WebhookSecret = secret }),
            new PushNotificationOutbox(db), NullLogger<WebhooksController>.Instance)
        { ControllerContext = new ControllerContext { HttpContext = context } };

        await controller.ReceiveHoppaWebhook(default);
        db.ChangeTracker.Clear();
        var snapshot = await db.AdminCustomerSnapshots.SingleAsync(s => s.UserId == user);
        Assert.True(snapshot.SyncRequestedAt > snapshot.LastSyncAttemptAt);
        Assert.Equal(future, snapshot.NextSyncAt);
        Assert.Equal(1, snapshot.ConsecutiveSyncFailures);
        Assert.Null((await db.AdminCustomerSnapshots.SingleAsync(s => s.UserId == other)).SyncRequestedAt);
        Assert.Equal("processed", (await db.WebhookDeliveries.SingleAsync()).Status);
    }

    [Fact]
    public void BackoffIsCappedAndConfigurationIsBounded()
    {
        var settings = new AdminCustomerSyncOptions();
        Assert.Equal(TimeSpan.FromMinutes(60), settings.Backoff(30));
        settings.InitialBackoffMinutes = -1;
        settings.MaxBackoffMinutes = -1;
        Assert.Equal(TimeSpan.FromMinutes(1), settings.Backoff(1));
    }

    private static NeoBankingDbContext Database() => new(new DbContextOptionsBuilder<NeoBankingDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    private static async Task<(Guid Company, Guid User)> Seed(NeoBankingDbContext db)
    {
        var company = new CompanyInstallation { Slug = "default", Status = "active" };
        db.CompanyInstallations.Add(company);
        await db.SaveChangesAsync();
        return (company.Id, await AddUser(db, company.Id, "101"));
    }

    internal static async Task<Guid> AddUser(NeoBankingDbContext db, Guid company, string provider)
    {
        var user = new ApplicationUser { CompanyInstallationId = company, Email = $"{provider}@example.test", EmailNormalized = $"{provider}@EXAMPLE.TEST" };
        db.Users.Add(user);
        db.ProviderMappings.Add(new ProviderMapping { CompanyInstallationId = company, Provider = "hoppa",
            ProviderEntityType = "user", ProviderEntityId = provider, InternalEntityType = "user", InternalEntityId = user.Id });
        await db.SaveChangesAsync();
        return user.Id;
    }

    internal static AdminCustomerSyncService Service(NeoBankingDbContext db, FakeHoppa hoppa, TestClock clock) =>
        new(db, hoppa, NullLogger<AdminCustomerSyncService>.Instance, Options.Create(new AdminCustomerSyncOptions()), clock);

    internal sealed class TestClock : TimeProvider
    {
        private DateTimeOffset now = new(2030, 1, 1, 0, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => now;
        public void Advance(int minutes) => now = now.AddMinutes(minutes);
    }

    internal sealed class FakeHoppa : IHoppaClient
    {
        public int CardCalls;
        public int DiscoveryCalls;
        public int? FailureStatus;
        public bool MissingBudgets;
        public TaskCompletionSource? Started;
        public TaskCompletionSource? Release;

        public async Task<ApplicationResult<TResponse>> SendAsync<TRequest, TResponse>(HoppaRequest<TRequest> request, CancellationToken cancellationToken)
        {
            if (request.Path == "/api/v2/cards")
            {
                Interlocked.Increment(ref CardCalls);
                Started?.TrySetResult();
                if (Release is not null) await Release.Task.WaitAsync(cancellationToken);
            }
            if (request.Path == "/api/v2/users") Interlocked.Increment(ref DiscoveryCalls);
            if (MissingBudgets && request.Path.EndsWith("/budgets"))
                return ApplicationResult<TResponse>.Failure(new ApplicationError("test.missing", "No budgets", 404));
            if (FailureStatus is { } status)
                return ApplicationResult<TResponse>.Failure(new ApplicationError("test.failure", "Unavailable", status));
            var body = request.Path switch
            {
                "/api/v2/users" => """{"users":[],"totalPages":1}""",
                "/api/v2/banking/accounts" => """[{"id":"account-1","status":"active","balance":100,"currency":"EUR"}]""",
                "/api/v2/cards" => """[{"id":"card-1","status":"active"}]""",
                "/api/v2/transactions" => """[{"id":"tx-1","status":"completed","amount":5,"currency":"EUR","createdAt":"2029-12-31T00:00:00Z"}]""",
                _ => "{}"
            };
            return ApplicationResult<TResponse>.Success(JsonSerializer.Deserialize<TResponse>(body)!);
        }
    }
}
