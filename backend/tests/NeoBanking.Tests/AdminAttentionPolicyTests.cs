using NeoBanking.Api.Admin;
using NeoBanking.Domain.Entities;
using Xunit;

namespace NeoBanking.Tests;

public sealed class AdminAttentionPolicyTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 27, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void PendingVerificationAfter24HoursNeedsAttention()
    {
        var snapshot = WithState(HealthySnapshot(),
            verificationStatus: "pending",
            verificationSubmittedAt: Now.AddHours(-25));

        var result = AdminAttentionPolicy.Evaluate(snapshot, Now);

        Assert.NotNull(result);
        Assert.Equal("Identity verification waiting over 24h", result.Reason);
        Assert.Equal("warning", result.Tone);
    }

    [Fact]
    public void PendingVerificationBefore24HoursIsHealthy()
    {
        var snapshot = WithState(HealthySnapshot(),
            verificationStatus: "pending",
            verificationSubmittedAt: Now.AddHours(-23));

        Assert.Null(AdminAttentionPolicy.Evaluate(snapshot, Now));
    }

    [Fact]
    public void InactiveOnboardingAfter48HoursNeedsFollowUp()
    {
        var snapshot = WithState(HealthySnapshot(),
            onboardingStatus: "in_progress",
            onboardingStep: "identity_check",
            onboardingUpdatedAt: Now.AddHours(-49));

        var result = AdminAttentionPolicy.Evaluate(snapshot, Now);

        Assert.NotNull(result);
        Assert.Equal("Stopped during Identity check", result.Reason);
    }

    [Fact]
    public void StaleSynchronizationTakesPriority()
    {
        var snapshot = HealthySnapshot();
        snapshot.LastSyncedAt = Now.AddMinutes(-61);
        snapshot.VerificationStatus = "rejected";

        var result = AdminAttentionPolicy.Evaluate(snapshot, Now);

        Assert.NotNull(result);
        Assert.Equal("Customer data is out of date", result.Reason);
        Assert.Equal(3, result.Priority);
    }

    private static AdminCustomerSnapshot HealthySnapshot() => new()
    {
        CustomerType = "individual",
        LastSyncedAt = Now.AddMinutes(-2),
        OnboardingStatus = "completed",
        OnboardingStep = "account_ready",
        OnboardingUpdatedAt = Now.AddMinutes(-5),
        VerificationStatus = "approved"
    };

    private static AdminCustomerSnapshot WithState(
        AdminCustomerSnapshot snapshot,
        string? verificationStatus = null,
        DateTimeOffset? verificationSubmittedAt = null,
        string? onboardingStatus = null,
        string? onboardingStep = null,
        DateTimeOffset? onboardingUpdatedAt = null)
    {
        snapshot.VerificationStatus = verificationStatus ?? snapshot.VerificationStatus;
        snapshot.VerificationSubmittedAt = verificationSubmittedAt ?? snapshot.VerificationSubmittedAt;
        snapshot.OnboardingStatus = onboardingStatus ?? snapshot.OnboardingStatus;
        snapshot.OnboardingStep = onboardingStep ?? snapshot.OnboardingStep;
        snapshot.OnboardingUpdatedAt = onboardingUpdatedAt ?? snapshot.OnboardingUpdatedAt;
        return snapshot;
    }
}
