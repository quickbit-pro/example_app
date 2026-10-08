#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class PushDevice : CompanyScopedEntity
{
    public Guid UserId { get; set; }

    public ApplicationUser? User { get; set; }

    public string RegistrationToken { get; set; } = string.Empty;

    public string Platform { get; set; } = string.Empty;

    public string? AppVersion { get; set; }

    public string? Locale { get; set; }

    public bool IsEnabled { get; set; } = true;

    public DateTimeOffset LastSeenAt { get; set; } = DateTimeOffset.UtcNow;
}
