using System.Collections.Generic;
using System.Net;
using System.Threading;
using System.Threading.Tasks;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Kyc;
using NeoBanking.Application.Interfaces;

namespace NeoBanking.Application.UseCases.Kyc;

public sealed class CreateSumSubAccessTokenUseCase : ICreateSumSubAccessTokenUseCase
{
    private readonly IHoppaKycClient _hoppaKycClient;

    public CreateSumSubAccessTokenUseCase(IHoppaKycClient hoppaKycClient)
    {
        _hoppaKycClient = hoppaKycClient;
    }

    public Task<ApplicationResult<SumSubAccessTokenResponseDto>> ExecuteAsync(
        CreateSumSubAccessTokenCommand command,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(command.AuthenticatedUserId))
        {
            return Task.FromResult(ApplicationResult<SumSubAccessTokenResponseDto>.Failure(
                new ApplicationError(
                    "identity.missing",
                    "Authenticated user identity is required.",
                    (int)HttpStatusCode.Unauthorized)));
        }

        var validationErrors = Validate(command.Request);
        if (validationErrors.Count > 0)
        {
            return Task.FromResult(ApplicationResult<SumSubAccessTokenResponseDto>.Failure(
                new ApplicationError(
                    "request.invalid",
                    "The request payload is invalid.",
                    (int)HttpStatusCode.BadRequest,
                    validationErrors: validationErrors)));
        }

        return _hoppaKycClient.CreateSumSubAccessTokenAsync(
            command.AuthenticatedUserId,
            command.ClientIpAddress,
            command.Request,
            cancellationToken);
    }

    private static IReadOnlyDictionary<string, string[]> Validate(SumSubAccessTokenRequestDto request)
    {
        var errors = new Dictionary<string, string[]>();

        if (string.IsNullOrWhiteSpace(request.Occupation))
        {
            errors[nameof(request.Occupation)] = new[] { "Occupation is required." };
        }
        else if (request.Occupation.Length > 120)
        {
            errors[nameof(request.Occupation)] = new[] { "Occupation must not exceed 120 characters." };
        }

        if (request.AnnualSalary is null)
        {
            errors[nameof(request.AnnualSalary)] = new[] { "Annual salary is required." };
        }
        else if (string.IsNullOrWhiteSpace(request.AnnualSalary))
        {
            errors[nameof(request.AnnualSalary)] = new[] { "Annual salary is required." };
        }
        else if (request.AnnualSalary.Length > 40)
        {
            errors[nameof(request.AnnualSalary)] = new[] { "Annual salary range must not exceed 40 characters." };
        }

        if (string.IsNullOrWhiteSpace(request.AccountPurpose))
        {
            errors[nameof(request.AccountPurpose)] = new[] { "Account purpose is required." };
        }
        else if (request.AccountPurpose.Length > 160)
        {
            errors[nameof(request.AccountPurpose)] = new[] { "Account purpose must not exceed 160 characters." };
        }

        if (request.ExpectedMonthlyVolume is null)
        {
            errors[nameof(request.ExpectedMonthlyVolume)] = new[] { "Expected monthly volume is required." };
        }
        else if (string.IsNullOrWhiteSpace(request.ExpectedMonthlyVolume))
        {
            errors[nameof(request.ExpectedMonthlyVolume)] = new[] { "Expected monthly volume is required." };
        }
        else if (request.ExpectedMonthlyVolume.Length > 40)
        {
            errors[nameof(request.ExpectedMonthlyVolume)] = new[] { "Expected monthly volume range must not exceed 40 characters." };
        }

        if (request.DocumentIssueDate is null)
        {
            errors[nameof(request.DocumentIssueDate)] = new[] { "Document issue date is required." };
        }
        else if (request.DocumentIssueDate > DateOnly.FromDateTime(DateTime.UtcNow))
        {
            errors[nameof(request.DocumentIssueDate)] = new[] { "Document issue date must not be in the future." };
        }

        return errors;
    }
}
