using System.Threading;
using System.Threading.Tasks;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Kyc;

namespace NeoBanking.Application.UseCases.Kyc;

public interface ICreateSumSubAccessTokenUseCase
{
    Task<ApplicationResult<SumSubAccessTokenResponseDto>> ExecuteAsync(
        CreateSumSubAccessTokenCommand command,
        CancellationToken cancellationToken);
}
