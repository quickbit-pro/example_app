using NeoBanking.Api.Admin;
using NeoBanking.Domain.Entities;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AdminStagesAndSettingsTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 25, 12, 0, 0, TimeSpan.Zero);

    [Theory]
    [InlineData("not_started", "not_started", 0, "{}", false, false, 0, AdminCustomerStages.SignedUp)]
    [InlineData("in_progress", "not_started", 0, "{}", false, false, 0, AdminCustomerStages.Onboarding)]
    [InlineData("in_progress", "pending", 0, "{}", false, false, 0, AdminCustomerStages.InReview)]
    [InlineData("in_progress", "rejected", 0, "{}", false, false, 0, AdminCustomerStages.Rejected)]
    [InlineData("completed", "approved", 0, "{}", false, false, 0, AdminCustomerStages.Approved)]
    [InlineData("completed", "approved", 0, "{\"USDT\":5}", false, false, 0, AdminCustomerStages.Funded)]
    [InlineData("completed", "approved", 0, "{}", true, false, 0, AdminCustomerStages.Funded)]
    [InlineData("completed", "approved", 1, "{}", true, false, 0, AdminCustomerStages.Carded)]
    [InlineData("completed", "approved", 1, "{}", true, true, 3, AdminCustomerStages.Active)]
    [InlineData("completed", "approved", 1, "{}", true, true, 45, AdminCustomerStages.Dormant)]
    public void EveryCustomerHasExactlyOneStage(string onboarding, string verification, int cards, string balances,
        bool receivedMoney, bool purchased, int daysSinceActivity, string expected)
    {
        var snapshot = new AdminCustomerSnapshot
        {
            OnboardingStatus = onboarding, VerificationStatus = verification, TotalCardCount = cards, BalanceSummaryJson = balances
        };
        var facts = receivedMoney || purchased
            ? new AdminCustomerStages.Facts(receivedMoney, purchased, Now.AddDays(-daysSinceActivity))
            : null;

        Assert.Equal(expected, AdminCustomerStages.Of(snapshot, facts, Now));
    }

    [Fact]
    public void ReportingTimeZoneRoundTripsAndRejectsUnknownZones()
    {
        var json = AdminReportingSettings.WriteTimeZone("{\"mobileDesign\":{\"appName\":\"Example\"}}", "Europe/Istanbul");
        Assert.Equal("Europe/Istanbul", AdminReportingSettings.ReadTimeZone(json));
        Assert.Contains("mobileDesign", json);
        Assert.Equal("UTC", AdminReportingSettings.ReadTimeZone("{\"reporting\":{\"timeZone\":\"Mars/Olympus\"}}"));
        Assert.Equal("UTC", AdminReportingSettings.ReadTimeZone("not json"));
        Assert.False(AdminReportingSettings.TryResolve("Mars/Olympus", out _));
        Assert.True(AdminReportingSettings.TryResolve("Europe/Berlin", out var berlin));
        Assert.Equal(TimeSpan.FromHours(2), berlin.GetUtcOffset(new DateTime(2026, 9, 25)));
    }

    [Fact]
    public void WeeksStartOnMonday()
    {
        Assert.Equal(new DateOnly(2026, 9, 21), AdminKpiService.WeekStart(new DateOnly(2026, 9, 25)));
        Assert.Equal(new DateOnly(2026, 9, 21), AdminKpiService.WeekStart(new DateOnly(2026, 9, 21)));
        Assert.Equal(new DateOnly(2026, 9, 21), AdminKpiService.WeekStart(new DateOnly(2026, 9, 27)));
    }
}
