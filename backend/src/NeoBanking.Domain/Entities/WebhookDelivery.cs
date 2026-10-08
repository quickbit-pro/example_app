#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class WebhookDelivery : CompanyScopedEntity
{
    public Guid? WebhookEndpointId { get; set; }

    public WebhookEndpoint? WebhookEndpoint { get; set; }

    public string Provider { get; set; } = string.Empty;

    public string EventId { get; set; } = string.Empty;

    public string EventType { get; set; } = string.Empty;

    public string Status { get; set; } = "received";

    public int AttemptCount { get; set; }

    public DateTimeOffset ReceivedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? LastAttemptAt { get; set; }

    public DateTimeOffset? NextAttemptAt { get; set; }

    public DateTimeOffset? ProcessedAt { get; set; }

    public int? ResponseStatusCode { get; set; }

    public string? ResponseBody { get; set; }

    public string? ErrorMessage { get; set; }

    public string? IdempotencyKey { get; set; }

    public string HeadersJson { get; set; } = "{}";

    public string PayloadJson { get; set; } = "{}";
}
