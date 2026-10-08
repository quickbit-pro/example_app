using System;
using System.Collections.Generic;

namespace NeoBanking.Application.DTOs.Admin;

public sealed class AdminUserSummaryDto
{
    public Guid LocalUserId { get; init; }

    public string? HoppaUserId { get; init; }

    public string? UserId => HoppaUserId;

    public string? DisplayName { get; init; }

    public string? Email { get; init; }

    public string? Status { get; init; }

    public DateTimeOffset? CreatedAt { get; init; }

    public DateTimeOffset? UpdatedAt { get; init; }

    public DateTimeOffset? LastLoginAt { get; init; }

    public string? KycStatus { get; init; }

    public string? KycLevel { get; init; }

    public string? KycProvider { get; init; }

    public string? KycProviderReference { get; init; }

    public string? Tier { get; init; }
}

public sealed class AdminUserListResponseDto
{
    public IReadOnlyList<AdminUserSummaryDto> Items { get; init; } = Array.Empty<AdminUserSummaryDto>();

    public int TotalCount { get; init; }
}

public sealed class AdminKycCaseSummaryDto
{
    public Guid CaseId { get; init; }

    public Guid LocalUserId { get; init; }

    public string? HoppaUserId { get; init; }

    public string? DisplayName { get; init; }

    public string? Email { get; init; }

    public string? Status { get; init; }

    public string? Level { get; init; }

    public string? Provider { get; init; }

    public string? ProviderReference { get; init; }

    public string? CountryCode { get; init; }

    public DateTimeOffset StartedAt { get; init; }

    public DateTimeOffset? SubmittedAt { get; init; }

    public DateTimeOffset? ReviewedAt { get; init; }
}

public sealed class AdminKycCaseListResponseDto
{
    public IReadOnlyList<AdminKycCaseSummaryDto> Items { get; init; } = Array.Empty<AdminKycCaseSummaryDto>();

    public int TotalCount { get; init; }
}

public sealed class AdminUserDecisionRequestDto
{
    public string? Decision { get; init; }

    public string? Reason { get; init; }
}

public sealed class AdminStatusUpdateRequestDto
{
    public string? Status { get; init; }

    public string? Reason { get; init; }
}

public sealed class AdminCardDecisionRequestDto
{
    public string? Decision { get; init; }

    public string? Reason { get; init; }
}

public sealed class AdminTransactionAdjustmentRequestDto
{
    public string? Reason { get; init; }

    public decimal? Amount { get; init; }

    public string? Currency { get; init; }
}
