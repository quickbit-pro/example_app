#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class WebhookEndpoint : CompanyScopedEntity
{
    public string Provider { get; set; } = string.Empty;

    public string Url { get; set; } = string.Empty;

    public string? Description { get; set; }

    public string SecretHash { get; set; } = string.Empty;

    public string Status { get; set; } = "active";

    public string EventTypesJson { get; set; } = "[]";

    public string HeadersJson { get; set; } = "{}";

    public ICollection<WebhookDelivery> Deliveries { get; set; } = new List<WebhookDelivery>();
}
