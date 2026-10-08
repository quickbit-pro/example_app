#nullable enable

using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.Email;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Infrastructure.Email;

public sealed record ResolvedEmailTemplate(
    EmailTemplateDefinition Definition,
    string Subject,
    string HtmlBody,
    string TextBody,
    bool IsEnabled,
    bool IsCustomized,
    DateTimeOffset? UpdatedAt);

/// <summary>
/// Resolves the effective template for an installation: the admin override
/// when one exists, otherwise the catalog default.
/// </summary>
public sealed class EmailTemplateStore(NeoBankingDbContext dbContext)
{
    public async Task<ResolvedEmailTemplate?> ResolveAsync(
        Guid companyInstallationId,
        string key,
        CancellationToken cancellationToken)
    {
        var definition = EmailTemplateCatalog.Find(key);
        if (definition is null)
        {
            return null;
        }

        var stored = await dbContext.EmailTemplates
            .AsNoTracking()
            .SingleOrDefaultAsync(
                template => template.CompanyInstallationId == companyInstallationId && template.Key == definition.Key,
                cancellationToken);

        return Resolve(definition, stored);
    }

    public async Task<IReadOnlyList<ResolvedEmailTemplate>> ResolveAllAsync(
        Guid companyInstallationId,
        CancellationToken cancellationToken)
    {
        var stored = await dbContext.EmailTemplates
            .AsNoTracking()
            .Where(template => template.CompanyInstallationId == companyInstallationId)
            .ToDictionaryAsync(template => template.Key, StringComparer.OrdinalIgnoreCase, cancellationToken);

        return EmailTemplateCatalog.All
            .Select(definition => Resolve(definition, stored.GetValueOrDefault(definition.Key)))
            .ToList();
    }

    public static ResolvedEmailTemplate Resolve(EmailTemplateDefinition definition, EmailTemplate? stored)
    {
        return stored is null
            ? new ResolvedEmailTemplate(
                definition,
                definition.DefaultSubject,
                definition.DefaultHtmlBody,
                definition.DefaultTextBody,
                IsEnabled: true,
                IsCustomized: false,
                UpdatedAt: null)
            : new ResolvedEmailTemplate(
                definition,
                stored.Subject,
                stored.HtmlBody,
                stored.TextBody,
                stored.IsEnabled,
                IsCustomized: true,
                stored.UpdatedAt);
    }
}
