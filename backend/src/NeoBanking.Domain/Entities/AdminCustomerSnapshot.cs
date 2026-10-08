#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class AdminCustomerSnapshot : CompanyScopedEntity
{
    public Guid UserId { get; set; }

    public ApplicationUser? User { get; set; }

    public string? ProviderUserId { get; set; }

    public string CustomerType { get; set; } = "individual";

    public string OnboardingStatus { get; set; } = "not_started";

    public string OnboardingStep { get; set; } = "start";

    public DateTimeOffset? OnboardingStartedAt { get; set; }

    public DateTimeOffset? OnboardingCompletedAt { get; set; }

    public DateTimeOffset? OnboardingUpdatedAt { get; set; }

    public string VerificationStatus { get; set; } = "not_started";

    public string? VerificationLevel { get; set; }

    public DateTimeOffset? VerificationSubmittedAt { get; set; }

    public DateTimeOffset? VerificationReviewedAt { get; set; }

    public string BalanceSummaryJson { get; set; } = "{}";

    public string AccountSummaryJson { get; set; } = "[]";

    public string CardSummaryJson { get; set; } = "[]";

    public string RecentTransactionsJson { get; set; } = "[]";

    public string VerificationDetailsJson { get; set; } = "{}";

    public int AccountCount { get; set; }

    public int ActiveCardCount { get; set; }

    public int TotalCardCount { get; set; }

    public int CompletedTransactionCount30d { get; set; }

    public string TransactionInflow30dJson { get; set; } = "{}";

    public string TransactionOutflow30dJson { get; set; } = "{}";

    public DateTimeOffset? LastTransactionAt { get; set; }

    public DateTimeOffset? LastActivityAt { get; set; }

    public DateTimeOffset? LastSyncedAt { get; set; }

    public string? LastSyncError { get; set; }

    public DateTimeOffset? LastSyncAttemptAt { get; set; }

    public DateTimeOffset? NextSyncAt { get; set; }

    public DateTimeOffset? SyncRequestedAt { get; set; }

    public int ConsecutiveSyncFailures { get; set; }
}
