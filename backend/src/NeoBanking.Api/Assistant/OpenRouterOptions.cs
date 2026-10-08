namespace NeoBanking.Api.Assistant;

public sealed class OpenRouterOptions
{
    public const string SectionName = "OpenRouter";

    // Configure through backend secrets (OpenRouter__ApiKey), never mobile configuration.
    public string ApiKey { get; set; } = string.Empty;
    public string Model { get; set; } = "deepseek/deepseek-v4.1-flash";
    public int TimeoutSeconds { get; set; } = 90;
}
