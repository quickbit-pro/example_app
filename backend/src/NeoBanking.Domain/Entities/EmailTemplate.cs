#nullable enable

namespace NeoBanking.Domain.Entities;

/// <summary>
/// Admin-editable override for one transactional email. When no row exists for a
/// template key the built-in default from the template catalog is used.
/// </summary>
public sealed class EmailTemplate : CompanyScopedEntity
{
    public string Key { get; set; } = string.Empty;

    public string Subject { get; set; } = string.Empty;

    public string HtmlBody { get; set; } = string.Empty;

    public string TextBody { get; set; } = string.Empty;

    public bool IsEnabled { get; set; } = true;

    public Guid? UpdatedByUserId { get; set; }
}
