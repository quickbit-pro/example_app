namespace NeoBanking.Api.Assistant;

public sealed class AssistantOptions
{
    public const string SectionName = "Assistant";
    public bool Enabled { get; set; }
    public bool WebSearchEnabled { get; set; } = true;
    // Enable in the deployment overlay after updating the mobile/PWA client.
    public bool RecommendationLinksEnabled { get; set; }
    public int DailyLimit { get; set; } = 50;
    public int PerMinuteLimit { get; set; } = 5;
    public int GlobalDailyLimit { get; set; } = 500;
    public int TimeoutSeconds { get; set; } = 90;
    // The mobile client waits 100 seconds and nginx waits 120 seconds.
    public int RequestTimeoutSeconds => Math.Clamp(TimeoutSeconds, 5, 90);
    public int LeaseSeconds => Math.Max(60, RequestTimeoutSeconds + 15);
}
