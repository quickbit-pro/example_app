using System.Threading;
using System.Threading.Tasks;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Kyc;

namespace NeoBanking.Application.Interfaces;

public interface IHoppaKycClient
{
    Task<ApplicationResult<SumSubAccessTokenResponseDto>> CreateSumSubAccessTokenAsync(
        string userId,
        string? clientIpAddress,
        SumSubAccessTokenRequestDto request,
        CancellationToken cancellationToken);
}
