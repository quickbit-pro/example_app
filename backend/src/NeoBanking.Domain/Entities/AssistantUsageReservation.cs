#nullable enable

namespace NeoBanking.Domain.Entities;

/// <summary>One charged assistant request. Message contents are deliberately never persisted.</summary>
public sealed class AssistantUsageReservation : Entity
{
    public Guid CompanyInstallationId { get; set; }

    public Guid UserId { get; set; }

    public DateTimeOffset ReservedAt { get; set; }

    public DateTimeOffset? ActiveUntil { get; set; }
}
