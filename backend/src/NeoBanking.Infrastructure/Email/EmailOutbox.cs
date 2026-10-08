#nullable enable

using System.Text.Json;
using Microsoft.Extensions.Logging;
using NeoBanking.Application.Company;
using NeoBanking.Application.Email;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Infrastructure.Email;

public sealed record EmailRequest(
    Guid CompanyInstallationId,
    Guid? UserId,
    string ToEmail,
    string? ToName,
    string TemplateKey,
    IReadOnlyDictionary<string, string> Values,
    string? MetadataJson = null);

/// <summary>
/// Renders a template for a recipient and stores it in the outbox. The caller
/// owns the unit of work: nothing is persisted until <c>SaveChangesAsync</c>.
/// </summary>
public sealed class EmailOutbox(
    NeoBankingDbContext dbContext,
    EmailTemplateStore templateStore,
    ICompanyContextAccessor companyContextAccessor,
    ILogger<EmailOutbox> logger)
{
    public async Task<EmailMessage?> EnqueueAsync(EmailRequest request, CancellationToken cancellationToken)
    {
        var template = await templateStore.ResolveAsync(request.CompanyInstallationId, request.TemplateKey, cancellationToken);
        if (template is null)
        {
            logger.LogError("Email template {TemplateKey} does not exist in the catalog.", request.TemplateKey);
            return null;
        }

        if (!template.IsEnabled)
        {
            logger.LogInformation("Email template {TemplateKey} is disabled; skipping {To}.", template.Definition.Key, request.ToEmail);
            return null;
        }

        var values = BuildValues(request);
        var rendered = EmailTemplateRenderer.Render(template.Subject, template.HtmlBody, template.TextBody, values);
        var now = DateTimeOffset.UtcNow;
        var message = new EmailMessage
        {
            CompanyInstallationId = request.CompanyInstallationId,
            UserId = request.UserId,
            TemplateKey = template.Definition.Key,
            ToEmail = request.ToEmail.Trim(),
            ToName = string.IsNullOrWhiteSpace(request.ToName) ? null : request.ToName.Trim(),
            Subject = rendered.Subject,
            HtmlBody = rendered.HtmlBody,
            TextBody = rendered.TextBody,
            Status = "pending",
            NextAttemptAt = now,
            MetadataJson = string.IsNullOrWhiteSpace(request.MetadataJson) ? "{}" : request.MetadataJson,
            CreatedAt = now,
            UpdatedAt = now
        };

        dbContext.EmailMessages.Add(message);
        return message;
    }

    /// <summary>
    /// Merges caller-supplied values over the company-wide placeholders
    /// (app name, support email, brand color, year).
    /// </summary>
    public IReadOnlyDictionary<string, string> BuildValues(EmailRequest request)
    {
        var values = CompanyValues();
        values["email"] = request.ToEmail.Trim();
        values["userName"] = string.IsNullOrWhiteSpace(request.ToName) ? request.ToEmail.Trim() : request.ToName.Trim();
        foreach (var (key, value) in request.Values)
        {
            values[key] = value;
        }

        return values;
    }

    public Dictionary<string, string> CompanyValues()
    {
        var company = companyContextAccessor.Current;
        return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["appName"] = company.BrandName,
            ["companyName"] = company.CompanyName,
            ["supportEmail"] = company.Branding.SupportEmail ?? string.Empty,
            ["brandColor"] = NormalizeColor(company.Branding.PrimaryColor),
            ["year"] = DateTime.UtcNow.Year.ToString()
        };
    }

    public static string SerializeMetadata(object metadata) => JsonSerializer.Serialize(metadata);

    private static string NormalizeColor(string? color)
    {
        if (string.IsNullOrWhiteSpace(color))
        {
            return "#2563EB";
        }

        var trimmed = color.Trim();
        return trimmed.StartsWith('#') ? trimmed : $"#{trimmed}";
    }
}
