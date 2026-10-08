#nullable enable

namespace NeoBanking.Domain.Entities;

/// <summary>
/// Outbox row for one rendered email. The dispatcher delivers it through the
/// configured provider and records the outcome.
/// </summary>
public sealed class EmailMessage : CompanyScopedEntity
{
    public Guid? UserId { get; set; }

    public ApplicationUser? User { get; set; }

    public string TemplateKey { get; set; } = string.Empty;

    public string ToEmail { get; set; } = string.Empty;

    public string? ToName { get; set; }

    public string Subject { get; set; } = string.Empty;

    public string HtmlBody { get; set; } = string.Empty;

    public string TextBody { get; set; } = string.Empty;

    public string Status { get; set; } = "pending";

    public int AttemptCount { get; set; }

    public DateTimeOffset? NextAttemptAt { get; set; }

    public DateTimeOffset? SentAt { get; set; }

    public string? ProviderMessageId { get; set; }

    public string? ErrorMessage { get; set; }

    public string MetadataJson { get; set; } = "{}";
}
