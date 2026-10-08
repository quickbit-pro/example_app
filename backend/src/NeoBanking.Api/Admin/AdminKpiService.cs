using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Admin;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Admin;

public sealed record AdminMetric(double Current, double Previous);

public sealed record AdminAmountMetric(decimal Amount, decimal PreviousAmount, int Count, int PreviousCount);

public sealed record AdminAmountCount(decimal Amount, int Count);

public sealed record AdminFeeTypeRow(string Type, string Label, decimal Amount, int Count);

public sealed record AdminMerchantRow(string Name, decimal Amount, int Count);

public sealed record AdminFunnelStep(string Key, string Label, int Value);

public sealed record AdminCurrencyAmount(string Currency, decimal Amount);

public sealed record AdminDailyKpi(
    DateOnly Date, int Signups, int Approvals, decimal Deposits, decimal Withdrawals, decimal Spend, int Declines,
    decimal DeclinedAmount, decimal Fees);

public sealed record AdminAttentionItem(
    Guid CustomerId, string CustomerName, string CustomerType, string Reason, string Tone, int Priority, long AgeHours);

public sealed record AdminOverviewFreshness(string State, int StaleCustomers, int ErrorCustomers);

public sealed record AdminCustomerKpis(
    int Customers,
    AdminMetric NewCustomers,
    AdminMetric Approvals,
    int ApprovedCustomers,
    int FundedCustomers,
    double? ActivationRate,
    AdminMetric TransactingCustomers,
    int EngagedCustomers,
    int ActiveCards,
    AdminMetric CardsIssued,
    double VerifiedRate);

public sealed record AdminMoneyKpis(
    AdminAmountMetric Deposits,
    AdminAmountMetric Withdrawals,
    decimal NetDeposits,
    decimal FundsHeld,
    AdminAmountCount Transfers,
    int Conversions,
    IReadOnlyList<string> UnconvertedCurrencies);

public sealed record AdminCardKpis(
    AdminAmountMetric Spend,
    decimal? AverageTicket,
    AdminMetric ActiveCardholders,
    AdminAmountCount Declines,
    double? DeclineRate,
    double? PreviousDeclineRate,
    int Checks,
    AdminAmountCount Cash);

public sealed record AdminRevenueKpis(
    AdminAmountMetric Fees,
    IReadOnlyList<AdminFeeTypeRow> ByType,
    decimal? PerTransactingCustomer,
    decimal? PerActiveCardholder,
    AdminAmountCount OnDeclinedPayments);

public sealed record AdminVerificationAging(int Pending, int Over24Hours, int Rejected);

public sealed record AdminSupportQueue(int Awaiting, long? OldestWaitingHours);

public sealed record AdminStageCount(string Stage, int Count);

public sealed record AdminCohortWeek(int Offset, int Active, double? Rate);

public sealed record AdminCohort(DateOnly WeekStart, int Size, IReadOnlyList<AdminCohortWeek> Weeks);

public sealed record AdminDeclineMerchant(string Name, int Declined, decimal Amount, int Attempts, double? Rate);

public sealed record AdminDeclineReason(string Reason, int Count);

public sealed record AdminDeclineCard(string LastFour, int Count);

public sealed record AdminDeclineBreakdown(
    IReadOnlyList<AdminDeclineMerchant> ByMerchant,
    IReadOnlyList<AdminDeclineReason> ByReason,
    IReadOnlyList<AdminDeclineCard> ByCard);

public sealed record AdminSegmentRow(
    string Key, int Customers, int Approved, int Funded, int Transacting, decimal Spend, decimal Fees);

public sealed record AdminSegments(
    IReadOnlyList<AdminSegmentRow> Source,
    IReadOnlyList<AdminSegmentRow> Country,
    IReadOnlyList<AdminSegmentRow> Platform,
    IReadOnlyList<AdminSegmentRow> AppVersion);

public sealed record AdminOverviewResponse(
    int RangeDays,
    DateTimeOffset From,
    DateTimeOffset To,
    DateTimeOffset PreviousFrom,
    DateTimeOffset GeneratedAt,
    DateTimeOffset? UpdatedAt,
    string TimeZone,
    string ReportingCurrency,
    AdminOverviewFreshness Freshness,
    int TestCustomers,
    AdminCustomerKpis Kpis,
    AdminMoneyKpis Money,
    AdminCardKpis Cards,
    AdminRevenueKpis Revenue,
    IReadOnlyList<AdminDailyKpi> Series,
    IReadOnlyList<AdminMerchantRow> TopMerchants,
    IReadOnlyList<AdminFunnelStep> Funnel,
    IReadOnlyList<AdminStageCount> Stages,
    IReadOnlyList<AdminCohort> Cohorts,
    AdminDeclineBreakdown Declines,
    AdminSegments Segments,
    IReadOnlyList<AdminCurrencyAmount> Balances,
    IReadOnlyList<AdminAttentionItem> Attention,
    AdminVerificationAging VerificationAging,
    AdminSupportQueue Support);

