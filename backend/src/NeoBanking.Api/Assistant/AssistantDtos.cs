using System.Text.Json.Serialization;

namespace NeoBanking.Api.Assistant;

public sealed record AssistantHistoryMessage(string Role, string Content);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record AssistantDepartureDto(string City, string? CountryCode = null, string? AirportCode = null);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record AssistantChatRequest(string Message, IReadOnlyList<AssistantHistoryMessage>? History = null, string? Locale = null,
    AssistantDepartureDto? Departure = null, string? SpendingPeriod = null, IReadOnlyList<string>? SpendingQuestions = null);
public sealed record AssistantUsageDto(bool Enabled, int DailyLimit, int Used, int Remaining, DateTimeOffset ResetsAt, int MaxMessageCharacters);
public sealed record AssistantActionDto(string Label, string Url, string Kind);
public sealed record AssistantSourceDto(string Title, string Url);
public sealed record AssistantAnswerOptionDto(string Title, IReadOnlyList<string> Highlights, string? Details = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] AssistantSourceDto? Source = null);
public sealed record AssistantAnswerDto(string Title, string Summary, IReadOnlyList<AssistantAnswerOptionDto> Options, string? NextStep = null);
public sealed record AssistantChatDto(string Reply, IReadOnlyList<AssistantActionDto> Actions,
    IReadOnlyList<AssistantSourceDto> Sources, bool WebSearchUsed, AssistantUsageDto Usage, bool Refused,
    AssistantAnswerDto? Answer = null, string? Verification = null, AssistantSpendingSummaryDto? Spending = null);
