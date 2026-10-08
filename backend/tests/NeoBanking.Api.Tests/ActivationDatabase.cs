using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Npgsql;

namespace NeoBanking.Api.Tests;

internal sealed class ActivationDatabase(string adminConnectionString, string databaseName, string connectionString) : IAsyncDisposable
{
    public Guid CompanyId { get; } = Guid.NewGuid();
    public Guid OtherCompanyId { get; } = Guid.NewGuid();
    public Guid OwnerId { get; } = Guid.NewGuid();
    public Guid PayerAId { get; } = Guid.NewGuid();
    public Guid PayerBId { get; } = Guid.NewGuid();

    public NeoBankingDbContext Context(params IInterceptor[] interceptors) => new(
        new DbContextOptionsBuilder<NeoBankingDbContext>().UseNpgsql(connectionString)
            .AddInterceptors(interceptors).Options);

    public static async Task<ActivationDatabase> CreateAsync(bool useMigrations = false)
    {
        var configured = Environment.GetEnvironmentVariable("ASSISTANT_TEST_POSTGRES")!;
        // Database is always replaced: no migrations, schema writes or deletes in the configured database.
        var admin = new NpgsqlConnectionStringBuilder(configured) { Database = "postgres", Pooling = false };
        var name = $"example_activation_test_{Guid.NewGuid():N}";
        await using (var connection = new NpgsqlConnection(admin.ConnectionString))
        {
            await connection.OpenAsync();
            await using var command = new NpgsqlCommand($"CREATE DATABASE \"{name}\"", connection);
            await command.ExecuteNonQueryAsync();
        }
        var test = new NpgsqlConnectionStringBuilder(admin.ConnectionString) { Database = name };
        var database = new ActivationDatabase(admin.ConnectionString, name, test.ConnectionString);
        try
        {
            await using var db = database.Context();
            if (useMigrations) await db.Database.MigrateAsync();
            else await db.Database.EnsureCreatedAsync();
            db.CompanyInstallations.AddRange(
                new CompanyInstallation { Id = database.CompanyId, Slug = "main", LegalName = "Main", DisplayName = "Main", Status = "active" },
                new CompanyInstallation { Id = database.OtherCompanyId, Slug = "other", LegalName = "Other", DisplayName = "Other", Status = "active" });
            db.Users.AddRange(database.User(database.OwnerId, "Owner"), database.User(database.PayerAId, "Payer A"),
                database.User(database.PayerBId, "Payer B"));
            await db.SaveChangesAsync();
            return database;
        }
        catch
        {
            await database.DisposeAsync();
            throw;
        }
    }

    private ApplicationUser User(Guid id, string name) => new()
    {
        Id = id, CompanyInstallationId = CompanyId, Email = $"{id:N}@example.test",
        EmailNormalized = $"{id:N}@EXAMPLE.TEST".ToUpperInvariant(), DisplayName = name, Status = "active"
    };

    public async ValueTask DisposeAsync()
    {
        await using var connection = new NpgsqlConnection(adminConnectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand($"DROP DATABASE IF EXISTS \"{databaseName}\" WITH (FORCE)", connection);
        await command.ExecuteNonQueryAsync();
    }
}
