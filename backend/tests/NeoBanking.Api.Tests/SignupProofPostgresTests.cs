using Microsoft.EntityFrameworkCore;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using NeoBanking.Infrastructure.Security;
using Npgsql;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class SignupProofPostgresTests
{
    [ReferralPostgresFact]
    public async Task ConcurrentProofConsumers_OnlyOneSucceeds_AndFailedAttemptsCannotBeLost()
    {
        var source = Environment.GetEnvironmentVariable("REFERRAL_FACADE_TEST_POSTGRES")!;
        var name = $"signup_proof_{Guid.NewGuid():N}";
        await using var admin = new NpgsqlConnection(source); await admin.OpenAsync();
        await using (var create = new NpgsqlCommand($"CREATE DATABASE \"{name}\"", admin)) await create.ExecuteNonQueryAsync();
        var cs = new NpgsqlConnectionStringBuilder(source) { Database = name }.ConnectionString;
        try
        {
            await using (var connection = new NpgsqlConnection(cs))
            {
                await connection.OpenAsync();
                await using var schema = new NpgsqlCommand("""
                    CREATE SCHEMA neobanking;
                    CREATE TABLE neobanking.user_verification_codes (
                      "Id" uuid PRIMARY KEY, "CompanyInstallationId" uuid, "UserId" uuid NOT NULL,
                      "Purpose" varchar(40) NOT NULL, "CodeHash" varchar(64) NOT NULL,
                      "ExpiresAt" timestamptz NOT NULL, "ConsumedAt" timestamptz,
                      "AttemptCount" integer NOT NULL, "MaxAttempts" integer NOT NULL,
                      "CreatedAt" timestamptz NOT NULL, "UpdatedAt" timestamptz NOT NULL);
                    """, connection);
                await schema.ExecuteNonQueryAsync();
            }
            var user = new ApplicationUser { CompanyInstallationId = Guid.NewGuid() };
            string plain;
            await using (var db = Db(cs))
            {
                var issued = await new UserVerificationCodeService(db).IssueAsync(user, SignupEmailTestSeed.Purpose, TimeSpan.FromMinutes(10), TimeSpan.Zero, default);
                plain = issued!.Code; await db.SaveChangesAsync();
            }
            var valid = await Task.WhenAll(Enumerable.Range(0, 8).Select(async _ =>
            {
                await using var db = Db(cs);
                return await new UserVerificationCodeService(db).VerifyAndConsumeAsync(user.Id, SignupEmailTestSeed.Purpose, plain, default);
            }));
            Assert.Single(valid, x => x == VerificationCodeOutcome.Valid);
            await using (var db = Db(cs))
            {
                var issued = await new UserVerificationCodeService(db).IssueAsync(user, SignupEmailTestSeed.Purpose, TimeSpan.FromMinutes(10), TimeSpan.Zero, default);
                plain = issued!.Code; await db.SaveChangesAsync();
            }
            var wrong = plain == "000000" ? "111111" : "000000";
            await Task.WhenAll(Enumerable.Range(0, 20).Select(async _ =>
            {
                await using var db = Db(cs);
                await new UserVerificationCodeService(db).VerifyAndConsumeAsync(user.Id, SignupEmailTestSeed.Purpose, wrong, default);
            }));
            await using (var db = Db(cs))
            {
                Assert.Equal(5, (await db.UserVerificationCodes.SingleAsync(x => x.ConsumedAt == null)).AttemptCount);
                Assert.Equal(VerificationCodeOutcome.Locked, await new UserVerificationCodeService(db).VerifyAndConsumeAsync(user.Id, SignupEmailTestSeed.Purpose, plain, default));
            }
        }
        finally
        {
            NpgsqlConnection.ClearAllPools();
            await using var drop = new NpgsqlCommand($"DROP DATABASE IF EXISTS \"{name}\" WITH (FORCE)", admin); await drop.ExecuteNonQueryAsync();
        }
    }
    private static NeoBankingDbContext Db(string cs) => new(new DbContextOptionsBuilder<NeoBankingDbContext>().UseNpgsql(cs).Options);
}