/// <summary>
/// Operator KPIs for the Overview. Money figures come from the classified
/// ledger (admin_transactions): only primary, non-duplicate rows count, internal
/// movements (card top-ups, conversions) are never in/out, and amounts are
/// reported in USD with USD stablecoins at 1:1. Days follow the installation's
/// reporting time zone. Test accounts are left out.
/// </summary>
public sealed class AdminKpiService(NeoBankingDbContext dbContext, TimeProvider clock)
{
    private const int SegmentLimit = 8;

    private static readonly HashSet<string> UsdLike = new(StringComparer.OrdinalIgnoreCase)
    {
        "USD", "USDT", "USDC", "PYUSD", "DAI", "FDUSD", "TUSD", "USDP"
    };

    private static readonly HashSet<string> ApprovedStatuses = new(StringComparer.OrdinalIgnoreCase)
    {
        "approved", "verified", "completed", "passed"
    };

    private static readonly HashSet<string> PendingStatuses = new(StringComparer.OrdinalIgnoreCase)
    {
        "pending", "submitted", "reviewing", "manual_review", "in_review"
    };

    private static readonly Dictionary<string, string> FeeLabels = new()
    {
        ["card_issuance"] = "Card issuance",
        ["top_up"] = "Card top-up",
        ["card_payment"] = "Per purchase",
        ["decline"] = "Declined payment",
        ["monthly"] = "Monthly card",
        ["exchange"] = "Exchange",
        ["withdrawal"] = "Withdrawal",
        ["transfer"] = "Transfer",
        ["card"] = "Other card fees",
        ["other"] = "Other fees",
        ["reversal"] = "Refunded fees"
    };

    public async Task<AdminOverviewResponse> GetOverviewAsync(Guid companyId, int rangeDays, CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        var settingsJson = await dbContext.CompanyInstallations
            .AsNoTracking()
            .Where(company => company.Id == companyId)
            .Select(company => company.SettingsJson)
            .FirstOrDefaultAsync(cancellationToken);
        var timeZoneId = AdminReportingSettings.ReadTimeZone(settingsJson);
        var zone = AdminReportingSettings.Resolve(timeZoneId);
        DateOnly LocalDay(DateTimeOffset at) => DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(at, zone).DateTime);
        DateTimeOffset StartOf(DateOnly day)
        {
            var local = day.ToDateTime(TimeOnly.MinValue);
            return new DateTimeOffset(local, zone.GetUtcOffset(local));
        }

        var today = LocalDay(now);
        var firstDay = today.AddDays(1 - rangeDays);
        var from = StartOf(firstDay);
        var previousFrom = StartOf(firstDay.AddDays(-rangeDays));
        var cohortWeeks = rangeDays >= 90 ? 13 : 8;
        var currentWeek = WeekStart(today);
        var firstCohort = currentWeek.AddDays(-7 * (cohortWeeks - 1));
        var ledgerFrom = new[] { previousFrom, now.AddDays(-30), StartOf(firstCohort) }.Min();

        var testUsers = (await dbContext.AdminCustomerFlags
                .AsNoTracking()
                .Where(flag => flag.CompanyInstallationId == companyId && flag.IsTestAccount)
                .Select(flag => flag.UserId)
                .ToListAsync(cancellationToken))
            .ToHashSet();
        var allSnapshots = await dbContext.AdminCustomerSnapshots
            .AsNoTracking()
            .Include(snapshot => snapshot.User)
            .Where(snapshot =>
                snapshot.CompanyInstallationId == companyId &&
                snapshot.User != null &&
                snapshot.User.AdminProfile == null)
            .ToListAsync(cancellationToken);
        var customers = allSnapshots.Where(snapshot => !testUsers.Contains(snapshot.UserId)).ToList();
        var customerIds = customers.Select(snapshot => snapshot.UserId).ToHashSet();

        var ledger = (await dbContext.AdminTransactions
                .AsNoTracking()
                .Where(row =>
                    row.CompanyInstallationId == companyId &&
                    row.OccurredAt >= ledgerFrom &&
                    row.IsPrimary &&
                    !row.IsDuplicate)
                .Select(row => new LedgerRow(
                    row.UserId, row.OccurredAt, row.Kind, row.Status, row.Direction, row.Amount, row.Currency,
                    row.FeeType, row.Merchant, row.ClientReference, row.RelatedReference, row.ExternalReference,
                    row.StatusReason, row.CardReference))
                .ToListAsync(cancellationToken))
            .Where(row => customerIds.Contains(row.UserId))
            .ToList();
        var facts = await AdminCustomerStages.LoadFactsAsync(dbContext, companyId, cancellationToken);
        AdminCustomerStages.Facts? FactsOf(Guid userId) => facts.GetValueOrDefault(userId);

