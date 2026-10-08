#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class AuditLogEntry : Entity
{
    public Guid? CompanyInstallationId { get; set; }

    public CompanyInstallation? CompanyInstallation { get; set; }

    public Guid? ActorUserId { get; set; }

    public ApplicationUser? ActorUser { get; set; }

    public Guid? ActorIdentityId { get; set; }

    public string Action { get; set; } = string.Empty;

    public string EntityType { get; set; } = string.Empty;

    public Guid? EntityId { get; set; }

    public string? TraceId { get; set; }

    public string? IpAddress { get; set; }

    public string? UserAgent { get; set; }

    public DateTimeOffset OccurredAt { get; set; } = DateTimeOffset.UtcNow;

    public string? BeforeJson { get; set; }

    public string? AfterJson { get; set; }

    public string MetadataJson { get; set; } = "{}";
}
