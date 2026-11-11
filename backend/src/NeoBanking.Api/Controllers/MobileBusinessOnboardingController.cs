using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Application.Common;
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
    [HttpGet("workflow")]
    public Task<ActionResult<JsonElement?>> GetWorkflow(CancellationToken cancellationToken) =>
        ForwardWorkflowAsync<object?>(HttpMethod.Get, "/api/v2/business-onboarding", null, cancellationToken);

    [HttpPost("workflow/tier")]
    public Task<ActionResult<JsonElement?>> SelectTier([FromBody] BusinessTierRequest request, CancellationToken cancellationToken) =>
        ForwardWorkflowAsync(HttpMethod.Post, "/api/v2/business-onboarding/tier", request, cancellationToken);

    [HttpPost("workflow/payments/{paymentId:guid}/checkout")]
    public Task<ActionResult<JsonElement?>> Checkout(Guid paymentId, [FromBody] BusinessCheckoutRequest request, CancellationToken cancellationToken) =>
        ForwardWorkflowAsync(HttpMethod.Post, $"/api/v2/business-onboarding/payments/{paymentId:D}/checkout", request, cancellationToken);

    [HttpPost("workflow/draft")]
    public Task<ActionResult<JsonElement?>> SaveDraft([FromBody] JsonElement request, CancellationToken cancellationToken) =>
        ForwardWorkflowAsync(HttpMethod.Post, "/api/v2/dashboard/kyb/submit", request, cancellationToken);

    public sealed record BusinessTierRequest(int TierId);
    public sealed record BusinessCheckoutRequest(bool TermsAccepted);

    [HttpGet("application")]
    public async Task<ActionResult<JsonElement?>> GetApplication(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendBusinessRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "/api/v2/business/onboarding/application",
            null,
            "mobile.kyb.status.failed",
            "We could not load business onboarding status.",
            cancellationToken));
    }

    [HttpGet("compliance")]
    public async Task<ActionResult<JsonElement?>> GetCompliance(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId)) return MissingIdentity<JsonElement?>();
        return ToActionResult(await SendBusinessRequestAsync<object?>(userId, HttpMethod.Get, "/api/v2/business/onboarding/compliance", null,
            "mobile.kyb.compliance.failed", "We could not load due diligence progress.", cancellationToken));
    }

    [HttpPost("compliance")]
    [HttpPost("compliance/draft")]
    [HttpPost("compliance/requirements")]
    public async Task<ActionResult<JsonElement?>> SaveCompliance([FromBody] JsonElement request, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId)) return MissingIdentity<JsonElement?>();
        var requestedPath = Request.Path.Value?.TrimEnd('/') ?? "";
        var path = requestedPath.EndsWith("/requirements", StringComparison.OrdinalIgnoreCase)
            ? "/api/v2/business/onboarding/compliance/requirements"
            : requestedPath.EndsWith("/draft", StringComparison.OrdinalIgnoreCase)
                ? "/api/v2/business/onboarding/compliance/draft"
                : "/api/v2/business/onboarding/compliance";
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
            "/api/v2/business/onboarding/options",
            null,
            "mobile.kyb.options.failed",
            "We could not load business onboarding options.",
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
            "/api/v2/business/onboarding/associated-people",
            null,
            "mobile.kyb.associated_people.list.failed",
            "We could not list associated people.",
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
            "/api/v2/dashboard/kyb/documents",
            form,
            "mobile.kyb.documents.submit.failed",
            "We could not submit business document.",
            cancellationToken));
    }

    [HttpPost("submit")]
    [HttpPost("application/submit")]
    [HttpPost("workflow/assess")]
    public async Task<ActionResult<JsonElement?>> SubmitApplication(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var result = await SendBusinessRequestAsync<object?>(
            userId,
            HttpMethod.Post,
            "/api/v2/business-onboarding/assess",
            null,
            "mobile.kyb.submit.failed",
            "We could not request assessment for your business application.",
            cancellationToken);
        return result.IsSuccess ? Accepted(value: result.Value) : ToActionResult(result);
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
        form.Add(new StringContent(associatedPersonId), "AssociatedPersonId");

        return ToActionResult(await SendBusinessRequestAsync(
            userId,
            HttpMethod.Post,
            "/api/v2/dashboard/kyb/documents",
            form,
            "mobile.kyb.associated_people.documents.submit.failed",
            "We could not submit associated person document.",
            cancellationToken));
    }

    private async Task<ActionResult<JsonElement?>> ForwardWorkflowAsync<TRequest>(
        HttpMethod method,
        string upstreamPath,
        TRequest? request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId)) return MissingIdentity<JsonElement?>();
        return ToActionResult(await SendBusinessRequestAsync(userId, method, upstreamPath, request,
            "mobile.kyb.workflow.failed", "We could not continue business onboarding.", cancellationToken));
    }

    private async Task<ApplicationResult<JsonElement?>> SendBusinessRequestAsync<TRequest>(
        string userId,
        HttpMethod method,
        string upstreamPath,
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
                UpstreamPath = upstreamPath,
                Query = Query(("userId", userId)),
                Request = request,
                SuppressPayloadLogging = true,
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
                var code = GetString(root, "code", "Code", "error") ?? failureCode;
                var message = GetString(root, "message", "Message");
                if ((root.TryGetProperty("errors", out var errors) || root.TryGetProperty("Errors", out errors)) &&
                    errors.ValueKind == JsonValueKind.Array)
                {
                    var messages = errors.EnumerateArray().Where(e => e.ValueKind == JsonValueKind.String).Select(e => e.GetString()!).ToArray();
                    if (messages.Length > 0) return ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                        code, message ?? "Review the business onboarding details.", result.Error.StatusCode, string.Join("\n", messages),
                        new Dictionary<string, string[]> { ["compliance"] = messages }));
                }
                if (message is not null)
                    return ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                        code, message, result.Error.StatusCode, message));
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
                SuppressPayloadLogging = true,
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
