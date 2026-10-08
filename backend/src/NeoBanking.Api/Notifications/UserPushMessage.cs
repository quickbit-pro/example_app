namespace NeoBanking.Api.Notifications;

public sealed record UserPushMessage(
    string Title,
    string Body,
    string Route,
    IReadOnlyDictionary<string, string> Data);
