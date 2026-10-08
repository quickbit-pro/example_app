using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Admin;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Admin;

/// <summary>
/// Where a customer is in the journey, for filters, drill-downs and reminders.
/// Stages are mutually exclusive and ordered; the Overview funnel counts the
/// same steps cumulatively.
/// </summary>
public static class AdminCustomerStages
{
    public const string SignedUp = "signed_up";
    public const string Onboarding = "onboarding";
    public const string InReview = "in_review";
    public const string Rejected = "rejected";
    public const string Approved = "approved";
    public const string Funded = "funded";
    public const string Carded = "carded";
    public const string Active = "active";
    public const string Dormant = "dormant";

    public static readonly IReadOnlyList<string> Ordered =
        [SignedUp, Onboarding, InReview, Rejected, Approved, Funded, Carded, Active, Dormant];

    /// <summary>A card user counts as active with any money movement they started in this window.</summary>
    public static readonly TimeSpan ActiveWindow = TimeSpan.FromDays(30);

    /// <summary>Ledger facts per customer: completed, primary, non-duplicate rows only.</summary>
    public sealed record Facts(bool ReceivedMoney, bool Purchased, DateTimeOffset? LastActivityAt);

    public static async Task<Dictionary<Guid, Facts>> LoadFactsAsync(
        NeoBankingDbContext dbContext, Guid companyId, CancellationToken cancellationToken)
    {
        var rows = await dbContext.AdminTransactions
            .AsNoTracking()
            .Where(row =>
                row.CompanyInstallationId == companyId &&
                row.IsPrimary &&
                !row.IsDuplicate &&
                row.Status == AdminTransactionStatuses.Completed &&
                (row.Kind == AdminTransactionKinds.Deposit ||
                 row.Kind == AdminTransactionKinds.Withdrawal ||
                 row.Kind == AdminTransactionKinds.CardPurchase ||
                 row.Kind == AdminTransactionKinds.CardCash ||
                 row.Kind == AdminTransactionKinds.CardFunding ||
                 row.Kind == AdminTransactionKinds.Conversion ||
                 row.Kind == AdminTransactionKinds.Transfer))
            .GroupBy(row => new { row.UserId, row.Kind, row.Direction })
            .Select(group => new { group.Key.UserId, group.Key.Kind, group.Key.Direction, Last = group.Max(row => row.OccurredAt) })
            .ToListAsync(cancellationToken);

        return rows
            .GroupBy(row => row.UserId)
            .ToDictionary(group => group.Key, group =>
            {
                var initiated = group.Where(row => row.Kind != AdminTransactionKinds.Transfer || row.Direction == AdminTransactionDirections.Out).ToList();
                return new Facts(
                    group.Any(row => row.Kind == AdminTransactionKinds.Deposit ||
                                     (row.Kind == AdminTransactionKinds.Transfer && row.Direction == AdminTransactionDirections.In)),
                    group.Any(row => row.Kind == AdminTransactionKinds.CardPurchase),
                    initiated.Count == 0 ? null : initiated.Max(row => row.Last));
            });
    }

    public static bool IsApproved(AdminCustomerSnapshot snapshot) =>
        snapshot.OnboardingStatus is "completed" or "approved" or "active" or "account_ready";

    public static bool IsRejected(AdminCustomerSnapshot snapshot) =>
        !IsApproved(snapshot) &&
        (snapshot.VerificationStatus is "rejected" or "failed" || snapshot.OnboardingStatus is "rejected" or "failed");

    public static bool Started(AdminCustomerSnapshot snapshot) =>
        snapshot.OnboardingStatus != "not_started" || snapshot.VerificationStatus != "not_started" || IsApproved(snapshot);

    public static bool Submitted(AdminCustomerSnapshot snapshot) =>
        Started(snapshot) && (snapshot.VerificationStatus != "not_started" || IsApproved(snapshot));

    public static bool HasMoney(AdminCustomerSnapshot snapshot, Facts? facts) =>
        facts?.ReceivedMoney == true ||
        snapshot.TotalCardCount > 0 ||
        ReadBalances(snapshot.BalanceSummaryJson).Values.Any(amount => amount > 0m);

    public static string Of(AdminCustomerSnapshot snapshot, Facts? facts, DateTimeOffset now)
    {
        if (IsRejected(snapshot)) return Rejected;
        if (!Started(snapshot)) return SignedUp;
        if (!Submitted(snapshot)) return Onboarding;
        if (!IsApproved(snapshot)) return InReview;
        if (facts?.Purchased == true)
        {
            return facts.LastActivityAt >= now - ActiveWindow ? Active : Dormant;
        }

        if (snapshot.TotalCardCount > 0) return Carded;
        return HasMoney(snapshot, facts) ? Funded : Approved;
    }

    private static Dictionary<string, decimal> ReadBalances(string json)
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
}
