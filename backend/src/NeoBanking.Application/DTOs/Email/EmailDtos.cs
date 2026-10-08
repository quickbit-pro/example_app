namespace NeoBanking.Application.DTOs.Email;

public sealed class EmailPlaceholderDto
{
    public string Name { get; init; } = string.Empty;

    public string Description { get; init; } = string.Empty;

    public string Sample { get; init; } = string.Empty;

    public bool Required { get; init; }
}

public sealed class EmailTemplateDto
{
    public string Key { get; init; } = string.Empty;

    public string Name { get; init; } = string.Empty;

    public string Description { get; init; } = string.Empty;

    public string Subject { get; init; } = string.Empty;

    public string HtmlBody { get; init; } = string.Empty;

    public string TextBody { get; init; } = string.Empty;

    public bool IsEnabled { get; init; } = true;

    /// <summary>True when an admin has saved an override for this template.</summary>
    public bool IsCustomized { get; init; }

    public IReadOnlyList<EmailPlaceholderDto> Placeholders { get; init; } = [];

    public DateTimeOffset? UpdatedAt { get; init; }
}

public sealed class EmailDeliveryStatusDto
{
    public string Provider { get; init; } = string.Empty;

    public bool Configured { get; init; }

    public string FromEmail { get; init; } = string.Empty;

    public string FromName { get; init; } = string.Empty;

    public string? ReplyToEmail { get; init; }
}

public sealed class EmailTemplateListResponseDto
{
    public IReadOnlyList<EmailTemplateDto> Templates { get; init; } = [];

    public EmailDeliveryStatusDto Delivery { get; init; } = new();
}

public sealed class UpdateEmailTemplateRequestDto
{
    public string? Subject { get; init; }

    public string? HtmlBody { get; init; }

    public string? TextBody { get; init; }

    public bool? IsEnabled { get; init; }
}

public sealed class PreviewEmailTemplateRequestDto
{
    public string? Subject { get; init; }

    public string? HtmlBody { get; init; }

    public string? TextBody { get; init; }
}

public sealed class PreviewEmailTemplateResponseDto
{
    public string Subject { get; init; } = string.Empty;

    public string HtmlBody { get; init; } = string.Empty;

    public string TextBody { get; init; } = string.Empty;
}

public sealed class SendTestEmailRequestDto
{
    public string? ToEmail { get; init; }

    public string? Subject { get; init; }

    public string? HtmlBody { get; init; }

    public string? TextBody { get; init; }
}

public sealed class EmailMessageDto
{
    public Guid Id { get; init; }

    public string TemplateKey { get; init; } = string.Empty;

    public string ToEmail { get; init; } = string.Empty;

    public string Subject { get; init; } = string.Empty;

    public string Status { get; init; } = string.Empty;

    public int AttemptCount { get; init; }

    public DateTimeOffset CreatedAt { get; init; }

    public DateTimeOffset? SentAt { get; init; }

    public string? ErrorMessage { get; init; }
}

public sealed class EmailMessageListResponseDto
{
    public IReadOnlyList<EmailMessageDto> Items { get; init; } = [];

    public int TotalCount { get; init; }
}