        var unconverted = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
        decimal Usd(decimal amount, string currency)
        {
            if (UsdLike.Contains(currency)) return amount;
            unconverted.Add(currency.ToUpperInvariant());
            return 0m;
        }

        decimal SumUsd(IEnumerable<LedgerRow> rows) => Round(rows.Sum(row => Usd(row.Amount, row.Currency)));
        bool Current(DateTimeOffset at) => at >= from && at <= now;
        bool Previous(DateTimeOffset at) => at >= previousFrom && at < from;
        IEnumerable<LedgerRow> Completed(string kind) =>
            ledger.Where(row => row.Kind == kind && row.Status == AdminTransactionStatuses.Completed);
        AdminAmountMetric AmountMetric(IEnumerable<LedgerRow> rows)
        {
            var list = rows.ToList();
            var current = list.Where(row => Current(row.OccurredAt)).ToList();
            var previous = list.Where(row => Previous(row.OccurredAt)).ToList();
            return new AdminAmountMetric(SumUsd(current), SumUsd(previous), current.Count, previous.Count);
        }

        bool Transacting(LedgerRow row) =>
            row.Status == AdminTransactionStatuses.Completed &&
            AdminTransactionKinds.CustomerInitiated.Contains(row.Kind) &&
            (row.Kind != AdminTransactionKinds.Transfer || row.Direction == AdminTransactionDirections.Out);

        // ---- customers ----
        var balances = SumCurrencies(customers.Select(snapshot => snapshot.BalanceSummaryJson));
        bool Approved(AdminCustomerSnapshot snapshot) => AdminCustomerStages.IsApproved(snapshot);
        bool Funded(AdminCustomerSnapshot snapshot) => Approved(snapshot) && AdminCustomerStages.HasMoney(snapshot, FactsOf(snapshot.UserId));
        DateTimeOffset? ApprovedAt(AdminCustomerSnapshot snapshot) =>
            Approved(snapshot) ? snapshot.OnboardingCompletedAt ?? snapshot.VerificationReviewedAt : null;
        var cardIssueDates = customers.SelectMany(snapshot => CardIssueDates(snapshot.CardSummaryJson)).ToList();
        var transactingCurrentUsers = ledger.Where(row => Transacting(row) && Current(row.OccurredAt)).Select(row => row.UserId).ToHashSet();
        var transactingPrevious = ledger.Where(row => Transacting(row) && Previous(row.OccurredAt)).Select(row => row.UserId).Distinct().Count();
        var approvedCustomers = customers.Count(Approved);
        var fundedCustomers = customers.Count(Funded);

        var kpis = new AdminCustomerKpis(
            customers.Count,
            new AdminMetric(
                customers.Count(snapshot => Current(snapshot.User!.CreatedAt)),
                customers.Count(snapshot => Previous(snapshot.User!.CreatedAt))),
            new AdminMetric(
                customers.Count(snapshot => ApprovedAt(snapshot) is { } at && Current(at)),
                customers.Count(snapshot => ApprovedAt(snapshot) is { } at && Previous(at))),
            approvedCustomers,
            fundedCustomers,
            Percent(fundedCustomers, approvedCustomers),
            new AdminMetric(transactingCurrentUsers.Count, transactingPrevious),
            customers.Count(snapshot => snapshot.User!.LastLoginAt >= from),
            customers.Sum(snapshot => snapshot.ActiveCardCount),
            new AdminMetric(cardIssueDates.Count(Current), cardIssueDates.Count(Previous)),
            Percent(customers.Count(snapshot => ApprovedStatuses.Contains(snapshot.VerificationStatus)), customers.Count) ?? 0);

        // ---- money ----
        var deposits = AmountMetric(Completed(AdminTransactionKinds.Deposit));
        var withdrawals = AmountMetric(Completed(AdminTransactionKinds.Withdrawal));
        var transfersOut = Completed(AdminTransactionKinds.Transfer)
            .Where(row => row.Direction == AdminTransactionDirections.Out && Current(row.OccurredAt))
            .ToList();
        var fundsHeld = Round(balances.Sum(pair => Usd(pair.Value, pair.Key)));

