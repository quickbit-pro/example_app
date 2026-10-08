using System.Net.Mail;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Application.DTOs.Email;
using NeoBanking.Application.Email;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Email;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/email-templates")]
public sealed class AdminEmailTemplatesController(
    NeoBankingDbContext dbContext,
    EmailTemplateStore templateStore,
    EmailOutbox outbox,
    IEmailSender emailSender,
    IOptions<EmailOptions> emailOptions) : ApiControllerBase
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [HttpGet]
    public async Task<ActionResult<EmailTemplateListResponseDto>> List(CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var templates = await templateStore.ResolveAllAsync(companyId, cancellationToken);
        return Ok(new EmailTemplateListResponseDto
        {
            Templates = templates.Select(ToDto).ToList(),
            Delivery = DeliveryStatus()
        });
    }

    [HttpGet("{key}")]
    public async Task<ActionResult<EmailTemplateDto>> Get(string key, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var template = await templateStore.ResolveAsync(companyId, key, cancellationToken);
        return template is null ? NotFound() : Ok(ToDto(template));
    }

    [HttpPut("{key}")]
    public async Task<ActionResult<EmailTemplateDto>> Update(
        string key,
        [FromBody] UpdateEmailTemplateRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var definition = EmailTemplateCatalog.Find(key);
        if (definition is null)
        {
            return NotFound();
        }

        var subject = request.Subject?.Trim() ?? string.Empty;
        var htmlBody = request.HtmlBody ?? string.Empty;
        var textBody = request.TextBody ?? string.Empty;
        var errors = EmailTemplateCatalog.Validate(definition, subject, htmlBody, textBody);
        if (errors.Count > 0)
        {
            return ValidationFailure(errors);
        }

        var existing = await dbContext.EmailTemplates
            .SingleOrDefaultAsync(template => template.CompanyInstallationId == companyId && template.Key == definition.Key, cancellationToken);
        var before = EmailTemplateStore.Resolve(definition, existing);
        var now = DateTimeOffset.UtcNow;
        var actorId = ActorUserId();

        if (existing is null)
        {
            existing = new EmailTemplate
            {
                CompanyInstallationId = companyId,
                Key = definition.Key,
                CreatedAt = now
            };
            dbContext.EmailTemplates.Add(existing);
        }

        existing.Subject = subject;
        existing.HtmlBody = htmlBody;
        existing.TextBody = textBody;
        existing.IsEnabled = request.IsEnabled ?? existing.IsEnabled;
        existing.UpdatedByUserId = actorId;
        existing.UpdatedAt = now;

        var after = EmailTemplateStore.Resolve(definition, existing);
        dbContext.AuditLogEntries.Add(AuditEntry(companyId, actorId, "email_template.updated", definition.Key, before, after));
        await dbContext.SaveChangesAsync(cancellationToken);

        return Ok(ToDto(after));
    }

    [HttpPost("{key}/reset")]
    public async Task<ActionResult<EmailTemplateDto>> ResetToDefault(string key, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var definition = EmailTemplateCatalog.Find(key);
        if (definition is null)
        {
            return NotFound();
        }

        var existing = await dbContext.EmailTemplates
            .SingleOrDefaultAsync(template => template.CompanyInstallationId == companyId && template.Key == definition.Key, cancellationToken);
        if (existing is not null)
        {
            var before = EmailTemplateStore.Resolve(definition, existing);
            dbContext.EmailTemplates.Remove(existing);
            dbContext.AuditLogEntries.Add(AuditEntry(
                companyId,
                ActorUserId(),
                "email_template.reset",
                definition.Key,
                before,
                EmailTemplateStore.Resolve(definition, null)));
            await dbContext.SaveChangesAsync(cancellationToken);
        }

        return Ok(ToDto(EmailTemplateStore.Resolve(definition, null)));
    }

    /// <summary>Renders a draft (or the saved template) with sample values.</summary>
    [HttpPost("{key}/preview")]
    public async Task<ActionResult<PreviewEmailTemplateResponseDto>> Preview(
        string key,
        [FromBody] PreviewEmailTemplateRequestDto? request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var template = await templateStore.ResolveAsync(companyId, key, cancellationToken);
        if (template is null)
        {
            return NotFound();
        }

        var rendered = RenderSample(template, request?.Subject, request?.HtmlBody, request?.TextBody);
        return Ok(new PreviewEmailTemplateResponseDto
        {
            Subject = rendered.Subject,
            HtmlBody = rendered.HtmlBody,
            TextBody = rendered.TextBody
        });
    }

    /// <summary>Queues a sample-data email to the given address through the real provider.</summary>
    [HttpPost("{key}/test")]
    public async Task<ActionResult<EmailMessageDto>> SendTest(
        string key,
        [FromBody] SendTestEmailRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var template = await templateStore.ResolveAsync(companyId, key, cancellationToken);
        if (template is null)
        {
            return NotFound();
        }

        var toEmail = request.ToEmail?.Trim();
        if (string.IsNullOrWhiteSpace(toEmail) || !MailAddress.TryCreate(toEmail, out _))
        {
            return ValidationFailure(new Dictionary<string, string[]> { ["toEmail"] = ["Enter a valid email address."] });
        }

        if (!emailSender.IsConfigured)
        {
            return ValidationFailure(new Dictionary<string, string[]>
            {
                ["delivery"] = [$"Email provider '{emailSender.ProviderName}' is not configured. Set the Email section in appsettings."]
            });
        }

        var rendered = RenderSample(template, request.Subject, request.HtmlBody, request.TextBody);
        var now = DateTimeOffset.UtcNow;
        var message = new EmailMessage
        {
            CompanyInstallationId = companyId,
            UserId = null,
            TemplateKey = template.Definition.Key,
            ToEmail = toEmail,
            ToName = null,
            Subject = $"[Test] {rendered.Subject}",
            HtmlBody = rendered.HtmlBody,
            TextBody = rendered.TextBody,
            Status = "pending",
            NextAttemptAt = now,
            MetadataJson = JsonSerializer.Serialize(new { test = true, actorUserId = ActorUserId() }),
            CreatedAt = now,
            UpdatedAt = now
        };
        dbContext.EmailMessages.Add(message);
        await dbContext.SaveChangesAsync(cancellationToken);

        return Accepted(ToDto(message));
    }

    [HttpGet("~/api/v1/admin/email-messages")]
    public async Task<ActionResult<EmailMessageListResponseDto>> RecentMessages(
        [FromQuery] string? templateKey,
        [FromQuery] string? status,
        [FromQuery] int take = 50,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var query = dbContext.EmailMessages
            .AsNoTracking()
            .Where(message => message.CompanyInstallationId == companyId);
        if (!string.IsNullOrWhiteSpace(templateKey))
        {
            var normalizedKey = templateKey.Trim();
            query = query.Where(message => message.TemplateKey == normalizedKey);
        }

        if (!string.IsNullOrWhiteSpace(status))
        {
            var normalizedStatus = status.Trim().ToLowerInvariant();
            query = query.Where(message => message.Status == normalizedStatus);
        }

        var total = await query.CountAsync(cancellationToken);
        var items = await query
            .OrderByDescending(message => message.CreatedAt)
            .Take(Math.Clamp(take, 1, 200))
            .ToListAsync(cancellationToken);

        return Ok(new EmailMessageListResponseDto
        {
            Items = items.Select(ToDto).ToList(),
            TotalCount = total
        });
    }

    private RenderedEmail RenderSample(ResolvedEmailTemplate template, string? subject, string? htmlBody, string? textBody)
    {
        var values = outbox.CompanyValues();
        foreach (var (name, sample) in template.Definition.SampleValues())
        {
            // Company-derived placeholders keep real values so the preview shows the actual brand.
            values.TryAdd(name, sample);
        }

        return EmailTemplateRenderer.Render(
            string.IsNullOrWhiteSpace(subject) ? template.Subject : subject,
            string.IsNullOrWhiteSpace(htmlBody) ? template.HtmlBody : htmlBody,
            textBody ?? template.TextBody,
            values);
    }

    private EmailDeliveryStatusDto DeliveryStatus()
    {
        var options = emailOptions.Value;
        return new EmailDeliveryStatusDto
        {
            Provider = emailSender.ProviderName,
            Configured = emailSender.IsConfigured,
            FromEmail = options.FromEmail,
            FromName = options.FromName,
            ReplyToEmail = options.ReplyToEmail
        };
    }

    private Guid? ActorUserId()
    {
        return TryGetLocalUserId(out var actorId) && Guid.TryParse(actorId, out var parsed) ? parsed : null;
    }

    private AuditLogEntry AuditEntry(
        Guid companyId,
        Guid? actorId,
        string action,
        string templateKey,
        ResolvedEmailTemplate before,
        ResolvedEmailTemplate after)
    {
        return new AuditLogEntry
        {
            CompanyInstallationId = companyId,
            ActorUserId = actorId,
            Action = action,
            EntityType = "email_template",
            TraceId = HttpContext.TraceIdentifier,
            IpAddress = GetClientIpAddress(),
            UserAgent = Request.Headers.UserAgent.ToString(),
            BeforeJson = JsonSerializer.Serialize(AuditShape(before), JsonOptions),
            AfterJson = JsonSerializer.Serialize(AuditShape(after), JsonOptions),
            MetadataJson = JsonSerializer.Serialize(new { source = "wl_admin", templateKey }, JsonOptions)
        };
    }

    private static object AuditShape(ResolvedEmailTemplate template)
    {
        return new
        {
            template.Subject,
            template.IsEnabled,
            template.IsCustomized,
            HtmlLength = template.HtmlBody.Length,
            TextLength = template.TextBody.Length
        };
    }

    private BadRequestObjectResult ValidationFailure(Dictionary<string, string[]> errors)
    {
        return BadRequest(new ValidationProblemDetails(errors)
        {
            Title = "Check the email template fields and try again.",
            Status = StatusCodes.Status400BadRequest
        });
    }

    private static EmailTemplateDto ToDto(ResolvedEmailTemplate template)
    {
        return new EmailTemplateDto
        {
            Key = template.Definition.Key,
            Name = template.Definition.Name,
            Description = template.Definition.Description,
            Subject = template.Subject,
            HtmlBody = template.HtmlBody,
            TextBody = template.TextBody,
            IsEnabled = template.IsEnabled,
            IsCustomized = template.IsCustomized,
            UpdatedAt = template.UpdatedAt,
            Placeholders = template.Definition.Placeholders
                .Select(placeholder => new EmailPlaceholderDto
                {
                    Name = placeholder.Name,
                    Description = placeholder.Description,
                    Sample = placeholder.Sample,
                    Required = placeholder.Required
                })
                .ToList()
        };
    }

    private static EmailMessageDto ToDto(EmailMessage message)
    {
        return new EmailMessageDto
        {
            Id = message.Id,
            TemplateKey = message.TemplateKey,
            ToEmail = message.ToEmail,
            Subject = message.Subject,
            Status = message.Status,
            AttemptCount = message.AttemptCount,
            CreatedAt = message.CreatedAt,
            SentAt = message.SentAt,
            ErrorMessage = message.ErrorMessage
        };
    }
}
