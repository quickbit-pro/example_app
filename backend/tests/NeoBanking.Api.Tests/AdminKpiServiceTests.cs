using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Admin;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Admin;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AdminKpiServiceTests
{
    internal static readonly DateTimeOffset Now = new(2026, 9, 25, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task MoneyKpisCountEachExternalMovementOnce_AndLeaveTestAccountsOut()
    {
        await using var db = Database();
        var company = await CreateCompany(db);
        var spender = await Customer(db, company, "spender", Now.AddDays(-10), approved: true, cards: 1);
        var saver = await Customer(db, company, "saver", Now.AddDays(-40), approved: true);
        var tester = await Customer(db, company, "tester", Now.AddDays(-5), approved: true, cards: 1);
        await Customer(db, company, "browser", Now.AddDays(-3), approved: false);
        db.AdminCustomerFlags.Add(new AdminCustomerFlag { CompanyInstallationId = company, UserId = tester, IsTestAccount = true });

        Ledger(db, company, spender, "d1", AdminTransactionKinds.Deposit, 100m, Now.AddDays(-2), currency: "USDT");
        Ledger(db, company, spender, "c1", AdminTransactionKinds.Conversion, 100m, Now.AddDays(-2));
        Ledger(db, company, spender, "l1", AdminTransactionKinds.CardFunding, 90m, Now.AddDays(-2));
        Ledger(db, company, spender, "p1", AdminTransactionKinds.CardPurchase, 30m, Now.AddDays(-1), merchant: "OPENAI");
        Ledger(db, company, spender, "p2", AdminTransactionKinds.CardPurchase, 20m, Now.AddDays(-1), merchant: "MIGROS");
        Ledger(db, company, spender, "p3", AdminTransactionKinds.CardPurchase, 50m, Now.AddDays(-1), merchant: "OPENAI",
            status: AdminTransactionStatuses.Failed, client: "2094");
        Ledger(db, company, spender, "r1", AdminTransactionKinds.CardRefund, 5m, Now.AddDays(-1));
        Ledger(db, company, spender, "f1", AdminTransactionKinds.Fee, 0.5m, Now.AddDays(-1), feeType: "decline");
        Ledger(db, company, spender, "f2", AdminTransactionKinds.Fee, 0.5m, Now.AddDays(-1), feeType: "card_payment", client: "2094_Fee_Consumption");
        Ledger(db, company, spender, "f3", AdminTransactionKinds.Fee, 9.99m, Now.AddDays(-2), feeType: "card_issuance");
        Ledger(db, company, spender, "f4", AdminTransactionKinds.FeeRefund, 4m, Now.AddDays(-1), feeType: "card_issuance");
        Ledger(db, company, spender, "f5", AdminTransactionKinds.Fee, 1.5m, Now.AddDays(-1), feeType: "monthly", duplicate: true);
        Ledger(db, company, spender, "x1", AdminTransactionKinds.Deposit, 100m, Now.AddDays(-2), primary: false);
        Ledger(db, company, saver, "d2", AdminTransactionKinds.Deposit, 40m, Now.AddDays(-35));
        Ledger(db, company, saver, "w1", AdminTransactionKinds.Withdrawal, 10m, Now.AddDays(-3));
        Ledger(db, company, saver, "e1", AdminTransactionKinds.Deposit, 20m, Now.AddDays(-3), currency: "EUR");
        Ledger(db, company, tester, "t1", AdminTransactionKinds.CardPurchase, 999m, Now.AddDays(-1));
        await db.SaveChangesAsync();

        var overview = await new AdminKpiService(db, new FixedClock(Now)).GetOverviewAsync(company, 30, default);

        Assert.Equal(3, overview.Kpis.Customers);
        Assert.Equal(1, overview.TestCustomers);
        Assert.Equal(100m, overview.Money.Deposits.Amount);
        Assert.Equal(2, overview.Money.Deposits.Count); // counts cover every currency; the USD amount leaves EUR out
        Assert.Equal(40m, overview.Money.Deposits.PreviousAmount);
        Assert.Equal(["EUR"], overview.Money.UnconvertedCurrencies);
        Assert.Equal(10m, overview.Money.Withdrawals.Amount);
        Assert.Equal(90m, overview.Money.NetDeposits);
        Assert.Equal(45m, overview.Cards.Spend.Amount);
        Assert.Equal(2, overview.Cards.Spend.Count);
        Assert.Equal(25m, overview.Cards.AverageTicket);
        Assert.Equal(1, overview.Cards.Declines.Count);
        Assert.Equal(33.3, overview.Cards.DeclineRate);
        Assert.Equal(1, overview.Cards.ActiveCardholders.Current);
        Assert.Equal(6.99m, overview.Revenue.Fees.Amount);
        Assert.Equal(1m, overview.Revenue.OnDeclinedPayments.Amount);
        Assert.Equal(2, overview.Revenue.OnDeclinedPayments.Count);
        Assert.Contains(overview.Revenue.ByType, row => row.Type == "reversal" && row.Amount == -4m);
        Assert.DoesNotContain(overview.Revenue.ByType, row => row.Type == "monthly");
        Assert.Equal(2, overview.Kpis.TransactingCustomers.Current);
        Assert.Equal("OPENAI", overview.TopMerchants[0].Name);
        Assert.Equal(30, overview.Series.Count);
        Assert.Equal(new DateOnly(2026, 9, 25), overview.Series[^1].Date);
        Assert.Equal(45m, overview.Series.Sum(day => day.Spend) - 5m);
    }

    [Fact]
    public async Task FunnelNeverWidens_AndActivationCountsApprovedCustomersWhoAddedMoney()
    {
        await using var db = Database();
        var company = await CreateCompany(db);
        var funded = await Customer(db, company, "funded", Now.AddDays(-10), approved: true, cards: 1);
        await Customer(db, company, "approved", Now.AddDays(-10), approved: true);
        var odd = await Customer(db, company, "odd", Now.AddDays(-10), approved: false, verification: "pending");
        await Customer(db, company, "new", Now.AddDays(-1), approved: false);
        Ledger(db, company, funded, "d1", AdminTransactionKinds.Deposit, 10m, Now.AddDays(-5));
        Ledger(db, company, funded, "p1", AdminTransactionKinds.CardPurchase, 5m, Now.AddDays(-4));
        // Deposit on an unapproved account must not skip the approval step.
        Ledger(db, company, odd, "d2", AdminTransactionKinds.Deposit, 10m, Now.AddDays(-5));
        await db.SaveChangesAsync();

        var overview = await new AdminKpiService(db, new FixedClock(Now)).GetOverviewAsync(company, 30, default);

        Assert.Equal([4, 3, 3, 2, 1, 1, 1], overview.Funnel.Select(step => step.Value));
        for (var index = 1; index < overview.Funnel.Count; index++)
            Assert.True(overview.Funnel[index].Value <= overview.Funnel[index - 1].Value);
        Assert.Equal(2, overview.Kpis.ApprovedCustomers);
        Assert.Equal(1, overview.Kpis.FundedCustomers);
        Assert.Equal(50, overview.Kpis.ActivationRate);
    }

    [Fact]
    public async Task OverviewJsonMatchesTheAdminPanelContract()
    {
        await using var db = Database();
        var company = await CreateCompany(db);
        await Customer(db, company, "one", Now.AddDays(-2), approved: true, cards: 1);
        var overview = await new AdminKpiService(db, new FixedClock(Now)).GetOverviewAsync(company, 7, default);

        // ASP.NET serializes with the web defaults; admin_vue/src/lib/operationsApi.ts OverviewData reads these names.
        var json = JsonSerializer.SerializeToElement(overview, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        string[] Names(JsonElement element) => element.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal).ToArray();
        Assert.Equal(["attention", "balances", "cards", "cohorts", "declines", "freshness", "from", "funnel", "generatedAt", "kpis", "money", "previousFrom",
            "rangeDays", "reportingCurrency", "revenue", "segments", "series", "stages", "support", "testCustomers", "timeZone", "to", "topMerchants",
            "updatedAt", "verificationAging"], Names(json));
        Assert.Equal(["byCard", "byMerchant", "byReason"], Names(json.GetProperty("declines")));
        Assert.Equal(["appVersion", "country", "platform", "source"], Names(json.GetProperty("segments")));
        Assert.Equal(["approved", "customers", "fees", "funded", "key", "spend", "transacting"], Names(json.GetProperty("segments").GetProperty("source")[0]));
        Assert.Equal(["size", "weekStart", "weeks"], Names(json.GetProperty("cohorts")[0]));
        Assert.Equal(["active", "offset", "rate"], Names(json.GetProperty("cohorts")[0].GetProperty("weeks")[0]));
        Assert.Equal(["count", "stage"], Names(json.GetProperty("stages")[0]));
        Assert.Equal(["activationRate", "activeCards", "approvals", "approvedCustomers", "cardsIssued", "customers", "engagedCustomers", "fundedCustomers",
            "newCustomers", "transactingCustomers", "verifiedRate"], Names(json.GetProperty("kpis")));
        Assert.Equal(["current", "previous"], Names(json.GetProperty("kpis").GetProperty("newCustomers")));
        Assert.Equal(["conversions", "deposits", "fundsHeld", "netDeposits", "transfers", "unconvertedCurrencies", "withdrawals"], Names(json.GetProperty("money")));
        Assert.Equal(["amount", "count", "previousAmount", "previousCount"], Names(json.GetProperty("money").GetProperty("deposits")));
        Assert.Equal(["activeCardholders", "averageTicket", "cash", "checks", "declineRate", "declines", "previousDeclineRate", "spend"], Names(json.GetProperty("cards")));
        Assert.Equal(["byType", "fees", "onDeclinedPayments", "perActiveCardholder", "perTransactingCustomer"], Names(json.GetProperty("revenue")));
        Assert.Equal(["approvals", "date", "declinedAmount", "declines", "deposits", "fees", "signups", "spend", "withdrawals"], Names(json.GetProperty("series")[0]));
        Assert.Equal("2026-09-25", json.GetProperty("series")[6].GetProperty("date").GetString());
        Assert.Equal(["awaiting", "oldestWaitingHours"], Names(json.GetProperty("support")));
        Assert.Equal(["errorCustomers", "staleCustomers", "state"], Names(json.GetProperty("freshness")));
        Assert.Equal(["key", "label", "value"], Names(json.GetProperty("funnel")[0]));
    }

    [Fact]
    public async Task DaysFollowTheReportingTimeZone()
    {
        await using var db = Database();
        var company = await CreateCompany(db);
        var companyRow = await db.CompanyInstallations.SingleAsync();
        companyRow.SettingsJson = AdminReportingSettings.WriteTimeZone(companyRow.SettingsJson, "Europe/Berlin");
        var user = await Customer(db, company, "late", Now.AddDays(-10), approved: true, cards: 1);
        // 23:30 UTC on 23 September is already 24 September in Berlin (UTC+2).
        Ledger(db, company, user, "p1", AdminTransactionKinds.CardPurchase, 10m, new DateTimeOffset(2026, 9, 23, 23, 30, 0, TimeSpan.Zero), merchant: "SHOP");
        await db.SaveChangesAsync();

        var overview = await new AdminKpiService(db, new FixedClock(Now)).GetOverviewAsync(company, 7, default);

        Assert.Equal("Europe/Berlin", overview.TimeZone);
        Assert.Equal(10m, overview.Series.Single(day => day.Date == new DateOnly(2026, 9, 24)).Spend);
        Assert.Equal(0m, overview.Series.Single(day => day.Date == new DateOnly(2026, 9, 23)).Spend);
        Assert.Equal(new DateTimeOffset(2026, 9, 18, 22, 0, 0, TimeSpan.Zero), overview.From);
    }

    [Fact]
    public async Task StagesCohortsDeclinesAndSegmentsDescribeTheSameCustomers()
    {
        await using var db = Database();
        var company = await CreateCompany(db);
        var active = await Customer(db, company, "active", Now.AddDays(-9), approved: true, cards: 1, verificationCountry: "DE");
        var unfunded = await Customer(db, company, "unfunded", Now.AddDays(-9), approved: true, locale: "tr-TR");
        await Customer(db, company, "new", Now.AddDays(-1), approved: false);
        db.ReferralSignupAttempts.Add(new ReferralSignupAttempt { CompanyInstallationId = company, LocalUserId = active, State = "ACCOUNT_CREATED" });
        db.PushDevices.Add(new PushDevice { CompanyInstallationId = company, UserId = active, Platform = "ios", AppVersion = "2.4.0", RegistrationToken = "t" });
        db.PushDevices.Add(new PushDevice { CompanyInstallationId = company, UserId = unfunded, Platform = "android", AppVersion = "2.3.1", RegistrationToken = "u" });
        Ledger(db, company, active, "d1", AdminTransactionKinds.Deposit, 50m, Now.AddDays(-8));
        Ledger(db, company, active, "p1", AdminTransactionKinds.CardPurchase, 20m, Now.AddDays(-2), merchant: "OPENAI", card: "card-1");
        Ledger(db, company, active, "p2", AdminTransactionKinds.CardPurchase, 30m, Now.AddDays(-2), merchant: "OPENAI", status: AdminTransactionStatuses.Failed,
            reason: "Insufficient funds", card: "card-1");
        Ledger(db, company, active, "p3", AdminTransactionKinds.CardPurchase, 5m, Now.AddDays(-2), merchant: "MIGROS", status: AdminTransactionStatuses.Failed, card: "card-1");
        Ledger(db, company, active, "f1", AdminTransactionKinds.Fee, 1m, Now.AddDays(-2), feeType: "card_issuance");
        await db.SaveChangesAsync();

        var overview = await new AdminKpiService(db, new FixedClock(Now)).GetOverviewAsync(company, 30, default);

        var stages = overview.Stages.ToDictionary(stage => stage.Stage, stage => stage.Count);
        Assert.Equal(1, stages[AdminCustomerStages.Active]);
        Assert.Equal(1, stages[AdminCustomerStages.Approved]);
        Assert.Equal(1, stages[AdminCustomerStages.SignedUp]);
        Assert.Equal(3, stages.Values.Sum());

        var merchant = Assert.Single(overview.Declines.ByMerchant, row => row.Name == "OPENAI");
        Assert.Equal((1, 2, 50.0), (merchant.Declined, merchant.Attempts, merchant.Rate));
        Assert.Contains(overview.Declines.ByReason, row => row.Reason == "Insufficient funds" && row.Count == 1);
        Assert.Contains(overview.Declines.ByReason, row => row.Reason == "No reason given" && row.Count == 1);
        Assert.Equal(("1234", 2), (overview.Declines.ByCard[0].LastFour, overview.Declines.ByCard[0].Count));

        var cohort = overview.Cohorts.Single(item => item.Size == 2);
        Assert.Equal(new DateOnly(2026, 9, 14), cohort.WeekStart);
        Assert.Equal([50.0, 50.0], cohort.Weeks.Select(week => week.Rate ?? -1));
        Assert.All(overview.Cohorts, item => Assert.Equal(item.Weeks.Count, (new DateOnly(2026, 9, 21).DayNumber - item.WeekStart.DayNumber) / 7 + 1));

        Assert.Contains(overview.Segments.Source, row => row.Key == "Referral" && row.Customers == 1 && row.Transacting == 1 && row.Spend == 20m && row.Fees == 1m);
        Assert.Contains(overview.Segments.Source, row => row.Key == "Organic" && row.Customers == 2);
        Assert.Contains(overview.Segments.Country, row => row.Key == "DE" && row.Customers == 1);
        Assert.Contains(overview.Segments.Country, row => row.Key == "TR" && row.Customers == 1);
        Assert.Contains(overview.Segments.Platform, row => row.Key == "iOS" && row.Customers == 1);
        Assert.Contains(overview.Segments.Platform, row => row.Key == "Android" && row.Customers == 1);
        Assert.Contains(overview.Segments.AppVersion, row => row.Key == "2.4.0");
        Assert.Equal(1m, overview.Revenue.PerActiveCardholder);
    }

    internal static NeoBankingDbContext Database() => new(new DbContextOptionsBuilder<NeoBankingDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    internal static async Task<Guid> CreateCompany(NeoBankingDbContext db)
    {
        var company = new CompanyInstallation { Slug = "default", Status = "active" };
        db.CompanyInstallations.Add(company);
        await db.SaveChangesAsync();
        return company.Id;
    }

    internal static async Task<Guid> Customer(NeoBankingDbContext db, Guid company, string name, DateTimeOffset createdAt,
        bool approved, int cards = 0, string? verification = null, string? verificationCountry = null, string locale = "en-US",
        DateTimeOffset? emailVerifiedAt = null)
    {
        var user = new ApplicationUser
        {
            CompanyInstallationId = company, Email = $"{name}@example.test", EmailNormalized = $"{name.ToUpperInvariant()}@EXAMPLE.TEST",
            DisplayName = name, CreatedAt = createdAt, LastLoginAt = Now.AddDays(-1), Locale = locale, EmailVerifiedAt = emailVerifiedAt ?? createdAt
        };
        db.Users.Add(user);
        db.AdminCustomerSnapshots.Add(new AdminCustomerSnapshot
        {
            CompanyInstallationId = company,
            UserId = user.Id,
            OnboardingStatus = approved ? "completed" : "not_started",
            OnboardingStep = approved ? "account_ready" : "start",
            OnboardingCompletedAt = approved ? createdAt.AddDays(1) : null,
            VerificationStatus = verification ?? (approved ? "approved" : "not_started"),
            TotalCardCount = cards,
            ActiveCardCount = cards,
            CardSummaryJson = cards > 0 ? "[{\"reference\":\"card-1\",\"lastFour\":\"1234\",\"status\":\"active\",\"issuedAt\":\"" + createdAt.AddDays(1).ToString("O") + "\"}]" : "[]",
            VerificationDetailsJson = verificationCountry is null ? "{}" : "{\"countryCode\":\"" + verificationCountry + "\"}",
            LastSyncedAt = Now.AddMinutes(-5)
        });
        await db.SaveChangesAsync();
        return user.Id;
    }

    internal static void Ledger(NeoBankingDbContext db, Guid company, Guid user, string id, string kind, decimal amount,
        DateTimeOffset at, string currency = "USD", string status = AdminTransactionStatuses.Completed, string? merchant = null,
        string? feeType = null, string? client = null, bool duplicate = false, bool primary = true, string? reason = null, string? card = null) =>
        db.AdminTransactions.Add(new AdminTransaction
        {
            CompanyInstallationId = company,
            UserId = user,
            ProviderTransactionId = id,
            OccurredAt = at,
            Kind = kind,
            Status = status,
            Direction = kind switch
            {
                AdminTransactionKinds.Deposit or AdminTransactionKinds.CardRefund or AdminTransactionKinds.FeeRefund => AdminTransactionDirections.In,
                AdminTransactionKinds.Conversion or AdminTransactionKinds.CardFunding => AdminTransactionDirections.Internal,
                _ => AdminTransactionDirections.Out
            },
            Amount = amount,
            Currency = currency,
            Merchant = merchant,
            FeeType = feeType,
            ClientReference = client,
            StatusReason = reason,
            CardReference = card,
            IsDuplicate = duplicate,
            IsPrimary = primary
        });

    internal sealed class FixedClock(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