        // ---- cards ----
        var purchases = Completed(AdminTransactionKinds.CardPurchase).ToList();
        var refunds = Completed(AdminTransactionKinds.CardRefund).ToList();
        var gross = AmountMetric(purchases);
        var refunded = AmountMetric(refunds);
        var spend = gross with { Amount = gross.Amount - refunded.Amount, PreviousAmount = gross.PreviousAmount - refunded.PreviousAmount };
        var declinedRows = ledger
            .Where(row => row.Kind == AdminTransactionKinds.CardPurchase && row.Status == AdminTransactionStatuses.Failed)
            .ToList();
        var declinedCurrent = declinedRows.Where(row => Current(row.OccurredAt)).ToList();
        var declinedPrevious = declinedRows.Count(row => Previous(row.OccurredAt));
        var cash = Completed(AdminTransactionKinds.CardCash).Where(row => Current(row.OccurredAt)).ToList();
        var activeCardholders = new AdminMetric(
            purchases.Where(row => Current(row.OccurredAt)).Select(row => row.UserId).Distinct().Count(),
            purchases.Where(row => Previous(row.OccurredAt)).Select(row => row.UserId).Distinct().Count());
        var cards = new AdminCardKpis(
            spend,
            gross.Count == 0 ? null : Round(gross.Amount / gross.Count),
            activeCardholders,
            new AdminAmountCount(SumUsd(declinedCurrent), declinedCurrent.Count),
            Percent(declinedCurrent.Count, declinedCurrent.Count + gross.Count),
            Percent(declinedPrevious, declinedPrevious + gross.PreviousCount),
            ledger.Count(row => row.Kind == AdminTransactionKinds.CardCheck && Current(row.OccurredAt)),
            new AdminAmountCount(SumUsd(cash), cash.Count));

        // ---- revenue ----
        var fees = Completed(AdminTransactionKinds.Fee).ToList();
        var feeRefunds = Completed(AdminTransactionKinds.FeeRefund).ToList();
        var feeGross = AmountMetric(fees);
        var feeReturned = AmountMetric(feeRefunds);
        var netFees = feeGross with
        {
            Amount = feeGross.Amount - feeReturned.Amount,
            PreviousAmount = feeGross.PreviousAmount - feeReturned.PreviousAmount
        };
        var currentFees = fees.Where(row => Current(row.OccurredAt)).ToList();
        var byType = currentFees
            .GroupBy(row => row.FeeType ?? "other")
            .Select(group => new AdminFeeTypeRow(group.Key, FeeLabel(group.Key), SumUsd(group), group.Count()))
            .OrderByDescending(row => row.Amount)
            .ToList();
        var currentFeeRefunds = feeRefunds.Where(row => Current(row.OccurredAt)).ToList();
        if (currentFeeRefunds.Count > 0)
        {
            byType.Add(new AdminFeeTypeRow("reversal", FeeLabel("reversal"), -SumUsd(currentFeeRefunds), currentFeeRefunds.Count));
        }

        var declinedClients = declinedCurrent
            .Where(row => !string.IsNullOrWhiteSpace(row.ClientReference))
            .Select(row => row.ClientReference!)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var declinedExternal = declinedCurrent
            .Where(row => !string.IsNullOrWhiteSpace(row.ExternalReference))
            .Select(row => row.ExternalReference!)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var feesOnDeclines = currentFees
            .Where(row => row.FeeType == "decline" ||
                          (row.RelatedReference is { } related && declinedExternal.Contains(related)) ||
                          (ParentClient(row.ClientReference) is { } parent && declinedClients.Contains(parent)))
            .ToList();
        var revenue = new AdminRevenueKpis(
            netFees,
            byType,
            transactingCurrentUsers.Count == 0 ? null : Round(netFees.Amount / transactingCurrentUsers.Count),
            activeCardholders.Current == 0 ? null : Round(netFees.Amount / (decimal)activeCardholders.Current),
            new AdminAmountCount(SumUsd(feesOnDeclines), feesOnDeclines.Count));

        // ---- series (reporting-time-zone days) ----
        Dictionary<DateOnly, List<LedgerRow>> ByDay(IEnumerable<LedgerRow> rows) =>
            rows.GroupBy(row => LocalDay(row.OccurredAt)).ToDictionary(group => group.Key, group => group.ToList());
        var depositDays = ByDay(Completed(AdminTransactionKinds.Deposit));
        var withdrawalDays = ByDay(Completed(AdminTransactionKinds.Withdrawal));
        var purchaseDays = ByDay(purchases);
        var declineDays = ByDay(declinedRows);
        var feeDays = ByDay(fees);
        var feeRefundDays = ByDay(feeRefunds);
        var signupDays = customers.GroupBy(snapshot => LocalDay(snapshot.User!.CreatedAt)).ToDictionary(group => group.Key, group => group.Count());
        var approvalDays = customers
            .Select(ApprovedAt)
            .Where(at => at.HasValue)
            .GroupBy(at => LocalDay(at!.Value))
            .ToDictionary(group => group.Key, group => group.Count());
        decimal DaySum(Dictionary<DateOnly, List<LedgerRow>> days, DateOnly day) =>
            days.TryGetValue(day, out var rows) ? SumUsd(rows) : 0m;
        var series = Enumerable.Range(0, rangeDays)
            .Select(offset => firstDay.AddDays(offset))
            .Select(day => new AdminDailyKpi(
                day,
                signupDays.GetValueOrDefault(day),
                approvalDays.GetValueOrDefault(day),
                DaySum(depositDays, day),
                DaySum(withdrawalDays, day),
                DaySum(purchaseDays, day),
                declineDays.TryGetValue(day, out var declined) ? declined.Count : 0,
                DaySum(declineDays, day),
                DaySum(feeDays, day) - DaySum(feeRefundDays, day)))
            .ToList();

