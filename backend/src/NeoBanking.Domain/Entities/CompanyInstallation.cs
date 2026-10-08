#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class CompanyInstallation : AuditableEntity
{
    public string Slug { get; set; } = string.Empty;

    public string LegalName { get; set; } = string.Empty;

    public string DisplayName { get; set; } = string.Empty;

    public string Status { get; set; } = "pending";

    public string CountryCode { get; set; } = "US";

    public string DefaultCurrency { get; set; } = "USD";

    public string SettingsJson { get; set; } = "{}";

    public ICollection<ApplicationUser> Users { get; set; } = new List<ApplicationUser>();

    public ICollection<ProviderMapping> ProviderMappings { get; set; } = new List<ProviderMapping>();

    public ICollection<OnboardingApplication> OnboardingApplications { get; set; } = new List<OnboardingApplication>();

    public ICollection<WebhookEndpoint> WebhookEndpoints { get; set; } = new List<WebhookEndpoint>();

    public ICollection<IdempotencyRecord> IdempotencyRecords { get; set; } = new List<IdempotencyRecord>();

    public ICollection<AuditLogEntry> AuditLogs { get; set; } = new List<AuditLogEntry>();
}
