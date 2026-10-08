using NeoBanking.Application.DTOs.Kyc;

namespace NeoBanking.Application.UseCases.Kyc;

public sealed class CreateSumSubAccessTokenCommand
{
    public string AuthenticatedUserId { get; init; } = string.Empty;

    public string? ClientIpAddress { get; init; }

    public SumSubAccessTokenRequestDto Request { get; init; } = new();
}
