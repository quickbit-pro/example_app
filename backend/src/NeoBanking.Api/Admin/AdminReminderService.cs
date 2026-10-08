using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Application.Email;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Email;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Admin;

public sealed class AdminRemindersOptions
{
    public const string SectionName = "AdminReminders";

    /// <summary>HTTPS customer app URL used in reminder buttons.</summary>
    public string AppUrl { get; set; } = string.Empty;

    /// <summary>A customer gets the same reminder at most once in this many days.</summary>
    public int CooldownDays { get; set; } = 7;

    public int MaxRecipients { get; set; } = 500;
}

public sealed record AdminReminderSkips(int RecentlyReminded, int TestAccounts, int EmailNotConfirmed, int Locked, int OverLimit);

public sealed record AdminReminderPlan(
    string Stage,
    string TemplateKey,
    string TemplateName,
    bool TemplateEnabled,
    string Subject,
    IReadOnlyList<Guid> Recipients,
    IReadOnlyList<string> SampleNames,
    AdminReminderSkips Skipped,
    int CooldownDays);

/// <summary>
/// Lifecycle reminders an operator sends from the Customers page. Only verified,
/// unlocked, non-test customers in the chosen stage are eligible, and each gets the
/// same reminder at most once per cooldown. Every send is audited.
/// </summary>
public sealed class AdminReminderService(
    NeoBankingDbContext dbContext,
    EmailTemplateStore templateStore,
    EmailOutbox outbox,
    IOptions<AdminRemindersOptions> options,
    TimeProvider clock)
{
    public static readonly IReadOnlyDictionary<string, string> TemplateByStage = new Dictionary<string, string>
    {
        [AdminCustomerStages.SignedUp] = EmailTemplateCatalog.ReminderFinishSignup,
        [AdminCustomerStages.Onboarding] = EmailTemplateCatalog.ReminderFinishSignup,
        [AdminCustomerStages.Approved] = EmailTemplateCatalog.ReminderAddMoney,
        [AdminCustomerStages.Funded] = EmailTemplateCatalog.ReminderGetCard,
        [AdminCustomerStages.Carded] = EmailTemplateCatalog.ReminderUseCard,
        [AdminCustomerStages.Dormant] = EmailTemplateCatalog.ReminderComeBack
    };

    public string AppUrl
    {
        get
        {
            var configured = options.Value.AppUrl;
            return Uri.TryCreate(configured, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps ? uri.ToString() : string.Empty;
        }
    }

    public async Task<AdminReminderPlan?> PlanAsync(
        Guid companyId, string stage, IReadOnlyCollection<Guid>? customerIds, CancellationToken cancellationToken)
    {
        if (!TemplateByStage.TryGetValue(stage, out var templateKey))
        {
            return null;
        }

        var now = clock.GetUtcNow();
        var snapshots = await dbContext.AdminCustomerSnapshots
            .AsNoTracking()
            .Include(snapshot => snapshot.User)
            .Where(snapshot =>
                snapshot.CompanyInstallationId == companyId &&
                snapshot.User != null &&
                snapshot.User.AdminProfile == null)
            .ToListAsync(cancellationToken);
        var facts = await AdminCustomerStages.LoadFactsAsync(dbContext, companyId, cancellationToken);
        var chosen = customerIds is { Count: > 0 } ? customerIds.ToHashSet() : null;
        var inStage = snapshots
            .Where(snapshot => chosen is null || chosen.Contains(snapshot.UserId))
            .Where(snapshot => AdminCustomerStages.Of(snapshot, facts.GetValueOrDefault(snapshot.UserId), now) == stage)
            .OrderBy(snapshot => snapshot.User!.CreatedAt)
            .ToList();

        var testUsers = (await dbContext.AdminCustomerFlags
                .AsNoTracking()
                .Where(flag => flag.CompanyInstallationId == companyId && flag.IsTestAccount)
                .Select(flag => flag.UserId)
                .ToListAsync(cancellationToken))
            .ToHashSet();
        var candidates = inStage.Where(snapshot => !testUsers.Contains(snapshot.UserId)).ToList();
        var skippedTest = inStage.Count - candidates.Count;
        var locked = candidates.Count(snapshot => snapshot.User!.LockedAt != null);
        candidates = candidates.Where(snapshot => snapshot.User!.LockedAt == null).ToList();
        // An unconfirmed address may belong to someone else; never write to it.
        var unconfirmed = candidates.Count(snapshot => snapshot.User!.EmailVerifiedAt == null || string.IsNullOrWhiteSpace(snapshot.User.Email));
        candidates = candidates.Where(snapshot => snapshot.User!.EmailVerifiedAt != null && !string.IsNullOrWhiteSpace(snapshot.User.Email)).ToList();

        var cooldownDays = Math.Clamp(options.Value.CooldownDays, 1, 90);
        var since = now.AddDays(-cooldownDays);
        var candidateIds = candidates.Select(snapshot => snapshot.UserId).ToList();
        var reminded = (await dbContext.EmailMessages
                .AsNoTracking()
                .Where(message =>
                    message.CompanyInstallationId == companyId &&
                    message.TemplateKey == templateKey &&
                    message.UserId != null &&
                    candidateIds.Contains(message.UserId.Value) &&
                    message.CreatedAt >= since)
                .Select(message => message.UserId!.Value)
                .ToListAsync(cancellationToken))
            .ToHashSet();
        var recent = candidates.Count(snapshot => reminded.Contains(snapshot.UserId));
        candidates = candidates.Where(snapshot => !reminded.Contains(snapshot.UserId)).ToList();

        var limit = Math.Clamp(options.Value.MaxRecipients, 1, 5000);
        var overLimit = Math.Max(0, candidates.Count - limit);
        candidates = candidates.Take(limit).ToList();

        var template = await templateStore.ResolveAsync(companyId, templateKey, cancellationToken);
        var subject = template is null
            ? templateKey
            : EmailTemplateRenderer.Render(template.Subject, template.HtmlBody, template.TextBody,
                outbox.BuildValues(new EmailRequest(companyId, null, "customer@example.com", "Customer", templateKey,
                    new Dictionary<string, string> { ["appUrl"] = AppUrl }))).Subject;

        return new AdminReminderPlan(
            stage,
            templateKey,
            template?.Definition.Name ?? templateKey,
            template?.IsEnabled == true,
            subject,
            candidates.Select(snapshot => snapshot.UserId).ToList(),
            candidates.Take(5).Select(snapshot => snapshot.User!.DisplayName ?? snapshot.User.Email).ToList(),
            new AdminReminderSkips(recent, skippedTest, unconfirmed, locked, overLimit),
            cooldownDays);
    }

    /// <summary>Queues the plan's emails and the audit entry; the caller saves.</summary>
    public async Task<int> QueueAsync(Guid companyId, Guid? actorId, AdminReminderPlan plan, AuditLogEntry audit, CancellationToken cancellationToken)
    {
        var users = await dbContext.Users
            .AsNoTracking()
            .Where(user => user.CompanyInstallationId == companyId && plan.Recipients.Contains(user.Id))
            .Select(user => new { user.Id, user.Email, user.DisplayName })
            .ToListAsync(cancellationToken);
        var queued = 0;
        foreach (var user in users)
        {
            var message = await outbox.EnqueueAsync(
                new EmailRequest(
                    companyId,
                    user.Id,
                    user.Email,
                    user.DisplayName,
                    plan.TemplateKey,
                    new Dictionary<string, string> { ["appUrl"] = AppUrl },
                    EmailOutbox.SerializeMetadata(new { purpose = "lifecycle_reminder", plan.Stage, sentBy = actorId })),
                cancellationToken);
            if (message is not null)
            {
                queued++;
            }
        }

        dbContext.AuditLogEntries.Add(audit);
        return queued;
    }
}
