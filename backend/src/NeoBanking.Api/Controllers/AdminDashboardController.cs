using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.Security;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/dashboard")]
public sealed class AdminDashboardController : ApiControllerBase
{
    private readonly NeoBankingDbContext _dbContext;

    public AdminDashboardController(NeoBankingDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    [HttpGet("overview")]
    public async Task<IActionResult> GetOverview(
        [FromQuery] int? days,
        CancellationToken cancellationToken)
    {
        var window = Math.Clamp(days ?? 30, 1, 180);
        var now = DateTimeOffset.UtcNow;
        var since = now.AddDays(-window).Date;
        var sinceUtc = new DateTimeOffset(since, TimeSpan.Zero);

        // ---------- KPI counts (totals + recent-window deltas) ----------
        var users = await _dbContext.Users.CountAsync(cancellationToken);
        var usersInWindow = await _dbContext.Users
            .Where(u => u.CreatedAt >= sinceUtc)
            .CountAsync(cancellationToken);

        var kycCases = await _dbContext.KycVerifications.CountAsync(cancellationToken);
        var kycPending = await _dbContext.KycVerifications
            .Where(k => k.Status == "pending" || k.Status == "submitted" || k.Status == "manual_review")
            .CountAsync(cancellationToken);
        var kycApprovedInWindow = await _dbContext.KycVerifications
            .Where(k => k.Status == "approved" && k.ReviewedAt != null && k.ReviewedAt >= sinceUtc)
            .CountAsync(cancellationToken);
        var kycRejectedInWindow = await _dbContext.KycVerifications
            .Where(k => k.Status == "rejected" && k.ReviewedAt != null && k.ReviewedAt >= sinceUtc)
            .CountAsync(cancellationToken);

        var kybCases = await _dbContext.KybVerifications.CountAsync(cancellationToken);
        var cards = await _dbContext.Cards.CountAsync(cancellationToken);
        var cardsActive = await _dbContext.Cards
            .Where(c => c.Status == "active")
            .CountAsync(cancellationToken);
        var cardsInWindow = await _dbContext.Cards
            .Where(c => c.IssuedAt != null && c.IssuedAt >= sinceUtc)
            .CountAsync(cancellationToken);

        var webhookTotal = await _dbContext.WebhookDeliveries.CountAsync(cancellationToken);
        var webhookFailed = await _dbContext.WebhookDeliveries
            .Where(w => w.Status == "failed")
            .CountAsync(cancellationToken);

        // ---------- Onboarding cohort and operator-facing health ----------
        // The selected window defines the signup cohort. Progress is read from each
        // user's latest application so admins can answer "what happened to users who
        // joined in this period?" instead of seeing unrelated technical totals.
        var cohortUsers = await _dbContext.Users
            .AsNoTracking()
            .Where(user => user.CreatedAt >= sinceUtc)
            .Select(user => new
            {
                user.Id,
                user.DisplayName,
                user.Email,
                user.CreatedAt,
            })
            .ToListAsync(cancellationToken);
        var cohortApplications = await _dbContext.OnboardingApplications
            .AsNoTracking()
            .Where(application => application.ApplicantUser != null &&
                                  application.ApplicantUser.CreatedAt >= sinceUtc)
            .Select(application => new
            {
                application.Id,
                application.ApplicantUserId,
                application.Kind,
                application.Status,
                application.CurrentStep,
                application.SubmittedAt,
                application.CompletedAt,
                application.CreatedAt,
                application.UpdatedAt,
            })
            .ToListAsync(cancellationToken);

        var latestApplications = cohortApplications
            .GroupBy(application => application.ApplicantUserId!.Value)
            .ToDictionary(
                group => group.Key,
                group => group.OrderByDescending(application => application.CreatedAt).First());

        var cohortKycRows = await _dbContext.KycVerifications
            .AsNoTracking()
            .Where(verification => verification.User != null &&
                                   verification.User.CreatedAt >= sinceUtc)
            .Select(verification => new
            {
                verification.UserId,
                verification.Status,
                verification.StartedAt,
            })
            .ToListAsync(cancellationToken);
        var latestKycByUser = cohortKycRows
            .GroupBy(verification => verification.UserId)
            .ToDictionary(
                group => group.Key,
                group => group.OrderByDescending(verification => verification.StartedAt).First().Status);

        var onboardingStarted = latestApplications.Count;
        var onboardingSubmitted = latestApplications.Count(pair =>
            IsSubmittedOnboarding(pair.Value.Status, pair.Value.SubmittedAt) ||
            latestKycByUser.ContainsKey(pair.Key));
        var onboardingVerified = latestApplications.Count(pair =>
            IsCompletedOnboarding(pair.Value.Status) ||
            (latestKycByUser.TryGetValue(pair.Key, out var status) && IsApproved(status)));
        var onboardingCompleted = latestApplications.Count(pair => IsCompletedOnboarding(pair.Value.Status));
        var onboardingAttention = latestApplications.Count(pair =>
            NeedsOnboardingAttention(pair.Value.Status, pair.Value.UpdatedAt, now)) +
            cohortUsers.Count(user => !latestApplications.ContainsKey(user.Id) &&
                                      now - user.CreatedAt >= TimeSpan.FromHours(48));
        var onboardingInProgress = latestApplications.Count - onboardingCompleted -
            latestApplications.Count(pair => IsFailedOnboarding(pair.Value.Status));

        var completedDurationsHours = latestApplications.Values
            .Where(application => application.CompletedAt != null)
            .Select(application => (application.CompletedAt!.Value - application.CreatedAt).TotalHours)
            .Where(hours => hours >= 0)
            .OrderBy(hours => hours)
            .ToArray();
        var medianCompletionHours = Median(completedDurationsHours);
        var completionRate = cohortUsers.Count == 0
            ? 0m
            : Math.Round(onboardingCompleted * 100m / cohortUsers.Count, 1);

        var onboardingFunnel = new object[]
        {
            FunnelStage("registered", "Registered", cohortUsers.Count, cohortUsers.Count),
            FunnelStage("started", "Started onboarding", onboardingStarted, cohortUsers.Count),
            FunnelStage("submitted", "Submitted details", onboardingSubmitted, cohortUsers.Count),
            FunnelStage("verified", "Identity verified", onboardingVerified, cohortUsers.Count),
            FunnelStage("completed", "Onboarding complete", onboardingCompleted, cohortUsers.Count),
        };

        var onboardingStatusBreakdown = latestApplications.Values
            .GroupBy(application => NormalizeLabel(application.Status, "unknown"))
            .Select(group => new { status = group.Key, count = group.Count() })
            .OrderByDescending(item => item.count)
            .ToArray();

        var onboardingStepBreakdown = latestApplications.Values
            .Where(application => !IsCompletedOnboarding(application.Status))
            .GroupBy(application => NormalizeLabel(application.CurrentStep, "not_started"))
            .Select(group => new { step = group.Key, count = group.Count() })
            .OrderByDescending(item => item.count)
            .Take(8)
            .ToArray();

        var onboardingApplicants = cohortUsers
            .Select(user =>
            {
                latestApplications.TryGetValue(user.Id, out var application);
                latestKycByUser.TryGetValue(user.Id, out var kycStatus);
                var status = application?.Status ?? "not_started";
                var lastActivityAt = application?.UpdatedAt ?? user.CreatedAt;
                var needsAttention = application == null
                    ? now - user.CreatedAt >= TimeSpan.FromHours(48)
                    : NeedsOnboardingAttention(status, application.UpdatedAt, now);

                return new
                {
                    id = application?.Id,
                    userId = user.Id,
                    name = string.IsNullOrWhiteSpace(user.DisplayName) ? user.Email : user.DisplayName,
                    user.Email,
                    kind = application?.Kind ?? "unknown",
                    status,
                    currentStep = application?.CurrentStep ?? "not_started",
                    kycStatus = kycStatus ?? "not_started",
                    registeredAt = user.CreatedAt,
                    lastActivityAt,
                    ageHours = Math.Max(0, Math.Round((now - lastActivityAt).TotalHours, 0)),
                    needsAttention,
                    attentionReason = OnboardingAttentionReason(application?.Status, lastActivityAt, now),
                };
            })
            .OrderByDescending(applicant => applicant.needsAttention)
            .ThenBy(applicant => applicant.lastActivityAt)
            .Take(20)
            .ToArray();

        // ---------- Time-series: signups per day ----------
        var signupRaw = await _dbContext.Users
            .Where(u => u.CreatedAt >= sinceUtc)
            .Select(u => new { u.CreatedAt })
            .ToListAsync(cancellationToken);
        var signupByDay = signupRaw
            .GroupBy(u => u.CreatedAt.UtcDateTime.Date)
            .ToDictionary(g => g.Key, g => (long)g.Count());
        var signupSeries = ToDailySeries(signupByDay, since, window);

        // ---------- Time-series: KYC reviews per day, split by outcome ----------
        var kycReviewRaw = await _dbContext.KycVerifications
            .Where(k => k.ReviewedAt != null && k.ReviewedAt >= sinceUtc)
            .Select(k => new { k.ReviewedAt, k.Status })
            .ToListAsync(cancellationToken);
        var kycApprovedByDay = kycReviewRaw
            .Where(x => x.Status == "approved")
            .GroupBy(x => x.ReviewedAt!.Value.UtcDateTime.Date)
            .ToDictionary(g => g.Key, g => (long)g.Count());
        var kycRejectedByDay = kycReviewRaw
            .Where(x => x.Status == "rejected")
            .GroupBy(x => x.ReviewedAt!.Value.UtcDateTime.Date)
            .ToDictionary(g => g.Key, g => (long)g.Count());
        var kycManualByDay = kycReviewRaw
            .Where(x => x.Status == "manual_review")
            .GroupBy(x => x.ReviewedAt!.Value.UtcDateTime.Date)
            .ToDictionary(g => g.Key, g => (long)g.Count());

        // ---------- Time-series: cards issued per day ----------
        var cardsRaw = await _dbContext.Cards
            .Where(c => c.IssuedAt != null && c.IssuedAt >= sinceUtc)
            .Select(c => new { c.IssuedAt })
            .ToListAsync(cancellationToken);
        var cardsByDay = cardsRaw
            .GroupBy(c => c.IssuedAt!.Value.UtcDateTime.Date)
            .ToDictionary(g => g.Key, g => (long)g.Count());
        var cardsSeries = ToDailySeries(cardsByDay, since, window);

        // ---------- Time-series: webhook deliveries per day, split by status ----------
        var webhookRaw = await _dbContext.WebhookDeliveries
            .Where(w => w.ReceivedAt >= sinceUtc)
            .Select(w => new { w.ReceivedAt, w.Status })
            .ToListAsync(cancellationToken);
        var webhookSucceededByDay = webhookRaw
            .Where(w => w.Status == "processed" || w.Status == "succeeded" || w.Status == "received")
            .GroupBy(w => w.ReceivedAt.UtcDateTime.Date)
            .ToDictionary(g => g.Key, g => (long)g.Count());
        var webhookFailedByDay = webhookRaw
            .Where(w => w.Status == "failed")
            .GroupBy(w => w.ReceivedAt.UtcDateTime.Date)
            .ToDictionary(g => g.Key, g => (long)g.Count());

        // Webhook event-type breakdown over window — proxy for transaction flow
        var webhookByType = await _dbContext.WebhookDeliveries
            .Where(w => w.ReceivedAt >= sinceUtc)
            .GroupBy(w => w.EventType)
            .Select(g => new { eventType = g.Key, count = g.Count() })
            .OrderByDescending(x => x.count)
            .Take(8)
            .ToListAsync(cancellationToken);

        // ---------- KYC status distribution (current snapshot) ----------
        var kycStatusBreakdown = await _dbContext.KycVerifications
            .GroupBy(k => k.Status)
            .Select(g => new { status = g.Key, count = g.Count() })
            .ToListAsync(cancellationToken);

        // ---------- Card status distribution ----------
        var cardStatusBreakdown = await _dbContext.Cards
            .GroupBy(c => c.Status)
            .Select(g => new { status = g.Key, count = g.Count() })
            .ToListAsync(cancellationToken);

        // ---------- Recent admin activity (audit) ----------
        var recentAuditRows = await _dbContext.AuditLogEntries
            .OrderByDescending(a => a.OccurredAt)
            .Take(20)
            .Select(a => new
            {
                id = a.Id,
                time = a.OccurredAt,
                actor = a.ActorUserId,
                action = a.Action,
                target = a.EntityType,
                metadata = a.MetadataJson,
            })
            .ToListAsync(cancellationToken);

        var recentAudit = recentAuditRows
            .Select(a =>
            {
                var failed = MetadataIndicatesFailure(a.metadata);
                return new
                {
                    a.id,
                    a.time,
                    a.actor,
                    a.action,
                    a.target,
                    priority = failed ? "high" : "low",
                    status = failed ? "failed" : "success",
                };
            })
            .ToList();

        // ---------- Risk signals (KYC pending oldest + webhook failures spike) ----------
        var stalePending = await _dbContext.KycVerifications
            .Where(k => k.Status == "pending" || k.Status == "submitted" || k.Status == "manual_review")
            .OrderBy(k => k.StartedAt)
            .Take(5)
            .Select(k => new
            {
                id = k.Id,
                subject = "KYC pending: " + (k.User != null ? k.User.DisplayName ?? k.User.Email : k.Id.ToString()),
                category = "compliance",
                severity = "medium",
                priority = "medium",
                owner = "Compliance",
                status = k.Status,
                time = k.StartedAt,
            })
            .ToListAsync(cancellationToken);

        var failingWebhooks = await _dbContext.WebhookDeliveries
            .Where(w => w.Status == "failed" && w.ReceivedAt >= sinceUtc)
            .OrderByDescending(w => w.ReceivedAt)
            .Take(5)
            .Select(w => new
            {
                id = w.Id,
                subject = "Webhook failure: " + w.EventType,
                category = "operations",
                severity = "high",
                priority = "high",
                owner = "Platform",
                status = "failed",
                time = w.ReceivedAt,
            })
            .ToListAsync(cancellationToken);

        return Ok(new
        {
            metrics = new object[]
            {
                new
                {
                    label = "Local users",
                    tone = usersInWindow > 0 ? "success" : "neutral",
                    trend = $"+{usersInWindow} in last {window}d",
                    value = users.ToString(),
                },
                new
                {
                    label = "KYC pending review",
                    tone = kycPending > 0 ? "warning" : "success",
                    trend = $"{kycApprovedInWindow} approved / {kycRejectedInWindow} rejected ({window}d)",
                    value = kycPending.ToString(),
                },
                new
                {
                    label = "Cards (active / total)",
                    tone = "neutral",
                    trend = $"+{cardsInWindow} issued in last {window}d",
                    value = $"{cardsActive} / {cards}",
                },
                new
                {
                    label = "Webhook failures",
                    tone = webhookFailed > 0 ? "danger" : "success",
                    trend = $"of {webhookTotal} total",
                    value = webhookFailed.ToString(),
                },
            },
            charts = new
            {
                windowDays = window,
                signups = signupSeries,
                kycReviews = new
                {
                    labels = signupSeries.labels,
                    approved = signupSeries.labels.Select(l => kycApprovedByDay.GetValueOrDefault(DateTime.Parse(l), 0)).ToArray(),
                    rejected = signupSeries.labels.Select(l => kycRejectedByDay.GetValueOrDefault(DateTime.Parse(l), 0)).ToArray(),
                    manualReview = signupSeries.labels.Select(l => kycManualByDay.GetValueOrDefault(DateTime.Parse(l), 0)).ToArray(),
                },
                cardsIssued = cardsSeries,
                webhooks = new
                {
                    labels = signupSeries.labels,
                    succeeded = signupSeries.labels.Select(l => webhookSucceededByDay.GetValueOrDefault(DateTime.Parse(l), 0)).ToArray(),
                    failed = signupSeries.labels.Select(l => webhookFailedByDay.GetValueOrDefault(DateTime.Parse(l), 0)).ToArray(),
                },
                webhookEventTypes = webhookByType,
                kycStatusBreakdown,
                cardStatusBreakdown,
            },
            onboarding = new
            {
                cohortLabel = $"Users registered in the last {window} days",
                registered = cohortUsers.Count,
                started = onboardingStarted,
                inProgress = Math.Max(0, onboardingInProgress),
                completed = onboardingCompleted,
                needsAttention = onboardingAttention,
                completionRate,
                medianCompletionHours,
                funnel = onboardingFunnel,
                statusBreakdown = onboardingStatusBreakdown,
                stepBreakdown = onboardingStepBreakdown,
                applicants = onboardingApplicants,
            },
            queues = stalePending,
            riskSignals = failingWebhooks,
            activity = recentAudit,
        });
    }

    private static DailySeries ToDailySeries(
        IDictionary<DateTime, long> byDay,
        DateTime since,
        int window)
    {
        var labels = new string[window];
        var values = new long[window];
        for (var i = 0; i < window; i++)
        {
            var day = since.AddDays(i);
            labels[i] = day.ToString("yyyy-MM-dd");
            values[i] = byDay.TryGetValue(day, out var v) ? v : 0L;
        }
        return new DailySeries(labels, values);
    }

    private static bool MetadataIndicatesFailure(string? metadataJson)
    {
        return !string.IsNullOrWhiteSpace(metadataJson) &&
            metadataJson.Contains("failed", StringComparison.OrdinalIgnoreCase);
    }

    private static object FunnelStage(string key, string label, int count, int cohortSize)
    {
        var percent = cohortSize == 0 ? 0m : Math.Round(count * 100m / cohortSize, 1);
        return new { key, label, count, percent };
    }

    private static bool IsSubmittedOnboarding(string? status, DateTimeOffset? submittedAt)
    {
        if (submittedAt != null)
        {
            return true;
        }

        return NormalizeLabel(status, string.Empty) is
            "submitted" or "pending" or "review" or "in_review" or "manual_review" or
            "approved" or "verified" or "completed";
    }

    private static bool IsCompletedOnboarding(string? status)
    {
        return NormalizeLabel(status, string.Empty) is "completed" or "approved" or "active";
    }

    private static bool IsApproved(string? status)
    {
        return NormalizeLabel(status, string.Empty) is "approved" or "verified" or "completed" or "active";
    }

    private static bool IsFailedOnboarding(string? status)
    {
        return NormalizeLabel(status, string.Empty) is
            "rejected" or "failed" or "declined" or "cancelled" or "expired";
    }

    private static bool NeedsOnboardingAttention(
        string? status,
        DateTimeOffset lastActivityAt,
        DateTimeOffset now)
    {
        return IsFailedOnboarding(status) ||
               (!IsCompletedOnboarding(status) && now - lastActivityAt >= TimeSpan.FromHours(48));
    }

    private static string OnboardingAttentionReason(
        string? status,
        DateTimeOffset lastActivityAt,
        DateTimeOffset now)
    {
        if (IsFailedOnboarding(status))
        {
            return "Application requires review";
        }

        if (!IsCompletedOnboarding(status) && now - lastActivityAt >= TimeSpan.FromHours(48))
        {
            return "No progress for 48+ hours";
        }

        return string.Empty;
    }

    private static string NormalizeLabel(string? value, string fallback)
    {
        return string.IsNullOrWhiteSpace(value)
            ? fallback
            : value.Trim().ToLowerInvariant().Replace('-', '_').Replace(' ', '_');
    }

    private static decimal? Median(double[] values)
    {
        if (values.Length == 0)
        {
            return null;
        }

        var middle = values.Length / 2;
        var median = values.Length % 2 == 0
            ? (values[middle - 1] + values[middle]) / 2d
            : values[middle];
        return Math.Round((decimal)median, 1);
    }

    private sealed record DailySeries(string[] labels, long[] values);
}
