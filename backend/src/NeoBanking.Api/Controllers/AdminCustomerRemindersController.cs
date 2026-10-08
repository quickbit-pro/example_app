using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Admin;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

/// <summary>Preview and send lifecycle reminder emails to the customers in one stage.</summary>
[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/customer-reminders")]
public sealed class AdminCustomerRemindersController(NeoBankingDbContext dbContext, AdminReminderService reminders) : ApiControllerBase
{
    [HttpPost("preview")]
    public async Task<IActionResult> Preview([FromBody] ReminderRequest request, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var plan = await reminders.PlanAsync(companyId, request.Stage ?? string.Empty, request.CustomerIds, cancellationToken);
        return plan is null ? UnsupportedStage() : Ok(ToResponse(plan, reminders.AppUrl));
    }

    [HttpPost("send")]
    public async Task<IActionResult> Send([FromBody] ReminderRequest request, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var plan = await reminders.PlanAsync(companyId, request.Stage ?? string.Empty, request.CustomerIds, cancellationToken);
        if (plan is null)
        {
            return UnsupportedStage();
        }

        if (string.IsNullOrEmpty(reminders.AppUrl))
        {
            return Conflict(new { code = "admin.reminders.app_url_missing", message = "Set AdminReminders:AppUrl (an https link to the app) before sending reminders." });
        }

        if (!plan.TemplateEnabled)
        {
            return Conflict(new { code = "admin.reminders.template_disabled", message = $"The “{plan.TemplateName}” email template is turned off. Turn it on under Email templates first." });
        }

        // The operator confirmed a number; if customers moved stage since the preview, ask again.
        if (request.ExpectedRecipients != plan.Recipients.Count)
        {
            return Conflict(new { code = "admin.reminders.recipients_changed", message = "The recipients changed since the preview. Review the reminder again.", preview = ToResponse(plan, reminders.AppUrl) });
        }

        if (plan.Recipients.Count == 0)
        {
            return Ok(new { queued = 0, stage = plan.Stage, templateKey = plan.TemplateKey });
        }

        Guid? actorId = TryGetLocalUserId(out var actor) && Guid.TryParse(actor, out var parsedActor) ? parsedActor : null;
        var audit = new AuditLogEntry
        {
            CompanyInstallationId = companyId,
            ActorUserId = actorId,
            Action = "customers.reminder_sent",
            EntityType = "email_template",
            TraceId = HttpContext.TraceIdentifier,
            IpAddress = GetClientIpAddress(),
            UserAgent = Request.Headers.UserAgent.ToString(),
            AfterJson = JsonSerializer.Serialize(new { plan.Stage, plan.TemplateKey, recipients = plan.Recipients.Count, skipped = plan.Skipped }),
            MetadataJson = "{\"source\":\"wl_admin\"}"
        };
        var queued = await reminders.QueueAsync(companyId, actorId, plan, audit, cancellationToken);
        await dbContext.SaveChangesAsync(cancellationToken);
        return Ok(new { queued, stage = plan.Stage, templateKey = plan.TemplateKey });
    }

    private static object ToResponse(AdminReminderPlan plan, string appUrl) => new
    {
        plan.Stage,
        plan.TemplateKey,
        plan.TemplateName,
        plan.TemplateEnabled,
        plan.Subject,
        recipients = plan.Recipients.Count,
        plan.SampleNames,
        plan.Skipped,
        plan.CooldownDays,
        appUrlConfigured = !string.IsNullOrEmpty(appUrl)
    };

    private BadRequestObjectResult UnsupportedStage() => BadRequest(new
    {
        code = "admin.reminders.stage_not_supported",
        message = "Reminders exist for customers who have not finished signing up, approved customers without money, customers without a card, unused cards and dormant customers."
    });

    public sealed record ReminderRequest(string? Stage, IReadOnlyCollection<Guid>? CustomerIds, int ExpectedRecipients);
}
