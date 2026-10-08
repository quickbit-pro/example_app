using System.Threading;
using System.Threading.Tasks;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Kyc;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Application.UseCases.Kyc;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/kyc")]
public sealed class MobileKycController : ApiControllerBase
{
    private readonly ICreateSumSubAccessTokenUseCase _createSumSubAccessToken;
    private readonly IProxyHoppaRequestUseCase _proxyHoppa;

    public MobileKycController(
        ICreateSumSubAccessTokenUseCase createSumSubAccessToken,
        IProxyHoppaRequestUseCase proxyHoppa)
    {
        _createSumSubAccessToken = createSumSubAccessToken;
        _proxyHoppa = proxyHoppa;
    }

    [HttpGet("status")]
    public async Task<ActionResult<JsonElement?>> GetStatus(CancellationToken cancellationToken)
    {
        return await GetDetailedStatus(cancellationToken);
    }

    [HttpGet("detailed-status")]
    public async Task<ActionResult<JsonElement?>> GetDetailedStatus(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var result = await _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object?>
            {
                Method = HttpMethod.Get,
                UpstreamPath = $"/api/v2/users/{Segment(userId)}/kyc/detailed-status",
                FailureCode = "mobile.kyc.status.failed",
                FailureMessage = "We could not load KYC status."
            },
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpPost("equalsmoney/documents")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(51 * 1024 * 1024)]
    public async Task<ActionResult<JsonElement?>> SubmitEqualsMoneyDocument(
        [FromForm] EqualsMoneyAdditionalDocumentFormDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var validationError = ValidateEqualsMoneyDocument(request);
        if (validationError is not null)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(validationError));
        }

        using var form = BuildEqualsMoneyDocumentForm(request, EqualsMoneyDocumentFormShape.PublicApi);
        var result = await _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<MultipartFormDataContent>
            {
                Method = HttpMethod.Post,
                UpstreamPath = $"/api/v2/users/{Segment(userId)}/kyc/equalsmoney/documents",
                Request = form,
                FailureCode = "mobile.kyc.equalsmoney_document.failed",
                FailureMessage = "We could not upload the EqualsMoney document."
            },
            cancellationToken);

        if (!result.IsSuccess && IsRetriableEqualsMoneyDocumentUploadFailure(result.Error?.StatusCode))
        {
            using var hoppaForm = BuildEqualsMoneyDocumentForm(request, EqualsMoneyDocumentFormShape.Legacy);
            result = await _proxyHoppa.ExecuteAsync(
                new ProxyHoppaRequestCommand<MultipartFormDataContent>
                {
                    Method = HttpMethod.Post,
                    UpstreamPath = $"/api/v2/users/{Segment(userId)}/kyc/equalsmoney/documents",
                    Request = hoppaForm,
                    FailureCode = "mobile.kyc.equalsmoney_document.failed",
                    FailureMessage = "We could not upload the EqualsMoney document."
                },
                cancellationToken);
        }

        return ToActionResult(result);
    }

    [HttpPost("equalsmoney/information")]
    public async Task<ActionResult<JsonElement?>> SubmitEqualsMoneyInformation(
        [FromBody] EqualsMoneyAdditionalInformationDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var errors = new Dictionary<string, string[]>();
        if (string.IsNullOrWhiteSpace(request.Type))
        {
            errors[nameof(request.Type)] = ["Information type is required."];
        }

        if (string.IsNullOrWhiteSpace(request.Response) || request.Response.Trim().Length > 1000)
        {
            errors[nameof(request.Response)] = ["Response is required and must not exceed 1000 characters."];
        }

        if (errors.Count > 0)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.kyc.equalsmoney_information.required_fields",
                "EqualsMoney information response is missing or invalid.",
                StatusCodes.Status400BadRequest,
                validationErrors: errors)));
        }

        var result = await _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object>
            {
                Method = HttpMethod.Post,
                UpstreamPath = $"/api/v2/users/{Segment(userId)}/kyc/equalsmoney/information",
                Request = new
                {
                    Type = request.Type!.Trim(),
                    Response = request.Response!.Trim(),
                    AssociatedPersonId = string.IsNullOrWhiteSpace(request.AssociatedPersonId)
                        ? null
                        : request.AssociatedPersonId.Trim()
                },
                FailureCode = "mobile.kyc.equalsmoney_information.failed",
                FailureMessage = "We could not submit the EqualsMoney information response."
            },
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpGet("occupation-codes")]
    public async Task<ActionResult<JsonElement?>> GetOccupationCodes(CancellationToken cancellationToken)
    {
        var result = await _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object?>
            {
                Method = HttpMethod.Get,
                UpstreamPath = "/api/v2/users/occupation-codes",
                FailureCode = "mobile.kyc.occupation_codes.failed",
                FailureMessage = "We could not load occupation codes."
            },
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpPost("sumsub-token")]
    public async Task<ActionResult<SumSubAccessTokenResponseDto>> CreateSumSubToken(
        [FromBody] SumSubAccessTokenRequestDto? request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<SumSubAccessTokenResponseDto>();
        }

        var validationError = ValidateSumSubRequiredFields(request);
        if (validationError is not null)
        {
            return ToActionResult(ApplicationResult<SumSubAccessTokenResponseDto>.Failure(validationError));
        }

        var result = await _createSumSubAccessToken.ExecuteAsync(
            new CreateSumSubAccessTokenCommand
            {
                AuthenticatedUserId = userId,
                ClientIpAddress = GetClientIpAddress(),
                Request = request ?? new SumSubAccessTokenRequestDto()
            },
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpPost("url")]
    [HttpPost("hosted-url")]
    public async Task<ActionResult<JsonElement?>> CreateHostedKycUrl(
        [FromBody] SumSubAccessTokenRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var validationError = ValidateSumSubRequiredFields(request);
        if (validationError is not null)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(validationError));
        }

        var result = await _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object>
            {
                Method = HttpMethod.Post,
                UpstreamPath = $"/api/v2/users/{Segment(userId)}/sumsub/kyc-url",
                Request = CreateSumSubRequestWithIpAddress(request, GetClientIpAddress()),
                FailureCode = "mobile.kyc.hosted_url.failed",
                FailureMessage = "We could not create hosted KYC URL."
            },
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpPost("resume")]
    public async Task<ActionResult<JsonElement?>> ResumeVerification(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
            return MissingIdentity<JsonElement?>();

        var status = await _proxyHoppa.ExecuteAsync(new ProxyHoppaRequestCommand<object?>
        {
            Method = HttpMethod.Get,
            UpstreamPath = $"/api/v2/users/{Segment(userId)}/kyc/detailed-status",
            FailureCode = "mobile.kyc.status.failed",
            FailureMessage = "We could not load your verification status."
        }, cancellationToken);
        if (!status.IsSuccess)
            return ToActionResult(status);

        if (!HasPendingDocumentReset(status.Value))
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.kyc.reset_not_pending",
                "No document upload is currently requested. Refresh your verification status.",
                (int)HttpStatusCode.Conflict)));

        // Hoppa reuses the reset applicant and retains the stored onboarding answers.
        var result = await _proxyHoppa.ExecuteAsync(new ProxyHoppaRequestCommand<object>
        {
            Method = HttpMethod.Post,
            UpstreamPath = $"/api/v2/users/{Segment(userId)}/sumsub/kyc-url",
            Request = new { },
            FailureCode = "mobile.kyc.resume.failed",
            FailureMessage = "We could not reopen verification. Please try again."
        }, cancellationToken);
        return ToActionResult(result);
    }

    private static bool HasPendingDocumentReset(JsonElement? payload)
    {
        if (payload is not { ValueKind: JsonValueKind.Object } root)
            return false;
        foreach (var provider in root.EnumerateObject())
        {
            if (!string.Equals(provider.Name, "Interlace", StringComparison.OrdinalIgnoreCase) ||
                provider.Value.ValueKind != JsonValueKind.Object)
                continue;
            foreach (var field in provider.Value.EnumerateObject())
                if (string.Equals(field.Name, "RequiredAction", StringComparison.OrdinalIgnoreCase) &&
                    field.Value.ValueKind == JsonValueKind.String)
                    return string.Equals(field.Value.GetString(), "RESUBMIT_DOCUMENTS", StringComparison.OrdinalIgnoreCase);
        }
        return false;
    }

    [HttpPost("verify")]
    public async Task<ActionResult<JsonElement?>> Verify(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var result = await _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<JsonElement>
            {
                Method = HttpMethod.Post,
                UpstreamPath = $"/api/v2/users/{Segment(userId)}/kyc/verify",
                Request = request,
                FailureCode = "mobile.kyc.verify.failed",
                FailureMessage = "We could not verify KYC."
            },
            cancellationToken);

        return ToActionResult(result);
    }

    private static ApplicationError? ValidateSumSubRequiredFields(SumSubAccessTokenRequestDto? request)
    {
        if (request is null ||
            string.IsNullOrWhiteSpace(request.Occupation) ||
            string.IsNullOrWhiteSpace(request.AnnualSalary) ||
            string.IsNullOrWhiteSpace(request.AccountPurpose) ||
            string.IsNullOrWhiteSpace(request.ExpectedMonthlyVolume) ||
            request.DocumentIssueDate is null)
        {
            return new ApplicationError(
                "mobile.kyc.sumsub.required_fields",
                "Occupation, annualSalary, accountPurpose, expectedMonthlyVolume, and documentIssueDate are required.",
                StatusCodes.Status400BadRequest);
        }

        return null;
    }

    private static ApplicationError? ValidateEqualsMoneyDocument(EqualsMoneyAdditionalDocumentFormDto request)
    {
        var errors = new Dictionary<string, string[]>();
        var files = request.GetFiles();
        if (files.Count == 0)
        {
            errors[nameof(request.Files)] = ["At least one document file is required."];
        }
        else if (files.Count > 10 || files.Any(file => file.Length == 0))
        {
            errors[nameof(request.Files)] = ["Upload between 1 and 10 non-empty document files."];
        }

        if (string.IsNullOrWhiteSpace(request.Type))
        {
            errors[nameof(request.Type)] = ["Document type is required."];
        }

        return errors.Count == 0
            ? null
            : new ApplicationError(
                "mobile.kyc.equalsmoney_document.required_fields",
                "EqualsMoney document upload is missing required fields.",
                StatusCodes.Status400BadRequest,
                validationErrors: errors);
    }

    private static MultipartFormDataContent BuildEqualsMoneyDocumentForm(
        EqualsMoneyAdditionalDocumentFormDto request,
        EqualsMoneyDocumentFormShape shape)
    {
        var form = new MultipartFormDataContent();
        form.Add(
            new StringContent(request.Type!.Trim()),
            shape == EqualsMoneyDocumentFormShape.PublicApi ? "Type" : "purpose");
        if (!string.IsNullOrWhiteSpace(request.AssociatedPersonId))
        {
            form.Add(
                new StringContent(request.AssociatedPersonId.Trim()),
                shape == EqualsMoneyDocumentFormShape.PublicApi ? "AssociatedPersonId" : "associatedPersonId");
        }

        if (shape == EqualsMoneyDocumentFormShape.Legacy && !string.IsNullOrWhiteSpace(request.ApplicationId))
        {
            form.Add(
                new StringContent(request.ApplicationId.Trim()),
                "applicationId");
        }

        foreach (var file in request.GetFiles())
        {
            var content = new StreamContent(file.OpenReadStream());
            var contentType = NormalizeDocumentContentType(file);
            if (!string.IsNullOrWhiteSpace(contentType))
            {
                content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue(contentType);
            }

            form.Add(
                content,
                shape == EqualsMoneyDocumentFormShape.PublicApi ? "Files" : "file",
                file.FileName);
        }

        return form;
    }

    private static string? NormalizeDocumentContentType(IFormFile file)
    {
        if (!string.IsNullOrWhiteSpace(file.ContentType) &&
            !string.Equals(file.ContentType, "application/octet-stream", StringComparison.OrdinalIgnoreCase))
        {
            return file.ContentType;
        }

        return Path.GetExtension(file.FileName).ToLowerInvariant() switch
        {
            ".jpg" or ".jpeg" => "image/jpeg",
            ".png" => "image/png",
            ".pdf" => "application/pdf",
            _ => file.ContentType
        };
    }

    private static bool IsRetriableEqualsMoneyDocumentUploadFailure(int? statusCode)
    {
        return statusCode is null ||
            statusCode == (int)HttpStatusCode.BadRequest ||
            statusCode >= (int)HttpStatusCode.InternalServerError;
    }

    private static object CreateSumSubRequestWithIpAddress(SumSubAccessTokenRequestDto request, string? ipAddress)
    {
        return new
        {
            request.Occupation,
            request.AnnualSalary,
            request.AccountPurpose,
            request.ExpectedMonthlyVolume,
            request.DocumentIssueDate,
            IpAddress = ipAddress
        };
    }
}

public sealed class EqualsMoneyAdditionalDocumentFormDto
{
    public IFormFile? File { get; init; }

    public List<IFormFile> Files { get; init; } = [];

    public string? Type { get; init; }

    public string? ApplicationId { get; init; }

    public string? AssociatedPersonId { get; init; }

    public IReadOnlyList<IFormFile> GetFiles()
    {
        return Files.Count > 0
            ? Files
            : File is null
                ? []
                : [File];
    }
}

public sealed class EqualsMoneyAdditionalInformationDto
{
    public string? Type { get; init; }

    public string? Response { get; init; }

    public string? AssociatedPersonId { get; init; }
}

enum EqualsMoneyDocumentFormShape
{
    PublicApi,
    Legacy
}
