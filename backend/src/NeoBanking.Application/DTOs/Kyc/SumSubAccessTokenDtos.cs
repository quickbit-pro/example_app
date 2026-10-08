using System;

namespace NeoBanking.Application.DTOs.Kyc;

public sealed class SumSubAccessTokenRequestDto
{
    public string? LevelName { get; init; }

    public int? TtlInSecs { get; init; }

    public string? Occupation { get; init; }

    public string? AnnualSalary { get; init; }

    public string? AccountPurpose { get; init; }

    public string? ExpectedMonthlyVolume { get; init; }

    public DateOnly? DocumentIssueDate { get; init; }
}

public sealed class SumSubAccessTokenResponseDto
{
    public string? Token { get; init; }

    public string? UserId { get; init; }

    public string? LevelName { get; init; }

    public DateTimeOffset? ExpiresAt { get; init; }
}
