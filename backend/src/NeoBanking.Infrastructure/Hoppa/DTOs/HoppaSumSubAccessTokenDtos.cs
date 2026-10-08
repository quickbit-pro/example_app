using System;
using System.Text.Json.Serialization;

namespace NeoBanking.Infrastructure.Hoppa.DTOs;

internal sealed class HoppaSumSubAccessTokenRequest
{
    [JsonPropertyName("Occupation")]
    public string? Occupation { get; init; }

    [JsonPropertyName("AnnualSalary")]
    public string? AnnualSalary { get; init; }

    [JsonPropertyName("AccountPurpose")]
    public string? AccountPurpose { get; init; }

    [JsonPropertyName("ExpectedMonthlyVolume")]
    public string? ExpectedMonthlyVolume { get; init; }

    [JsonPropertyName("DocumentIssueDate")]
    public DateOnly? DocumentIssueDate { get; init; }

    [JsonPropertyName("IpAddress")]
    public string? IpAddress { get; init; }
}

internal sealed class HoppaSumSubAccessTokenResponse
{
    [JsonPropertyName("token")]
    public string? Token { get; init; }

    [JsonPropertyName("userId")]
    public string? UserId { get; init; }

    [JsonPropertyName("levelName")]
    public string? LevelName { get; init; }

    [JsonPropertyName("expiresAt")]
    public DateTimeOffset? ExpiresAt { get; init; }

    [JsonPropertyName("expiresInSecs")]
    public int? ExpiresInSecs { get; init; }
}
