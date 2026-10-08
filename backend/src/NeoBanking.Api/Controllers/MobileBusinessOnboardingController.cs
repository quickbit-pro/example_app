using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Onboarding;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/business-onboarding")]
public sealed class MobileBusinessOnboardingController : ApiControllerBase, IActionFilter
{
    private readonly IProxyHoppaRequestUseCase _proxyHoppa;
    private readonly NeoBankingDbContext _dbContext;
    private readonly CompanyOptions _companyOptions;

    public MobileBusinessOnboardingController(
        IProxyHoppaRequestUseCase proxyHoppa,
        NeoBankingDbContext dbContext,
        IOptions<CompanyOptions> companyOptions)
    {
        _proxyHoppa = proxyHoppa;
        _dbContext = dbContext;
        _companyOptions = companyOptions.Value;
    }

    /// <summary>Business onboarding is hidden entirely on personal-only installations.</summary>
    public void OnActionExecuting(ActionExecutingContext context)
    {
        if (!_companyOptions.Features.BusinessOnboardingEnabled)
        {
            context.Result = NotFound();
        }
    }

    public void OnActionExecuted(ActionExecutedContext context)
    {
    }

    [HttpGet("status")]
    [HttpGet("application")]
    public async Task<ActionResult<JsonElement?>> GetStatus(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendBusinessRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "application",
            null,
            "mobile.kyb.status.failed",
            "We could not load business onboarding status.",
            cancellationToken));
    }

    [HttpGet("compliance")]
    public async Task<ActionResult<JsonElement?>> GetCompliance(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId)) return MissingIdentity<JsonElement?>();
        return ToActionResult(await SendBusinessRequestAsync<object?>(userId, HttpMethod.Get, "compliance", null,
            "mobile.kyb.compliance.failed", "We could not load due diligence progress.", cancellationToken));
    }

    [HttpPost("compliance")]
    [HttpPost("compliance/draft")]
    [HttpPost("compliance/requirements")]
    public async Task<ActionResult<JsonElement?>> SaveCompliance([FromBody] JsonElement request, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId)) return MissingIdentity<JsonElement?>();
        var path = Request.Path.Value!.EndsWith("/requirements") ? "compliance/requirements"
            : Request.Path.Value.EndsWith("/draft") ? "compliance/draft" : "compliance";
        return ToActionResult(await SendBusinessRequestAsync(userId, HttpMethod.Post, path, request,
            "mobile.kyb.compliance.failed", "Review the due diligence checklist.", cancellationToken));
    }

    [HttpGet("options")]
    public async Task<ActionResult<JsonElement?>> GetOptions(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendBusinessRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "options",
            null,
            "mobile.kyb.options.failed",
            "We could not load business onboarding options.",
            cancellationToken));
    }

    [HttpPost("start")]
    [HttpPost("application")]
    public async Task<ActionResult<JsonElement?>> Start(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendBusinessRequestAsync(
            userId,
            HttpMethod.Post,
            "application",
            request,
            "mobile.kyb.start.failed",
            "We could not start business onboarding.",
            cancellationToken));
    }

    [HttpPatch("profile")]
    public async Task<ActionResult<JsonElement?>> UpdateProfile(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendBusinessRequestAsync(
            userId,
            HttpMethod.Post,
            "application",
            request,
            "mobile.kyb.profile.update.failed",
            "We could not update business profile.",
            cancellationToken));
    }

    [HttpGet("associated-people")]
    public async Task<ActionResult<JsonElement?>> ListAssociatedPeople(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendBusinessRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "associated-people",
            null,
            "mobile.kyb.associated_people.list.failed",
            "We could not list associated people.",
            cancellationToken));
    }

    [HttpPost("beneficial-owners")]
    [HttpPost("associated-people")]
    public async Task<ActionResult<JsonElement?>> UpsertBeneficialOwner(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendBusinessRequestAsync(
            userId,
            HttpMethod.Post,
            "associated-people",
            request,
            "mobile.kyb.beneficial_owners.upsert.failed",
            "We could not upsert beneficial owner.",
            cancellationToken));
    }

    [HttpPost("documents")]
    [HttpPost("application/documents")]
    public async Task<ActionResult<JsonElement?>> SubmitDocument(
        [FromForm] BusinessOnboardingDocumentFormDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        using var form = BuildDocumentForm(request);

        return ToActionResult(await SendBusinessRequestAsync(
            userId,
            HttpMethod.Post,
            "application/documents",
            form,
            "mobile.kyb.documents.submit.failed",
            "We could not submit business document.",
            cancellationToken));
    }

    [HttpPost("submit")]
    [HttpPost("application/submit")]
    public async Task<ActionResult<JsonElement?>> SubmitApplication(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendBusinessRequestAsync<object?>(
            userId,
            HttpMethod.Post,
            "application/submit",
            null,
            "mobile.kyb.submit.failed",
            "We could not submit business onboarding application.",
            cancellationToken));
    }

    [HttpPost("associated-people/{associatedPersonId}/documents")]
    public async Task<ActionResult<JsonElement?>> SubmitAssociatedPersonDocument(
        string associatedPersonId,
        [FromForm] BusinessOnboardingDocumentFormDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        using var form = BuildDocumentForm(request);

        return ToActionResult(await SendBusinessRequestAsync(
            userId,
            HttpMethod.Post,
            $"associated-people/{Segment(associatedPersonId)}/documents",
            form,
            "mobile.kyb.associated_people.documents.submit.failed",
            "We could not submit associated person document.",
            cancellationToken));
    }

    private async Task<ApplicationResult<JsonElement?>> SendBusinessRequestAsync<TRequest>(
        string userId,
        HttpMethod method,
        string relativePath,
        TRequest? request,
        string failureCode,
        string failureMessage,
        CancellationToken cancellationToken)
    {
        var accountType = await GetLocalAccountTypeAsync(cancellationToken);
        if (accountType != "business")
        {
            return ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.kyb.personal_account",
                "Business onboarding is only available for business accounts.",
                StatusCodes.Status403Forbidden));
        }

        var result = await _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<TRequest>
            {
                Method = method,
                UpstreamPath = $"/api/v2/business/onboarding/{relativePath}",
                Query = new Dictionary<string, string?>
                {
                    ["userId"] = userId
                },
                Request = request,
                FailureCode = failureCode,
                FailureMessage = failureMessage
            },
            cancellationToken);
        if (!result.IsSuccess && result.Error?.Detail is { } detail)
        {
            try
            {
                using var document = JsonDocument.Parse(detail);
                var root = document.RootElement;
                if (root.ValueKind != JsonValueKind.Object) return result;
                if (root.TryGetProperty("errors", out var errors) && errors.ValueKind == JsonValueKind.Array)
                {
                    var messages = errors.EnumerateArray().Where(e => e.ValueKind == JsonValueKind.String).Select(e => e.GetString()!).ToArray();
                    if (messages.Length > 0) return ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                        root.TryGetProperty("code", out var code) ? code.GetString() ?? failureCode : failureCode,
                        "Review the business onboarding details.", result.Error.StatusCode, string.Join("\n", messages),
                        new Dictionary<string, string[]> { ["compliance"] = messages }));
                }
                if (root.TryGetProperty("message", out var message) && message.ValueKind == JsonValueKind.String)
                    return ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                        root.TryGetProperty("code", out var code) ? code.GetString() ?? failureCode : failureCode,
                        message.GetString()!, result.Error.StatusCode, message.GetString()));
            }
            catch (JsonException) { }
        }
        return result;
    }

    private async Task<string> GetLocalAccountTypeAsync(CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var parsedUserId))
        {
            return "personal";
        }

        var metadataJson = await _dbContext.Users
            .AsNoTracking()
            .Where(user => user.Id == parsedUserId)
            .Select(user => user.MetadataJson)
            .SingleOrDefaultAsync(cancellationToken);

        var localAccountType = GetAccountType(metadataJson);
        var liveAccountType = await GetLiveHoppaAccountTypeAsync(cancellationToken);

        return liveAccountType ?? localAccountType;
    }

    private async Task<string?> GetLiveHoppaAccountTypeAsync(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var hoppaUserId))
        {
            return null;
        }

        var result = await _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object?>
            {
                Method = HttpMethod.Get,
                UpstreamPath = $"/api/v2/users/{Segment(hoppaUserId)}",
                FailureCode = "mobile.kyb.user.failed",
                FailureMessage = "We could not load user account type."
            },
            cancellationToken);

        if (!result.IsSuccess || result.Value is null)
        {
            return null;
        }

        return GetAccountTypeFromPayload(result.Value.Value);
    }

    private static string GetAccountType(string? metadataJson)
    {
        if (string.IsNullOrWhiteSpace(metadataJson))
        {
            return "personal";
        }

        try
        {
            using var document = JsonDocument.Parse(metadataJson);
            if (document.RootElement.TryGetProperty("accountType", out var value) &&
                value.ValueKind == JsonValueKind.String)
            {
                return NormalizeAccountType(value.GetString());
            }
        }
        catch (JsonException)
        {
            return "personal";
        }

        return "personal";
    }

    private static string? GetAccountTypeFromPayload(JsonElement payload)
    {
        var userPayload = UnwrapPayload(payload);
        var accountType = GetString(userPayload, "AccountType", "accountType");

        return string.IsNullOrWhiteSpace(accountType) ? null : NormalizeAccountType(accountType);
    }

    private static JsonElement UnwrapPayload(JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object)
        {
            return payload;
        }

        foreach (var propertyName in new[] { "Data", "data", "User", "user" })
        {
            if (payload.TryGetProperty(propertyName, out var nested) &&
                nested.ValueKind == JsonValueKind.Object)
            {
                return nested;
            }
        }

        return payload;
    }

    private static string? GetString(JsonElement payload, params string[] propertyNames)
    {
        foreach (var propertyName in propertyNames)
        {
            if (payload.ValueKind == JsonValueKind.Object &&
                payload.TryGetProperty(propertyName, out var property) &&
                property.ValueKind == JsonValueKind.String)
            {
                return property.GetString();
            }
        }

        return null;
    }

    private static string NormalizeAccountType(string? accountType)
    {
        return string.Equals(accountType?.Trim(), "business", StringComparison.OrdinalIgnoreCase)
            ? "business"
            : "personal";
    }

    private static MultipartFormDataContent BuildDocumentForm(BusinessOnboardingDocumentFormDto request)
    {
        var form = new MultipartFormDataContent();
        if (!string.IsNullOrWhiteSpace(request.Purpose))
        {
            form.Add(new StringContent(request.Purpose), "Purpose");
        }

        if (request.File is not null)
        {
            var content = new StreamContent(request.File.OpenReadStream());
            if (!string.IsNullOrWhiteSpace(request.File.ContentType))
            {
                content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue(request.File.ContentType);
            }

            form.Add(content, "File", request.File.FileName);
        }

        return form;
    }
}

public sealed class BusinessOnboardingDocumentFormDto
{
    public IFormFile? File { get; init; }

    public string? Purpose { get; init; }
}
