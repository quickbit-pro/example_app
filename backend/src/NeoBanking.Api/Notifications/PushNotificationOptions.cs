namespace NeoBanking.Api.Notifications;

public sealed class PushNotificationOptions
{
    public const string SectionName = "PushNotifications";

    public bool Enabled { get; init; }

    public string? FirebaseProjectId { get; init; }

    public string? ServiceAccountPath { get; init; }

    public int MaxAttempts { get; init; } = 5;
}
