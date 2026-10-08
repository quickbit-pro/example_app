#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class PushNotification : CompanyScopedEntity
{
    public Guid UserId { get; set; }

    public ApplicationUser? User { get; set; }

    public string EventId { get; set; } = string.Empty;

    public string EventType { get; set; } = string.Empty;

    public string Title { get; set; } = string.Empty;

    public string Body { get; set; } = string.Empty;

    public string Route { get; set; } = "/home";

    public string DataJson { get; set; } = "{}";

    public string Status { get; set; } = "pending";

    public int AttemptCount { get; set; }

    public DateTimeOffset? NextAttemptAt { get; set; }

    public DateTimeOffset? SentAt { get; set; }

    public DateTimeOffset? ReadAt { get; set; }

    public string? ErrorMessage { get; set; }
}
