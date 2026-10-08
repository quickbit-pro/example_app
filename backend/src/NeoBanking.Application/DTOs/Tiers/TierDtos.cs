namespace NeoBanking.Application.DTOs.Tiers;

public sealed class ChangeUserTierRequestDto
{
    public int? TierId { get; init; }

    public string? TierCycle { get; init; }

    public string? TierCode { get; init; }

    public string? Reason { get; init; }
}

public sealed class SetUserTierRequestDto
{
    public int TierId { get; init; }

    public string? TierCycle { get; init; }
}

public sealed class UpdateTierRequestDto
{
    public string? DisplayName { get; init; }

    public decimal? MonthlyFee { get; init; }

    public string? Currency { get; init; }

    public string? BenefitsJson { get; init; }

    public string? Status { get; init; }
}
