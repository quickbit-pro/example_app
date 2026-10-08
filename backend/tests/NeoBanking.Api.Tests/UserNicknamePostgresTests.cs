using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using NeoBanking.Infrastructure.Persistence;
using Npgsql;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class NicknamePostgresFactAttribute : FactAttribute
{
    public NicknamePostgresFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("NICKNAME_TEST_POSTGRES")))
            Skip = "Set NICKNAME_TEST_POSTGRES to a disposable local server; this test creates and drops its own database.";
    }
}

public sealed class UserNicknamePostgresTests
{
    [NicknamePostgresFact]
    public async Task MigrationAndConcurrentClaims_OnlyOneWins_OtherReceivesConflict()
    {
        var source = Environment.GetEnvironmentVariable("NICKNAME_TEST_POSTGRES")!;
        var name = $"nickname_test_{Guid.NewGuid():N}";
        await using var admin = new NpgsqlConnection(source);
        await admin.OpenAsync();
        await using (var create = new NpgsqlCommand($"CREATE DATABASE \"{name}\"", admin))
            await create.ExecuteNonQueryAsync();
        var connection = new NpgsqlConnectionStringBuilder(source) { Database = name }.ConnectionString;
        try
        {
            Guid firstId, secondId;
            await using (var db = Context(connection))
            {
                await db.Database.MigrateAsync();
                await db.Database.MigrateAsync();
                var company = await db.CompanyInstallations.FirstAsync();
                firstId = (await UserNicknameTests.AddUser(db, company.Id)).Id;
                secondId = (await UserNicknameTests.AddUser(db, company.Id)).Id;
            }

            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
            var gate = new ClaimGate();
            await using var first = Context(connection, gate);
            await using var second = Context(connection, gate);
            var results = await Task.WhenAll(
                UserNicknameTests.Controller(first, firstId).UpdateProfile(new() { Nickname = "@AnA" }, timeout.Token),
                UserNicknameTests.Controller(second, secondId).UpdateProfile(new() { Nickname = "ANA" }, timeout.Token));
            Assert.Single(results, result => result.Result is OkObjectResult);
            Assert.Single(results, result => result.Result is ObjectResult { StatusCode: 409 });
            await using var check = Context(connection);
            Assert.Equal(1, await check.Users.CountAsync(user => user.Nickname == "ana"));
            Assert.Equal(1, await check.Users.CountAsync(user => user.Nickname == null));
            // Out-of-band noncanonical writes cannot bypass case-insensitive uniqueness.
            var loser = await check.Users.SingleAsync(user => user.Nickname == null);
            loser.Nickname = "ANA";
            var exception = await Assert.ThrowsAsync<DbUpdateException>(() => check.SaveChangesAsync());
            Assert.Equal(PostgresErrorCodes.CheckViolation, Assert.IsType<PostgresException>(exception.InnerException).SqlState);
        }
        finally
        {
            NpgsqlConnection.ClearAllPools();
            await using var drop = new NpgsqlCommand($"DROP DATABASE \"{name}\" WITH (FORCE)", admin);
            await drop.ExecuteNonQueryAsync();
        }
    }

    private static NeoBankingDbContext Context(string connection, params IInterceptor[] interceptors) =>
        new(new DbContextOptionsBuilder<NeoBankingDbContext>().UseNpgsql(connection).AddInterceptors(interceptors).Options);

    private sealed class ClaimGate : SaveChangesInterceptor
    {
        private int _arrivals;
        private readonly TaskCompletionSource _ready = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public override async ValueTask<InterceptionResult<int>> SavingChangesAsync(
            DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
        {
            if (Interlocked.Increment(ref _arrivals) == 2) _ready.TrySetResult();
            await _ready.Task.WaitAsync(cancellationToken);
            return result;
        }
    }
}
