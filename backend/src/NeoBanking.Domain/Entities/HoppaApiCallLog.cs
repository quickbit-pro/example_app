#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class HoppaApiCallLog : Entity
{
    public Guid? CompanyInstallationId { get; set; }

    public CompanyInstallation? CompanyInstallation { get; set; }

    public Guid? ActorUserId { get; set; }

    public ApplicationUser? ActorUser { get; set; }

    public string? TraceId { get; set; }

    public string? IpAddress { get; set; }

    public string? UserAgent { get; set; }

    public DateTimeOffset OccurredAt { get; set; } = DateTimeOffset.UtcNow;

    public string Direction { get; set; } = "outbound";

    public string AppMethod { get; set; } = string.Empty;

    public string AppPath { get; set; } = string.Empty;

    public string? AppQueryString { get; set; }

    public int? AppStatusCode { get; set; }

    public string? AppRequestJson { get; set; }

    public string? AppResponseJson { get; set; }

    public string HoppaMethod { get; set; } = string.Empty;

    public string HoppaEndpoint { get; set; } = string.Empty;

    public string? HoppaQueryString { get; set; }

    public int? HoppaStatusCode { get; set; }

    public long HoppaDurationMs { get; set; }

    public bool Succeeded { get; set; }

    public string? FailureCode { get; set; }

    public string? FailureMessage { get; set; }

    public string? HoppaRequestJson { get; set; }

    public string? HoppaResponseJson { get; set; }
}
