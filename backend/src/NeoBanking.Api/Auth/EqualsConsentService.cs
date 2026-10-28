using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Auth;

public sealed record EqualsConsentDocuments(string TermsUrl, string PrivacyUrl, string Version, bool Available);
public sealed record EqualsConsentStatus(bool Required, bool RequiresAcceptance, EqualsConsentDocuments Documents);

/// <summary>Append-only acceptance evidence, separate from editable profile metadata.</summary>
public sealed class EqualsConsentService(NeoBankingDbContext db, IOptions<CompanyOptions> options, DashboardLegalSettings? legalSettings = null)
{
    public const string AcceptanceAction = "equals.agreement.accepted";

    public static EqualsConsentDocuments Documents(BrandingOptions branding)
    {
        var terms = branding.EqualsGeneralTermsUrl ?? "";
        var privacy = EqualsSignupConsent.PrivacyUrl(branding.EqualsRegulatoryRegionDefault);
        // Publish changed documents at a new immutable URL. This identifies URLs, not file contents.
        var version = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
            JsonSerializer.Serialize(string.IsNullOrEmpty(branding.EqualsTermsVersion)
                ? new[] { terms, privacy } : new[] { terms, privacy, branding.EqualsTermsVersion })))).ToLowerInvariant();
        return new(terms, privacy, version,
            Uri.TryCreate(terms, UriKind.Absolute, out var uri) && uri.Scheme == "https");
    }

    public Task<BrandingOptions> BrandingAsync(CancellationToken ct) =>
        legalSettings?.GetAsync(ct) ?? Task.FromResult(options.Value.Branding);

    public bool Required(ApplicationUser user)
    {
        if (options.Value.Features.EqualsMoneyEnabled) return true;
        try
        {
            using var metadata = JsonDocument.Parse(user.MetadataJson);
            return metadata.RootElement.TryGetProperty("accountType", out var accountType) &&
                accountType.GetString() == "business";
        }
        catch (JsonException) { return true; } // Invalid account metadata cannot silently waive consent.
    }

    public async Task<EqualsConsentStatus> StatusAsync(ApplicationUser user, CancellationToken ct)
    {
        var documents = Documents(await BrandingAsync(ct));
        if (!Required(user)) return new(false, false, documents);
        if (!documents.Available) return new(true, true, documents);
        var types = await db.AuditLogEntries.AsNoTracking()
            .Where(x => x.ActorUserId == user.Id && x.CompanyInstallationId == user.CompanyInstallationId &&
                x.EntityId == user.Id && x.Action == AcceptanceAction && x.TraceId == documents.Version)
            .Select(x => x.EntityType).Distinct().ToListAsync(ct);
        return new(true, !types.Contains("equals_money_terms") || !types.Contains("equals_money_privacy"), documents);
    }

    public static void AddEvidence(NeoBankingDbContext db, ApplicationUser user, BrandingOptions branding,
        DateTimeOffset receivedAt, string channel)
    {
        var documents = Documents(branding);
        foreach (var (type, url) in new[] { ("equals_money_terms", documents.TermsUrl), ("equals_money_privacy", documents.PrivacyUrl) })
        {
            db.AuditLogEntries.Add(new AuditLogEntry {
                CompanyInstallationId = user.CompanyInstallationId, ActorUserId = user.Id,
                EntityId = user.Id, EntityType = type, Action = AcceptanceAction,
                TraceId = documents.Version, OccurredAt = receivedAt,
                MetadataJson = JsonSerializer.Serialize(new {
                    agreementType = type, documentUrl = url, documentVersionReference = type == "equals_money_terms" ? branding.EqualsTermsVersion ?? url : url,
                    documentSetVersion = documents.Version, acceptedAt = receivedAt, channel,
                    termsAccessReported = true
                })
            });
        }
    }
}
