using System.Globalization;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Admin;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.Interfaces;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Admin;
using NeoBanking.Infrastructure.Persistence;
using Npgsql;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AdminTransactionLedgerTests
{
    [Fact]
    public async Task FirstSyncBackfillsEveryPage_ThenLaterSyncsReadOnlyTheRecentWindow()
    {
        await using var db = Database();
        var (company, user) = await Seed(db);
        var clock = new AdminCustomerSyncTests.TestClock();
        var start = clock.GetUtcNow().AddDays(-400);
        var hoppa = new LedgerHoppa(Enumerable.Range(0, 1203)
            .Select(i => Row($"tx-{i}", "card_payment", 2m, "closed", start.AddHours(i * 8)))
            .ToList());

        await Service(db, hoppa, clock).SyncCustomerAsync(company, user, default);

        Assert.Equal(1203, await db.AdminTransactions.CountAsync());
        Assert.Equal([1, 2, 3], hoppa.RequestedPages);
        Assert.All(await db.AdminTransactions.ToListAsync(), row =>
        {
            Assert.Equal(AdminTransactionKinds.CardPurchase, row.Kind);
            Assert.Equal(AdminTransactionDirections.Out, row.Direction);
            Assert.Equal(user, row.UserId);
        });

        hoppa.RequestedPages.Clear();
        clock.Advance(20);
        await Service(db, hoppa, clock).SyncCustomerAsync(company, user, default);
        Assert.Equal([1], hoppa.RequestedPages);
        Assert.Equal(1203, await db.AdminTransactions.CountAsync());
    }

    [Fact]
    public async Task StatusChangesUpdateTheStoredRow_AndSnapshotTotalsUseExternalMovementsOnly()
    {
        await using var db = Database();
        var (company, user) = await Seed(db);
        var clock = new AdminCustomerSyncTests.TestClock();
        var now = clock.GetUtcNow();
        var hoppa = new LedgerHoppa(
        [
            Row("p1", "card_payment", 12m, "pending", now.AddDays(-1)),
            Row("d1", "crypto_deposit", 50m, "complete", now.AddDays(-2), currency: "USDT"),
            Row("c1", "crypto_to_quantum_transfer", 50m, "completed", now.AddDays(-2)),
            Row("t1", "card_topup", 40m, "completed", now.AddDays(-2)),
            Row("f1", "fees", -0.6m, "completed", now.AddDays(-2), description: "fees: card_topup_fee"),
        ]);

        await Service(db, hoppa, clock).SyncCustomerAsync(company, user, default);
        Assert.Equal(AdminTransactionStatuses.Pending, (await db.AdminTransactions.SingleAsync(row => row.ProviderTransactionId == "p1")).Status);

        hoppa.Rows[0] = Row("p1", "card_payment", 12m, "closed", now.AddDays(-1));
        clock.Advance(20);
        db.ChangeTracker.Clear();
        await Service(db, hoppa, clock).SyncCustomerAsync(company, user, default);

        Assert.Equal(5, await db.AdminTransactions.CountAsync());
        Assert.Equal(AdminTransactionStatuses.Completed, (await db.AdminTransactions.SingleAsync(row => row.ProviderTransactionId == "p1")).Status);
        var snapshot = await db.AdminCustomerSnapshots.SingleAsync();
        // Conversions and card top-ups move the customer's own money; they are not in/out.
        Assert.Equal(3, snapshot.CompletedTransactionCount30d);
        Assert.Equal(50m, JsonSerializer.Deserialize<Dictionary<string, decimal>>(snapshot.TransactionInflow30dJson)!["USDT"]);
        Assert.Equal(12.6m, JsonSerializer.Deserialize<Dictionary<string, decimal>>(snapshot.TransactionOutflow30dJson)!["USD"]);
        Assert.Equal("[]", snapshot.RecentTransactionsJson);
    }

    [Fact]
    public async Task RowsNamingAnotherProviderUserAreIgnored()
    {
        await using var db = Database();
        var (company, user) = await Seed(db);
        var clock = new AdminCustomerSyncTests.TestClock();
        var mine = Row("own", "card_payment", 5m, "closed", clock.GetUtcNow().AddDays(-1));
        var theirs = JsonSerializer.SerializeToElement(new Dictionary<string, object?>
        {
            ["id"] = "foreign", ["type"] = "card_payment", ["amount"] = 9m, ["currency"] = "USD", ["status"] = "closed",
            ["transactionDate"] = "2029-12-30T10:00:00", ["userId"] = 202
        });
        var owned = JsonSerializer.SerializeToElement(new Dictionary<string, object?>
        {
            ["id"] = "owned", ["type"] = "card_payment", ["amount"] = 3m, ["currency"] = "USD", ["status"] = "closed",
            ["transactionDate"] = "2029-12-30T11:00:00", ["userId"] = 101
        });

        await Service(db, new LedgerHoppa([mine, theirs, owned]), clock).SyncCustomerAsync(company, user, default);

        Assert.Equal(["own", "owned"], await db.AdminTransactions.OrderBy(row => row.ProviderTransactionId).Select(row => row.ProviderTransactionId).ToListAsync());
    }

    [Fact]
    public async Task RepeatedProviderViewsAreFlaggedAsDuplicates()
    {
        await using var db = Database();
        var (company, user) = await Seed(db);
        var clock = new AdminCustomerSyncTests.TestClock();
        var at = clock.GetUtcNow().AddDays(-3);
        var hoppa = new LedgerHoppa(
        [
            Row("m1", "7", 1.5m, "success", at, description: "Monthly card fee for card ending 6295 (2029-12-01 to 2029-12-31)"),
            Row("m2", "fees", -1.5m, "completed", at, description: "fees: Monthly card fee for card ending 6295 (2029-12-01 to 2029-12-31)"),
        ]);

        await Service(db, hoppa, clock).SyncCustomerAsync(company, user, default);

        Assert.False((await db.AdminTransactions.SingleAsync(row => row.ProviderTransactionId == "m1")).IsDuplicate);
        Assert.True((await db.AdminTransactions.SingleAsync(row => row.ProviderTransactionId == "m2")).IsDuplicate);
    }

    [CustomerSyncPostgresFact]
    public async Task LedgerSyncKpisAndMoneyQueriesRunOnPostgres()
    {
        var source = Environment.GetEnvironmentVariable("CUSTOMER_SYNC_TEST_POSTGRES")!;
        var name = $"admin_ledger_test_{Guid.NewGuid():N}";
        await using var admin = new NpgsqlConnection(source);
        await admin.OpenAsync();
        await using (var create = new NpgsqlCommand($"CREATE DATABASE \"{name}\"", admin))
            await create.ExecuteNonQueryAsync();
        var options = new DbContextOptionsBuilder<NeoBankingDbContext>()
            .UseNpgsql(new NpgsqlConnectionStringBuilder(source) { Database = name }.ConnectionString).Options;
        try
        {
            await using var db = new NeoBankingDbContext(options);
            await db.Database.MigrateAsync();
            var company = (await db.CompanyInstallations.FirstAsync()).Id;
            var user = await AdminCustomerSyncTests.AddUser(db, company, "101");
            var clock = new AdminCustomerSyncTests.TestClock();
            var now = clock.GetUtcNow();
            var hoppa = new LedgerHoppa(
            [
                Row("d1", "crypto_deposit", 50m, "complete", now.AddDays(-2), currency: "USDT", description: "Crypto deposit of 50 USDT from TRX"),
                Row("p1", "card_payment", 12m, "closed", now.AddDays(-1), description: "Type1: OPENAI                 SAN FRANCISCOCAUS"),
                Row("p2", "card_payment", 30m, "fail", now.AddDays(-1), description: "Type1: MIGROS"),
                Row("m1", "7", 1.5m, "success", now.AddDays(-1), description: "Monthly card fee for card ending 6295 (2029-12-01 to 2029-12-31)"),
                Row("m2", "fees", -1.5m, "completed", now.AddDays(-1), description: "fees: Monthly card fee for card ending 6295 (2029-12-01 to 2029-12-31)"),
            ]);
            await Service(db, hoppa, clock).SyncCustomerAsync(company, user, default);
            await Service(db, hoppa, clock).SyncCustomerAsync(company, user, default);
            Assert.Equal(5, await db.AdminTransactions.CountAsync());

            var overview = await new AdminKpiService(db, clock).GetOverviewAsync(company, 30, default);
            Assert.Equal(12m, overview.Cards.Spend.Amount);
            Assert.Equal(50m, overview.Money.Deposits.Amount);
            Assert.Equal(1.5m, overview.Revenue.Fees.Amount);
            Assert.Equal(50, overview.Cards.DeclineRate);

            var controller = new AdminOperationsController(db, Service(db, hoppa, clock), new AdminKpiService(db, clock))
            {
                ControllerContext = new ControllerContext
                {
                    HttpContext = new DefaultHttpContext
                    {
                        User = new ClaimsPrincipal(new ClaimsIdentity([new Claim("company_installation_id", company.ToString())], "test"))
                    }
                }
            };
            foreach (var sort in new[] { "date", "customer", "amount", "kind" })
            {
                var result = Assert.IsType<OkObjectResult>(await controller.GetMoney(0, "openai", null, null, null, null, null, null, null, sort, "asc", 0, 25, default));
                var json = JsonSerializer.SerializeToElement(result.Value);
                Assert.Equal(1, json.GetProperty("totalCount").GetInt32());
            }

            var all = JsonSerializer.SerializeToElement(Assert.IsType<OkObjectResult>(
                await controller.GetMoney(0, null, user, "completed", null, null, "fee", null, null, null, null, 0, 25, default)).Value);
            Assert.Equal(2, all.GetProperty("totalCount").GetInt32());
            Assert.Equal(1.5m, all.GetProperty("activity")[0].GetProperty("outflow").GetDecimal());

            // Stage facts, stage filter and the reminder cooldown query translate to SQL.
            // The fake provider never approves this customer, so despite card purchases it has not started onboarding.
            var notStarted = JsonSerializer.SerializeToElement(Assert.IsType<OkObjectResult>(
                await controller.GetCustomers(null, null, null, null, null, null, AdminCustomerStages.SignedUp, null, 0, 25, default)).Value,
                new JsonSerializerOptions(JsonSerializerDefaults.Web));
            Assert.Equal(1, notStarted.GetProperty("totalCount").GetInt32());
            Assert.Equal(AdminCustomerStages.SignedUp, notStarted.GetProperty("items")[0].GetProperty("stage").GetString());
            var plan = await new AdminReminderService(db, new NeoBanking.Infrastructure.Email.EmailTemplateStore(db),
                    new NeoBanking.Infrastructure.Email.EmailOutbox(db, new NeoBanking.Infrastructure.Email.EmailTemplateStore(db), new LedgerCompanyContext(),
                        NullLogger<NeoBanking.Infrastructure.Email.EmailOutbox>.Instance),
                    Options.Create(new AdminRemindersOptions { AppUrl = "https://app.example.test" }), clock)
                .PlanAsync(company, AdminCustomerStages.Dormant, null, default);
            Assert.NotNull(plan);
        }
        finally
        {
            NpgsqlConnection.ClearAllPools();
            await using var drop = new NpgsqlCommand($"DROP DATABASE \"{name}\" WITH (FORCE)", admin);
            await drop.ExecuteNonQueryAsync();
        }
    }

    internal static JsonElement Row(string id, string type, decimal amount, string status, DateTimeOffset at,
        string currency = "USD", string? description = null, string? cardId = "card-1") =>
        JsonSerializer.SerializeToElement(new Dictionary<string, object?>
        {
            ["id"] = id,
            ["type"] = type,
            ["description"] = description ?? $"Type1: SHOP {id}",
            ["amount"] = amount,
            ["currency"] = currency,
            ["status"] = status,
            ["transactionDate"] = at.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture),
            ["cardId"] = type.StartsWith("card", StringComparison.Ordinal) ? cardId : null
        });

    private static NeoBankingDbContext Database() => new(new DbContextOptionsBuilder<NeoBankingDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    private static async Task<(Guid Company, Guid User)> Seed(NeoBankingDbContext db)
    {
        var company = new CompanyInstallation { Slug = "default", Status = "active" };
        db.CompanyInstallations.Add(company);
        await db.SaveChangesAsync();
        return (company.Id, await AdminCustomerSyncTests.AddUser(db, company.Id, "101"));
    }

    private static AdminCustomerSyncService Service(NeoBankingDbContext db, IHoppaClient hoppa, TimeProvider clock) =>
        new(db, hoppa, NullLogger<AdminCustomerSyncService>.Instance, Options.Create(new AdminCustomerSyncOptions()), clock);

    private sealed class LedgerCompanyContext : NeoBanking.Application.Company.ICompanyContextAccessor
    {
        public NeoBanking.Application.Company.ICompanyContext Current { get; private set; } = NeoBanking.Application.Company.CompanyContext.Empty;
        public void SetCurrent(NeoBanking.Application.Company.ICompanyContext context) => Current = context;
        public void Clear() { }
    }

    /// <summary>Serves the transactions feed newest first with Hoppa's pagination envelope.</summary>
    internal sealed class LedgerHoppa(List<JsonElement> rows) : IHoppaClient
    {
        public List<JsonElement> Rows { get; } = rows;
        public List<int> RequestedPages { get; } = [];

        public Task<ApplicationResult<TResponse>> SendAsync<TRequest, TResponse>(HoppaRequest<TRequest> request, CancellationToken cancellationToken)
        {
            string body;
            if (request.Path == "/api/v2/transactions")
            {
                var page = int.Parse(request.Query["page"]!, CultureInfo.InvariantCulture);
                var size = int.Parse(request.Query["pageSize"]!, CultureInfo.InvariantCulture);
                RequestedPages.Add(page);
                var ordered = Rows.OrderByDescending(row => row.GetProperty("transactionDate").GetString(), StringComparer.Ordinal).ToList();
                var slice = ordered.Skip((page - 1) * size).Take(size).ToList();
                var totalPages = (ordered.Count + size - 1) / size;
                body = JsonSerializer.Serialize(new
                {
                    data = slice,
                    pagination = new { page, pageSize = size, total = ordered.Count, totalPages, hasNext = page < totalPages }
                });
            }
            else
            {
                body = request.Path switch
                {
                    "/api/v2/users" => """{"users":[],"totalPages":1}""",
                    "/api/v2/cards" => """[{"id":"card-1","status":"active"}]""",
                    _ => "{}"
                };
            }

            return Task.FromResult(ApplicationResult<TResponse>.Success(JsonSerializer.Deserialize<TResponse>(body)!));
        }
    }
}
