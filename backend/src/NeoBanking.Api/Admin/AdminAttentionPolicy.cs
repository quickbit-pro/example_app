using NeoBanking.Domain.Entities;

namespace NeoBanking.Api.Admin;

public sealed record AdminAttentionEvaluation(
    string Reason,
    string Tone,
    int Priority,
    long AgeHours);

public static class AdminAttentionPolicy
{
    /// <summary>Snapshots refresh every 15 minutes; only several missed refreshes make one stale.</summary>
    public static readonly TimeSpan StaleAfter = TimeSpan.FromMinutes(60);

    private static readonly HashSet<string> PendingStatuses = new(StringComparer.OrdinalIgnoreCase)
    {
        "pending", "submitted", "reviewing", "manual_review", "in_review"
    };

    public static AdminAttentionEvaluation? Evaluate(AdminCustomerSnapshot snapshot, DateTimeOffset now)
    {
        if (!string.IsNullOrWhiteSpace(snapshot.LastSyncError))
        {
            if (snapshot.LastSyncError.Contains("not yet connected", StringComparison.OrdinalIgnoreCase))
            {
                return new("Banking connection not completed", "warning", 2, AgeHours(snapshot.OnboardingStartedAt, now));
            }

            return new("Customer data needs a refresh", "danger", 4, AgeHours(snapshot.LastSyncedAt, now));
        }

        if (!snapshot.LastSyncedAt.HasValue || snapshot.LastSyncedAt < now - StaleAfter)
        {
            return new("Customer data is out of date", "warning", 3, AgeHours(snapshot.LastSyncedAt, now));
        }

        if (snapshot.OnboardingStatus is "failed" or "rejected")
        {
            return new("Onboarding needs review", "danger", 4, AgeHours(snapshot.OnboardingUpdatedAt, now));
        }

        if (snapshot.VerificationStatus is "failed" or "rejected")
        {
            return new(
                $"{(snapshot.CustomerType == "business" ? "Business verification" : "Identity verification")} was not approved",
                "danger", 4, AgeHours(snapshot.VerificationReviewedAt ?? snapshot.VerificationSubmittedAt, now));
        }

        var verificationSince = snapshot.VerificationSubmittedAt ?? snapshot.OnboardingStartedAt;
        if (PendingStatuses.Contains(snapshot.VerificationStatus) && verificationSince < now.AddHours(-24))
        {
            return new(
                $"{(snapshot.CustomerType == "business" ? "Business verification" : "Identity verification")} waiting over 24h",
                "warning", 2, AgeHours(verificationSince, now));
        }

        if (!IsComplete(snapshot.OnboardingStatus) &&
            snapshot.OnboardingStatus != "not_started" &&
            snapshot.OnboardingUpdatedAt < now.AddHours(-48))
        {
            return new($"Stopped during {Humanize(snapshot.OnboardingStep)}", "warning", 1,
                AgeHours(snapshot.OnboardingUpdatedAt, now));
        }

        return null;
    }

    private static bool IsComplete(string? status) =>
        status is "completed" or "approved" or "active" or "account_ready";

    private static long AgeHours(DateTimeOffset? since, DateTimeOffset now) =>
        since.HasValue ? Math.Max(0, (long)(now - since.Value).TotalHours) : 0;

    private static string Humanize(string value)
    {
        var text = string.Join(' ', value.Split(['_', '-'], StringSplitOptions.RemoveEmptyEntries));
        return text.Length > 0 ? char.ToUpperInvariant(text[0]) + text[1..] : "onboarding";
    }
}
