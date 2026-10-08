using Microsoft.EntityFrameworkCore;
using NeoBanking.Infrastructure.Persistence;
using Npgsql;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class CustomerSyncPostgresFactAttribute : FactAttribute
{
    public CustomerSyncPostgresFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CUSTOMER_SYNC_TEST_POSTGRES")))
            Skip = "Set CUSTOMER_SYNC_TEST_POSTGRES to a disposable local server; this test creates and drops its own database.";
    }
}

public sealed class AdminCustomerSyncPostgresTests
{
    [CustomerSyncPostgresFact]
    public async Task MigrationAndSqlDueSelection_PersistCacheInvalidationAndBackoffAcrossScopes()
    {
        var source = Environment.GetEnvironmentVariable("CUSTOMER_SYNC_TEST_POSTGRES")!;
        var name = $"customer_sync_test_{Guid.NewGuid():N}";
        await using var admin = new NpgsqlConnection(source);
        await admin.OpenAsync();
        await using (var create = new NpgsqlCommand($"CREATE DATABASE \"{name}\"", admin))
            await create.ExecuteNonQueryAsync();
        var connection = new NpgsqlConnectionStringBuilder(source) { Database = name }.ConnectionString;
        var options = new DbContextOptionsBuilder<NeoBankingDbContext>().UseNpgsql(connection).Options;
        try
        {
            Guid company;
            var clock = new AdminCustomerSyncTests.TestClock();
            var hoppa = new AdminCustomerSyncTests.FakeHoppa();
            await using (var db = new NeoBankingDbContext(options))
            {
                await db.Database.MigrateAsync();
                await db.Database.MigrateAsync();
                company = (await db.CompanyInstallations.FirstAsync()).Id;
                await AdminCustomerSyncTests.AddUser(db, company, "101");
                await AdminCustomerSyncTests.Service(db, hoppa, clock).SyncCompanyAsync(company, default);
            }
            clock.Advance(1);
            await using (var db = new NeoBankingDbContext(options))
            {
                var service = AdminCustomerSyncTests.Service(db, hoppa, clock);
                await service.SyncCompanyAsync(company, default);
                Assert.Equal(1, hoppa.CardCalls);
                var snapshot = await db.AdminCustomerSnapshots.SingleAsync();
                snapshot.SyncRequestedAt = clock.GetUtcNow();
                await db.SaveChangesAsync();
                hoppa.FailureStatus = 429;
                await service.SyncCompanyAsync(company, default);
                Assert.Equal(2, hoppa.CardCalls);
                Assert.Equal(1, snapshot.TotalCardCount);
            }
            clock.Advance(1);
            await using (var db = new NeoBankingDbContext(options))
            {
                await AdminCustomerSyncTests.Service(db, hoppa, clock).SyncCompanyAsync(company, default);
                Assert.Equal(2, hoppa.CardCalls);
                Assert.Equal(1, (await db.AdminCustomerSnapshots.SingleAsync()).ConsecutiveSyncFailures);
                clock.Advance(1);
                hoppa.FailureStatus = null;
                await AdminCustomerSyncTests.Service(db, hoppa, clock).SyncCompanyAsync(company, default);
                Assert.Equal(3, hoppa.CardCalls);
            }
        }
        finally
        {
            NpgsqlConnection.ClearAllPools();
            await using var drop = new NpgsqlCommand($"DROP DATABASE \"{name}\" WITH (FORCE)", admin);
            await drop.ExecuteNonQueryAsync();
        }
    }
}
