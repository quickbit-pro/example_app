using Microsoft.EntityFrameworkCore;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Assistant;
using NeoBanking.Infrastructure.Persistence;
using Npgsql;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AssistantPostgresFactAttribute : FactAttribute
{
    public AssistantPostgresFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("ASSISTANT_TEST_POSTGRES")))
            Skip = "Set ASSISTANT_TEST_POSTGRES to a disposable local server; tests create and drop their own databases.";
    }
}

public sealed class AssistantQuotaPostgresTests
{
    [Fact]
    public async Task NonPostgresProvider_FailsClosed()
    {
        await using var db = new NeoBankingDbContext(new DbContextOptionsBuilder<NeoBankingDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var store = new AssistantQuotaStore(db, TimeProvider.System);
        await Assert.ThrowsAsync<InvalidOperationException>(() =>
            store.ReserveAsync(Guid.NewGuid(), Guid.NewGuid(), new(50, 5, 500), default));
    }

    [AssistantPostgresFact]
    public Task ConcurrentRequests_OneLease_ChargesSurviveReleaseAndNewContexts() => WithDatabaseAsync(async (connection, companyId) =>
    {
        var clock = new TestClock(new DateTimeOffset(2026, 9, 23, 12, 0, 0, TimeSpan.Zero));
        Guid userId;
        await using (var setup = Context(connection)) userId = await AddUserAsync(setup, companyId);
        var limits = new AssistantQuotaLimits(3, 2, 100);

        var attempts = await Task.WhenAll(Enumerable.Range(0, 10).Select(async _ =>
        {
            await using var db = Context(connection);
            return await new AssistantQuotaStore(db, clock).ReserveAsync(companyId, userId, limits, default);
        }));
        var winner = Assert.Single(attempts, result => result.Outcome == AssistantQuotaOutcome.Accepted);
        Assert.Equal(9, attempts.Count(result => result.Outcome == AssistantQuotaOutcome.Concurrent));
        Assert.All(attempts, result => Assert.Equal(1, result.Used));

        await using var check = Context(connection);
        var store = new AssistantQuotaStore(check, clock);
        Assert.Equal(1, await store.GetUsedAsync(companyId, userId, clock.GetUtcNow(), default));
        await store.ReleaseAsync(winner.Id!.Value, default);
        Assert.Equal(1, await store.GetUsedAsync(companyId, userId, clock.GetUtcNow(), default));
        var second = await store.ReserveAsync(companyId, userId, limits, default);
        Assert.Equal(AssistantQuotaOutcome.Accepted, second.Outcome);
        Assert.Equal(2, second.Used);
        await store.ReleaseAsync(second.Id!.Value, default);
        var rateLimited = await store.ReserveAsync(companyId, userId, limits, default);
        Assert.Equal(AssistantQuotaOutcome.RateLimit, rateLimited.Outcome);
        Assert.Equal(2, rateLimited.Used);

        clock.Advance(TimeSpan.FromSeconds(61));
        var third = await store.ReserveAsync(companyId, userId, limits, default);
        Assert.Equal(AssistantQuotaOutcome.Accepted, third.Outcome);
        await store.ReleaseAsync(third.Id!.Value, default);
        var dailyLimited = await store.ReserveAsync(companyId, userId, limits, default);
        Assert.Equal(AssistantQuotaOutcome.DailyLimit, dailyLimited.Outcome);
        Assert.Equal(3, dailyLimited.Used);
        Assert.Equal(3, await check.AssistantUsageReservations.CountAsync());
    });

    [AssistantPostgresFact]
    public Task GlobalBudget_IsAtomicAcrossDifferentUsers() => WithDatabaseAsync(async (connection, companyId) =>
    {
        var clock = new TestClock(new DateTimeOffset(2026, 9, 23, 12, 0, 0, TimeSpan.Zero));
        var userIds = new List<Guid>();
        await using (var setup = Context(connection))
            for (var index = 0; index < 8; index++) userIds.Add(await AddUserAsync(setup, companyId));

        var attempts = await Task.WhenAll(userIds.Select(async userId =>
        {
            await using var db = Context(connection);
            return await new AssistantQuotaStore(db, clock).ReserveAsync(companyId, userId, new(50, 5, 3), default);
        }));
        Assert.Equal(3, attempts.Count(result => result.Outcome == AssistantQuotaOutcome.Accepted));
        Assert.Equal(5, attempts.Count(result => result.Outcome == AssistantQuotaOutcome.GlobalLimit));
        await using var check = Context(connection);
        Assert.Equal(3, await check.AssistantUsageReservations.CountAsync());
    });

    [AssistantPostgresFact]
    public Task ExpiredLeasesRecover_AndMinuteWindowSurvivesUtcDayReset() => WithDatabaseAsync(async (connection, companyId) =>
    {
        var clock = new TestClock(new DateTimeOffset(2026, 9, 23, 23, 59, 58, TimeSpan.Zero));
        await using var db = Context(connection);
        var userId = await AddUserAsync(db, companyId);
        var store = new AssistantQuotaStore(db, clock);
        var first = await store.ReserveAsync(companyId, userId, new(50, 1, 500), default);
        Assert.Equal(AssistantQuotaOutcome.Accepted, first.Outcome);
        clock.Advance(TimeSpan.FromSeconds(3));
        Assert.Equal(0, await store.GetUsedAsync(companyId, userId, clock.GetUtcNow(), default));
        Assert.Equal(AssistantQuotaOutcome.Concurrent,
            (await store.ReserveAsync(companyId, userId, new(50, 1, 500), default)).Outcome);

        await store.ReleaseAsync(first.Id!.Value, default);
        Assert.Equal(AssistantQuotaOutcome.RateLimit,
            (await store.ReserveAsync(companyId, userId, new(50, 1, 500), default)).Outcome);
        clock.Advance(TimeSpan.FromSeconds(58));
        var second = await store.ReserveAsync(companyId, userId, new(50, 1, 500), default);
        Assert.Equal(AssistantQuotaOutcome.Accepted, second.Outcome);
        Assert.Equal(1, second.Used);
        // Simulate a crashed process: no release. The next request recovers after the lease expires.
        clock.Advance(TimeSpan.FromSeconds(61));
        var recovered = await store.ReserveAsync(companyId, userId, new(50, 1, 500), default);
        Assert.Equal(AssistantQuotaOutcome.Accepted, recovered.Outcome);
        Assert.Equal(2, recovered.Used);
    });

    private static async Task WithDatabaseAsync(Func<string, Guid, Task> action)
    {
        var source = Environment.GetEnvironmentVariable("ASSISTANT_TEST_POSTGRES")!;
        var name = $"assistant_test_{Guid.NewGuid():N}";
        await using var admin = new NpgsqlConnection(source);
        await admin.OpenAsync();
        await using (var create = new NpgsqlCommand($"CREATE DATABASE \"{name}\"", admin))
            await create.ExecuteNonQueryAsync();
        var connection = new NpgsqlConnectionStringBuilder(source) { Database = name }.ConnectionString;
        try
        {
            Guid companyId;
            await using (var setup = Context(connection))
            {
                await setup.Database.MigrateAsync();
                await setup.Database.MigrateAsync();
                companyId = await setup.CompanyInstallations.Select(company => company.Id).FirstAsync();
            }
            await action(connection, companyId);
        }
        finally
        {
            NpgsqlConnection.ClearAllPools();
            await using var drop = new NpgsqlCommand($"DROP DATABASE \"{name}\" WITH (FORCE)", admin);
            await drop.ExecuteNonQueryAsync();
        }
    }

    private static async Task<Guid> AddUserAsync(NeoBankingDbContext db, Guid companyId)
    {
        var email = $"{Guid.NewGuid():N}@quota.test";
        var user = new ApplicationUser { CompanyInstallationId = companyId, Email = email, EmailNormalized = email.ToUpperInvariant(), Status = "active" };
        db.Users.Add(user);
        await db.SaveChangesAsync();
        return user.Id;
    }

    private static NeoBankingDbContext Context(string connection) =>
        new(new DbContextOptionsBuilder<NeoBankingDbContext>().UseNpgsql(connection).Options);

    private sealed class TestClock(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
        public void Advance(TimeSpan duration) => now += duration;
    }
}