        var topMerchants = purchases
            .Where(row => Current(row.OccurredAt))
            .GroupBy(row => MerchantKey(row.Merchant))
            .Select(group => new AdminMerchantRow(group.Key, SumUsd(group), group.Count()))
            .OrderByDescending(row => row.Amount)
            .ThenByDescending(row => row.Count)
            .Take(8)
            .ToList();

        // ---- journey: the funnel counts steps cumulatively, stages say where each customer is now ----
        bool FundedStep(AdminCustomerSnapshot snapshot) => Funded(snapshot);
        bool Carded(AdminCustomerSnapshot snapshot) => FundedStep(snapshot) && snapshot.TotalCardCount > 0;
        bool Purchased(AdminCustomerSnapshot snapshot) => Carded(snapshot) && FactsOf(snapshot.UserId)?.Purchased == true;
        var funnel = new List<AdminFunnelStep>
        {
            new("signed_up", "Signed up", customers.Count),
            new("started", "Started onboarding", customers.Count(AdminCustomerStages.Started)),
            new("submitted", "Submitted verification", customers.Count(AdminCustomerStages.Submitted)),
            new("approved", "Approved", customers.Count(Approved)),
            new("funded", "Added money", customers.Count(FundedStep)),
            new("carded", "Got a card", customers.Count(Carded)),
            new("purchased", "Used the card", customers.Count(Purchased))
        };
        var stageOf = customers.ToDictionary(snapshot => snapshot.UserId, snapshot => AdminCustomerStages.Of(snapshot, FactsOf(snapshot.UserId), now));
        var stages = AdminCustomerStages.Ordered
            .Select(stage => new AdminStageCount(stage, stageOf.Values.Count(value => value == stage)))
            .ToList();

        // ---- weekly signup cohorts: share of each cohort that moved money in each later week ----
        var activeWeeks = ledger
            .Where(Transacting)
            .Select(row => (row.UserId, Week: WeekStart(LocalDay(row.OccurredAt))))
            .Distinct()
            .GroupBy(item => item.Week)
            .ToDictionary(group => group.Key, group => group.Select(item => item.UserId).ToHashSet());
        var cohorts = Enumerable.Range(0, cohortWeeks)
            .Select(index => firstCohort.AddDays(7 * index))
            .Select(week =>
            {
                var members = customers
                    .Where(snapshot => WeekStart(LocalDay(snapshot.User!.CreatedAt)) == week)
                    .Select(snapshot => snapshot.UserId)
                    .ToHashSet();
                var elapsed = (currentWeek.DayNumber - week.DayNumber) / 7;
                var weeks = Enumerable.Range(0, elapsed + 1)
                    .Select(offset =>
                    {
                        var active = activeWeeks.TryGetValue(week.AddDays(7 * offset), out var users) ? members.Count(users.Contains) : 0;
                        return new AdminCohortWeek(offset, active, Percent(active, members.Count));
                    })
                    .ToList();
                return new AdminCohort(week, members.Count, weeks);
            })
            .ToList();

        // ---- declines ----
        var settledByMerchant = purchases
            .Where(row => Current(row.OccurredAt))
            .GroupBy(row => MerchantKey(row.Merchant))
            .ToDictionary(group => group.Key, group => group.Count());
        var cardLastFour = customers
            .SelectMany(snapshot => CardReferences(snapshot.CardSummaryJson))
            .GroupBy(card => card.Reference, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First().LastFour, StringComparer.OrdinalIgnoreCase);
        var declines = new AdminDeclineBreakdown(
            declinedCurrent
                .GroupBy(row => MerchantKey(row.Merchant))
                .Select(group =>
                {
                    var attempts = group.Count() + settledByMerchant.GetValueOrDefault(group.Key);
                    return new AdminDeclineMerchant(group.Key, group.Count(), SumUsd(group), attempts, Percent(group.Count(), attempts));
                })
                .OrderByDescending(row => row.Declined)
                .ThenByDescending(row => row.Amount)
                .Take(8)
                .ToList(),
            declinedCurrent
                .GroupBy(row => string.IsNullOrWhiteSpace(row.StatusReason) ? "No reason given" : row.StatusReason.Trim())
                .Select(group => new AdminDeclineReason(group.Key, group.Count()))
                .OrderByDescending(row => row.Count)
                .Take(8)
                .ToList(),
            declinedCurrent
                .Where(row => !string.IsNullOrWhiteSpace(row.CardReference))
                .GroupBy(row => row.CardReference!, StringComparer.OrdinalIgnoreCase)
                .Select(group => new AdminDeclineCard(cardLastFour.GetValueOrDefault(group.Key) ?? "····", group.Count()))
                .OrderByDescending(row => row.Count)
                .Take(5)
                .ToList());

        // ---- segments ----
        var segments = await BuildSegmentsAsync(companyId, customers, ledger, Current, Transacting, Approved, Funded, Usd, cancellationToken);

        // ---- operations ----
        var attention = customers
            .Select(snapshot => (Snapshot: snapshot, Evaluation: AdminAttentionPolicy.Evaluate(snapshot, now)))
            .Where(item => item.Evaluation is not null)
            .Select(item => new AdminAttentionItem(
                item.Snapshot.UserId,
                item.Snapshot.User!.DisplayName ?? item.Snapshot.User.Email,
                item.Snapshot.CustomerType,
                item.Evaluation!.Reason,
                item.Evaluation.Tone,
                item.Evaluation.Priority,
                item.Evaluation.AgeHours))
            .OrderByDescending(item => item.Priority)
            .ThenByDescending(item => item.AgeHours)
            .Take(12)
            .ToList();
        var awaiting = await dbContext.SupportTickets
            .AsNoTracking()
            .Where(ticket => ticket.CompanyInstallationId == companyId && ticket.Status == SupportTicketStatuses.AwaitingSupport)
            .Select(ticket => ticket.UpdatedAt)
            .ToListAsync(cancellationToken);
        var lastSyncedAt = customers
            .Where(snapshot => snapshot.LastSyncedAt.HasValue)
            .Select(snapshot => snapshot.LastSyncedAt!.Value)
            .DefaultIfEmpty()
            .Min();
        var staleCustomers = customers.Count(snapshot => !snapshot.LastSyncedAt.HasValue || snapshot.LastSyncedAt < now - AdminAttentionPolicy.StaleAfter);
        var errorCustomers = customers.Count(snapshot => HasActionableSyncError(snapshot.LastSyncError));

        var money = new AdminMoneyKpis(
            deposits,
            withdrawals,
            deposits.Amount - withdrawals.Amount,
            fundsHeld,
            new AdminAmountCount(SumUsd(transfersOut), transfersOut.Count),
            Completed(AdminTransactionKinds.Conversion).Count(row => Current(row.OccurredAt)),
            unconverted.ToList());
        return new AdminOverviewResponse(
            rangeDays,
            from,
            now,
            previousFrom,
            now,
            lastSyncedAt == default ? null : lastSyncedAt,
            timeZoneId,
            "USD",
            new AdminOverviewFreshness(
                errorCustomers > 0 ? "warning" : staleCustomers > 0 ? "stale" : "current",
                staleCustomers,
                errorCustomers),
            allSnapshots.Count - customers.Count,
            kpis,
            money,
            cards,
            revenue,
            series,
            topMerchants,
            funnel,
            stages,
            cohorts,
            declines,
            segments,
            balances.Select(pair => new AdminCurrencyAmount(pair.Key, pair.Value)).ToList(),
            attention,
            new AdminVerificationAging(
                customers.Count(snapshot => PendingStatuses.Contains(snapshot.VerificationStatus)),
                customers.Count(snapshot =>
                    PendingStatuses.Contains(snapshot.VerificationStatus) &&
                    (snapshot.VerificationSubmittedAt ?? snapshot.OnboardingStartedAt) < now.AddHours(-24)),
                customers.Count(snapshot => snapshot.VerificationStatus is "rejected" or "failed")),
            new AdminSupportQueue(
                awaiting.Count,
                awaiting.Count == 0 ? null : (long)Math.Max(0, (now - awaiting.Min()).TotalHours)));
    }

    /// <summary>
    /// Customers split by how they arrived (referral signup or organic), KYC country
    /// (falling back to the app locale), app platform and app version.
    /// </summary>
    private async Task<AdminSegments> BuildSegmentsAsync(
        Guid companyId,
        IReadOnlyList<AdminCustomerSnapshot> customers,
        IReadOnlyList<LedgerRow> ledger,
        Func<DateTimeOffset, bool> current,
        Func<LedgerRow, bool> transacting,
        Func<AdminCustomerSnapshot, bool> approved,
        Func<AdminCustomerSnapshot, bool> funded,
        Func<decimal, string, decimal> usd,
        CancellationToken cancellationToken)
    {
        var referred = (await dbContext.ReferralSignupAttempts
                .AsNoTracking()
                .Where(attempt => attempt.CompanyInstallationId == companyId && attempt.LocalUserId != null)
                .Select(attempt => attempt.LocalUserId!.Value)
                .ToListAsync(cancellationToken))
            .ToHashSet();
        var devices = (await dbContext.PushDevices
                .AsNoTracking()
                .Where(device => device.CompanyInstallationId == companyId)
                .Select(device => new { device.UserId, device.Platform, device.AppVersion, device.LastSeenAt })
                .ToListAsync(cancellationToken))
            .GroupBy(device => device.UserId)
            .ToDictionary(group => group.Key, group => group.OrderByDescending(device => device.LastSeenAt).First());
        var sessionSince = clock.GetUtcNow().AddDays(-180);
        var agents = (await dbContext.RefreshSessions
                .AsNoTracking()
                .Where(session => session.CompanyInstallationId == companyId && session.CreatedAt >= sessionSince)
                .Select(session => new { session.UserId, session.UserAgent, session.CreatedAt })
                .ToListAsync(cancellationToken))
            .GroupBy(session => session.UserId)
            .ToDictionary(group => group.Key, group => group.OrderByDescending(session => session.CreatedAt).First().UserAgent);

        var byUser = ledger.GroupBy(row => row.UserId).ToDictionary(group => group.Key, group => group.ToList());
        IReadOnlyList<AdminSegmentRow> Split(Func<AdminCustomerSnapshot, string> key)
        {
            var rows = customers
                .GroupBy(key)
                .Select(group =>
                {
                    var users = group.Select(snapshot => snapshot.UserId).ToHashSet();
                    var rowsOf = users.SelectMany(user => byUser.GetValueOrDefault(user) ?? []).Where(row => current(row.OccurredAt)).ToList();
                    var fees = rowsOf.Where(row => row.Kind == AdminTransactionKinds.Fee && row.Status == AdminTransactionStatuses.Completed).Sum(row => usd(row.Amount, row.Currency)) -
                               rowsOf.Where(row => row.Kind == AdminTransactionKinds.FeeRefund && row.Status == AdminTransactionStatuses.Completed).Sum(row => usd(row.Amount, row.Currency));
                    return new AdminSegmentRow(
                        group.Key,
                        group.Count(),
                        group.Count(approved),
                        group.Count(funded),
                        rowsOf.Where(transacting).Select(row => row.UserId).Distinct().Count(),
                        Round(rowsOf.Where(row => row.Kind == AdminTransactionKinds.CardPurchase && row.Status == AdminTransactionStatuses.Completed).Sum(row => usd(row.Amount, row.Currency))),
                        Round(fees));
                })
                .OrderByDescending(row => row.Customers)
                .ToList();
            if (rows.Count <= SegmentLimit)
            {
                return rows;
            }

            var rest = rows.Skip(SegmentLimit - 1).ToList();
            return
            [
                .. rows.Take(SegmentLimit - 1),
                new AdminSegmentRow("Other", rest.Sum(row => row.Customers), rest.Sum(row => row.Approved), rest.Sum(row => row.Funded),
                    rest.Sum(row => row.Transacting), rest.Sum(row => row.Spend), rest.Sum(row => row.Fees))
            ];
        }

        return new AdminSegments(
            Split(snapshot => referred.Contains(snapshot.UserId) ? "Referral" : "Organic"),
            Split(snapshot => CountryOf(snapshot) ?? "Unknown"),
            Split(snapshot => devices.TryGetValue(snapshot.UserId, out var device)
                ? Platform(device.Platform) ?? PlatformFromAgent(agents.GetValueOrDefault(snapshot.UserId))
                : PlatformFromAgent(agents.GetValueOrDefault(snapshot.UserId))),
            Split(snapshot => devices.TryGetValue(snapshot.UserId, out var device) && !string.IsNullOrWhiteSpace(device.AppVersion)
                ? device.AppVersion!.Trim()
                : "Unknown"));
    }

    public static bool HasActionableSyncError(string? error) =>
        !string.IsNullOrWhiteSpace(error) &&
        !error.Contains("not yet connected", StringComparison.OrdinalIgnoreCase);

    public static bool IsComplete(string? status) => status is "completed" or "approved" or "active" or "account_ready";

    public static SortedDictionary<string, decimal> SumCurrencies(IEnumerable<string> documents)
    {
        var totals = new SortedDictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);
        foreach (var document in documents)
        {
            foreach (var pair in ReadCurrencies(document).Where(pair => AdminCustomerSyncService.IsVisibleBalanceCurrency(pair.Key)))
            {
                totals[pair.Key] = totals.GetValueOrDefault(pair.Key) + pair.Value;
            }
        }

        if (totals.Values.Any(value => value != 0m))
        {
            foreach (var currency in totals.Where(item => item.Value == 0m).Select(item => item.Key).ToArray())
            {
                totals.Remove(currency);
            }
        }

        return totals;
    }

    /// <summary>Monday of the week that contains <paramref name="day"/>.</summary>
    public static DateOnly WeekStart(DateOnly day) => day.AddDays(-(((int)day.DayOfWeek + 6) % 7));

    private static string MerchantKey(string? merchant) =>
        string.IsNullOrWhiteSpace(merchant) ? "Unknown merchant" : merchant.Trim().ToUpperInvariant();

    private static string? CountryOf(AdminCustomerSnapshot snapshot)
    {
        try
        {
            using var document = JsonDocument.Parse(snapshot.VerificationDetailsJson);
            if (document.RootElement.ValueKind == JsonValueKind.Object &&
                document.RootElement.TryGetProperty("countryCode", out var code) &&
                code.ValueKind == JsonValueKind.String &&
                code.GetString() is { Length: 2 or 3 } country)
            {
                return country.ToUpperInvariant();
            }
        }
        catch (JsonException)
        {
            // Fall back to the app locale.
        }

        var locale = snapshot.User?.Locale;
        var separator = locale?.IndexOfAny(['-', '_']) ?? -1;
        return separator > 0 && locale!.Length - separator - 1 == 2 ? locale[(separator + 1)..].ToUpperInvariant() : null;
    }

    private static string? Platform(string? platform) => platform?.Trim().ToLowerInvariant() switch
    {
        "ios" or "iphone" or "ipad" or "apns" => "iOS",
        "android" or "fcm" => "Android",
        "web" or "pwa" or "webpush" => "Web",
        _ => null
    };

    private static string PlatformFromAgent(string? agent)
    {
        if (string.IsNullOrWhiteSpace(agent)) return "Unknown";
        if (agent.Contains("iPhone", StringComparison.OrdinalIgnoreCase) || agent.Contains("iPad", StringComparison.OrdinalIgnoreCase) ||
            agent.Contains("iOS", StringComparison.Ordinal)) return "iOS";
        return agent.Contains("Android", StringComparison.OrdinalIgnoreCase) ? "Android" : "Web";
    }

    private static Dictionary<string, decimal> ReadCurrencies(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<Dictionary<string, decimal>>(json) ?? [];
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private static IEnumerable<DateTimeOffset> CardIssueDates(string json) =>
        CardReferences(json).Where(card => card.IssuedAt.HasValue).Select(card => card.IssuedAt!.Value);

    private static IReadOnlyList<(string Reference, string LastFour, DateTimeOffset? IssuedAt)> CardReferences(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Array)
            {
                return [];
            }

            return document.RootElement.EnumerateArray()
                .Where(card => card.ValueKind == JsonValueKind.Object)
                .Select(card => (
                    card.TryGetProperty("reference", out var reference) ? reference.ToString() : string.Empty,
                    card.TryGetProperty("lastFour", out var lastFour) ? lastFour.ToString() : string.Empty,
                    card.TryGetProperty("issuedAt", out var issued) && issued.ValueKind == JsonValueKind.String && issued.TryGetDateTimeOffset(out var at)
                        ? at
                        : (DateTimeOffset?)null))
                .ToList();
        }
        catch (JsonException)
        {
            return [];
        }
    }

    /// <summary>"2094723116296110081_Fee_Consumption" → "2094723116296110081".</summary>
    private static string? ParentClient(string? client)
    {
        if (string.IsNullOrWhiteSpace(client))
        {
            return null;
        }

        foreach (var suffix in new[] { "_Fee_Consumption", "_Fee_Declination" })
        {
            if (client.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
            {
                return client[..^suffix.Length];
            }
        }

        return null;
    }

    private static string FeeLabel(string type) => FeeLabels.GetValueOrDefault(type, "Other fees");

    private static double? Percent(int numerator, int denominator) =>
        denominator == 0 ? null : Math.Round(numerator * 100d / denominator, 1);

    private static decimal Round(decimal value) => decimal.Round(value, 2, MidpointRounding.AwayFromZero);

    private sealed record LedgerRow(
        Guid UserId,
        DateTimeOffset OccurredAt,
        string Kind,
        string Status,
        string Direction,
        decimal Amount,
        string Currency,
        string? FeeType,
        string? Merchant,
        string? ClientReference,
        string? RelatedReference,
        string? ExternalReference,
        string? StatusReason,
        string? CardReference);
}
