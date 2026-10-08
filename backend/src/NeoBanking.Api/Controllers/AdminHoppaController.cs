using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.Common;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/hoppa")]
public sealed class AdminHoppaController : HoppaProxyControllerBase
{
    private readonly NeoBankingDbContext _dbContext;

    public AdminHoppaController(
        IProxyHoppaRequestUseCase proxyHoppa,
        NeoBankingDbContext dbContext)
        : base(proxyHoppa)
    {
        _dbContext = dbContext;
    }

    [HttpGet]
    [HttpGet("{**path}")]
    public Task<ActionResult<JsonElement?>> Get(string? path, CancellationToken cancellationToken)
    {
        return ProxyAsync(HttpMethod.Get, path, null, cancellationToken);
    }

    [HttpPost]
    [HttpPost("{**path}")]
    public Task<ActionResult<JsonElement?>> Post(
        string? path,
        [FromBody] JsonElement? request,
        CancellationToken cancellationToken)
    {
        return ProxyAsync(HttpMethod.Post, path, request, cancellationToken);
    }

    [HttpPut]
    [HttpPut("{**path}")]
    public Task<ActionResult<JsonElement?>> Put(
        string? path,
        [FromBody] JsonElement? request,
        CancellationToken cancellationToken)
    {
        return ProxyAsync(HttpMethod.Put, path, request, cancellationToken);
    }

    [HttpPatch]
    [HttpPatch("{**path}")]
    public Task<ActionResult<JsonElement?>> Patch(
        string? path,
        [FromBody] JsonElement? request,
        CancellationToken cancellationToken)
    {
        return ProxyAsync(HttpMethod.Patch, path, request, cancellationToken);
    }

    [HttpDelete]
    [HttpDelete("{**path}")]
    public Task<ActionResult<JsonElement?>> Delete(
        string? path,
        [FromBody] JsonElement? request,
        CancellationToken cancellationToken)
    {
        return ProxyAsync(HttpMethod.Delete, path, request, cancellationToken);
    }

    private async Task<ActionResult<JsonElement?>> ProxyAsync(
        HttpMethod method,
        string? path,
        JsonElement? request,
        CancellationToken cancellationToken)
    {
        var query = QueryFromRequest(Request.Query);
        var upstreamQueryResult = await ResolveAndCleanUserScopedQueryAsync(path, query, cancellationToken);
        if (!upstreamQueryResult.IsSuccess)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(upstreamQueryResult.Error!));
        }

        var upstreamQuery = upstreamQueryResult.Value!;
        var userScopedPathResult = await ResolveDirectUserScopedPathAsync(path, cancellationToken);
        if (!userScopedPathResult.IsSuccess)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(userScopedPathResult.Error!));
        }

        var userResolvedPath = userScopedPathResult.Value ?? path;
        var resolvedPathResult = await ResolveCaseScopedPathAsync(userResolvedPath, cancellationToken);
        if (!resolvedPathResult.IsSuccess)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(resolvedPathResult.Error!));
        }

        var resolvedPath = resolvedPathResult.Value ?? userResolvedPath;
        var upstreamPath = MapAdminHoppaPath(resolvedPath, upstreamQuery);
        var upstreamMethod = MapAdminHoppaMethod(method, path);
        var operationError = ValidateMappedOperation(upstreamMethod, upstreamPath);
        if (operationError is not null)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(operationError));
        }

        var forwardedQuery = upstreamQuery
            .Where(pair => !string.Equals(pair.Key, "__hoppaUserId", StringComparison.Ordinal))
            .ToDictionary(pair => pair.Key, pair => pair.Value);

        return ToActionResult(await SendHoppaAsync(
            upstreamMethod,
            upstreamPath,
            request,
            "admin.hoppa.proxy.failed",
            "Hoppa admin proxy request failed.",
            cancellationToken,
            forwardedQuery));
    }

    private async Task<ApplicationResult<IReadOnlyDictionary<string, string?>>> ResolveAndCleanUserScopedQueryAsync(
        string? path,
        IReadOnlyDictionary<string, string?> query,
        CancellationToken cancellationToken)
    {
        if (!PathConsumesUserId(path) || !TryGetQueryUserId(query, out var rawUserId))
        {
            return ApplicationResult<IReadOnlyDictionary<string, string?>>.Success(query);
        }

        var resolvedUserId = await ResolveHoppaUserIdAsync(rawUserId, cancellationToken);
        if (!resolvedUserId.IsSuccess)
        {
            return ApplicationResult<IReadOnlyDictionary<string, string?>>.Failure(resolvedUserId.Error!);
        }

        var cleanedQuery = query
            .Where(pair => !string.Equals(pair.Key, "userId", StringComparison.Ordinal) &&
                           !string.Equals(pair.Key, "UserId", StringComparison.Ordinal))
            .ToDictionary(pair => pair.Key, pair => pair.Value);

        cleanedQuery["__hoppaUserId"] = resolvedUserId.Value;

        return ApplicationResult<IReadOnlyDictionary<string, string?>>.Success(cleanedQuery);
    }

    private async Task<ApplicationResult<string>> ResolveHoppaUserIdAsync(
        string rawUserId,
        CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return ApplicationResult<string>.Failure(new ApplicationError(
                "admin.company_context.missing",
                "Sign in again to continue.",
                StatusCodes.Status401Unauthorized));
        }

        var trimmedUserId = rawUserId.Trim();
        if (int.TryParse(trimmedUserId, out var numericUserId) && numericUserId > 0)
        {
            return ApplicationResult<string>.Success(trimmedUserId);
        }

        if (!Guid.TryParse(trimmedUserId, out var localUserId))
        {
            return ApplicationResult<string>.Failure(new ApplicationError(
                "admin.hoppa.user_id.invalid",
                "Enter a numeric Hoppa user ID, or a local user UUID that has a Hoppa mapping.",
                StatusCodes.Status400BadRequest));
        }

        var mappedUserId = await _dbContext.ProviderMappings
            .AsNoTracking()
            .Where(mapping => mapping.CompanyInstallationId == companyId &&
                              mapping.Provider == "hoppa" &&
                              mapping.ProviderEntityType == "user" &&
                              mapping.InternalEntityType == "user" &&
                              mapping.InternalEntityId == localUserId)
            .OrderByDescending(mapping => mapping.UpdatedAt)
            .Select(mapping => mapping.ProviderEntityId)
            .FirstOrDefaultAsync(cancellationToken);

        if (string.IsNullOrWhiteSpace(mappedUserId))
        {
            return ApplicationResult<string>.Failure(new ApplicationError(
                "admin.hoppa.user_id.mapping_missing",
                "No Hoppa user mapping exists for this local user UUID.",
                StatusCodes.Status404NotFound));
        }

        if (!int.TryParse(mappedUserId, out var mappedNumericUserId) || mappedNumericUserId <= 0)
        {
            return ApplicationResult<string>.Failure(new ApplicationError(
                "admin.hoppa.user_id.mapping_invalid",
                "The local user mapping does not contain a numeric Hoppa user ID.",
                StatusCodes.Status409Conflict));
        }

        return ApplicationResult<string>.Success(mappedUserId);
    }

    private async Task<ApplicationResult<string?>> ResolveDirectUserScopedPathAsync(
        string? path,
        CancellationToken cancellationToken)
    {
        var normalizedPath = (path ?? string.Empty).Trim('/');
        var segments = normalizedPath
            .Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        if (segments is not ["users", var rawUserId, var resource, .. var tail] ||
            resource is not ("wallets" or "assets" or "crypto-addresses" or "kyc" or "tier"))
        {
            return ApplicationResult<string?>.Success(null);
        }

        var resolvedUserId = await ResolveHoppaUserIdAsync(rawUserId, cancellationToken);
        if (!resolvedUserId.IsSuccess)
        {
            return ApplicationResult<string?>.Failure(resolvedUserId.Error!);
        }

        var resolvedSegments = new[] { "users", resolvedUserId.Value!, resource }.Concat(tail);
        return ApplicationResult<string?>.Success(Join(resolvedSegments));
    }

    private async Task<ApplicationResult<string?>> ResolveCaseScopedPathAsync(
        string? path,
        CancellationToken cancellationToken)
    {
        var normalizedPath = (path ?? string.Empty).Trim('/');
        var segments = normalizedPath
            .Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        if (segments is not ["kyc-kyb", "cases", var caseId, .. var tail])
        {
            return ApplicationResult<string?>.Success(null);
        }

        if (tail is ["request", ..] or ["reject", ..])
        {
            return ApplicationResult<string?>.Failure(new ApplicationError(
                "admin.hoppa.kyc_case_action.unsupported",
                "This KYC/KYB case action is not mapped to a supported Hoppa public API endpoint.",
                StatusCodes.Status501NotImplemented,
                "Use a backend-supported public Hoppa API action, or add a typed backend endpoint once the upstream contract is confirmed."));
        }

        if (tail.Length > 0 && tail is not ["approve"] && tail is not ["status"] && tail is not ["details"])
        {
            return ApplicationResult<string?>.Success(null);
        }

        var resolvedHoppaUserId = await ResolveCaseHoppaUserIdAsync(caseId, cancellationToken);
        if (!resolvedHoppaUserId.IsSuccess)
        {
            return ApplicationResult<string?>.Failure(resolvedHoppaUserId.Error!);
        }

        var actionTail = tail is ["approve"] ? "/approve" : string.Empty;
        return ApplicationResult<string?>.Success($"kyc-kyb/cases/{resolvedHoppaUserId.Value}{actionTail}");
    }

    private async Task<ApplicationResult<string>> ResolveCaseHoppaUserIdAsync(
        string rawCaseId,
        CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return ApplicationResult<string>.Failure(new ApplicationError(
                "admin.company_context.missing",
                "Sign in again to continue.",
                StatusCodes.Status401Unauthorized));
        }

        var trimmedCaseId = rawCaseId.Trim();
        if (int.TryParse(trimmedCaseId, out var numericUserId) && numericUserId > 0)
        {
            return ApplicationResult<string>.Success(trimmedCaseId);
        }

        if (!Guid.TryParse(trimmedCaseId, out var caseGuid))
        {
            return ApplicationResult<string>.Failure(new ApplicationError(
                "admin.hoppa.kyc_case_id.invalid",
                "Enter a numeric Hoppa user ID, local user UUID, or local KYC/KYB case UUID.",
                StatusCodes.Status400BadRequest));
        }

        var kycUserId = await _dbContext.KycVerifications
            .AsNoTracking()
            .Where(kyc => kyc.CompanyInstallationId == companyId && kyc.Id == caseGuid)
            .Select(kyc => (Guid?)kyc.UserId)
            .FirstOrDefaultAsync(cancellationToken);

        var kybUserId = kycUserId is null
            ? await _dbContext.KybVerifications
                .AsNoTracking()
                .Where(kyb => kyb.CompanyInstallationId == companyId && kyb.Id == caseGuid)
                .Select(kyb => kyb.OnboardingApplication != null
                    ? kyb.OnboardingApplication.ApplicantUserId
                    : null)
                .FirstOrDefaultAsync(cancellationToken)
            : null;

        var localUserId = kycUserId ?? kybUserId ?? caseGuid;
        return await ResolveHoppaUserIdAsync(localUserId.ToString(), cancellationToken);
    }

    private static string MapAdminHoppaPath(string? path, IReadOnlyDictionary<string, string?> query)
    {
        var normalizedPath = (path ?? string.Empty).Trim('/');
        if (string.IsNullOrWhiteSpace(normalizedPath))
        {
            return "/api/v2/users";
        }

        var segments = normalizedPath
            .Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        return segments switch
        {
            ["support", "messages", "report-transaction"] => "/api/v2/admin/support/messages/report-transaction",
            ["support", "reported-transactions", ..] => "/api/v2/admin/support/messages/report-transaction",
            ["business-onboarding", "applications"] => "/api/v2/business/onboarding/application",
            ["business-onboarding", "applications", _, "submit"] => "/api/v2/business/onboarding/application/submit",
            ["business-onboarding", "applications", _, "documents", ..] => "/api/v2/business/onboarding/application/documents",
            ["business-onboarding", .. var tail] => $"/api/v2/business/onboarding/{Join(tail)}",
            ["kyc-kyb", "cases"] => "/api/v2/users",
            ["kyc-kyb", "cases", var caseId, "approve"] => $"/api/v2/users/{Segment(caseId)}/kyc/verify",
            ["kyc-kyb", "cases", var caseId, ..] => $"/api/v2/users/{Segment(caseId)}/kyc/detailed-status",
            ["banking", "budgets", var budgetId, "transfer"] => $"/api/v2/banking/budgets/{Segment(budgetId)}/transfer",
            ["banking", "budgets"] when TryGetQueryUserId(query, out var userId) => $"/api/v2/banking/users/{Segment(userId)}/budgets",
            ["banking", "budgets", .. var tail] when TryGetQueryUserId(query, out var userId) => $"/api/v2/banking/users/{Segment(userId)}/budgets{OptionalTail(tail)}",
            ["banking", "balances", ..] => "/api/v2/banking/balance",
            ["banking", "transfers"] => "/api/v2/transfers",
            ["banking", "transfers", var transferId] => $"/api/v2/transfers/{Segment(transferId)}",
            ["banking", .. var tail] => $"/api/v2/banking/{Join(tail)}",
            ["tiers", "card-tiers", var cardTierId, ..] => $"/api/v2/tiers/card-tier/{Segment(cardTierId)}",
            ["tiers", "card-tiers"] => "/api/v2/tiers",
            ["tiers", .. var tail] => $"/api/v2/tiers{OptionalTail(tail)}",
            ["cards", "transactions"] => "/api/v2/transactions",
            ["cards", var cardId, "transactions"] => $"/api/v2/cards/{Segment(cardId)}/transactions",
            ["cards", "widget-secrets"] => "/api/v2/cards",
            ["cards", var cardId, "widget", "secret-data"] => $"/api/v2/cards/{Segment(cardId)}/widget",
            ["cards", var cardId, "widget", ..] => $"/api/v2/cards/{Segment(cardId)}/widget",
            ["cards", .. var tail] => $"/api/v2/cards{OptionalTail(tail)}",
            ["users", "wallets"] when TryGetQueryUserId(query, out var userId) => $"/api/v2/users/{Segment(userId)}/wallets",
            ["users", "assets"] when TryGetQueryUserId(query, out var userId) => $"/api/v2/users/{Segment(userId)}/assets",
            ["users", "crypto-addresses"] when TryGetQueryUserId(query, out var userId) => $"/api/v2/users/{Segment(userId)}/crypto-addresses",
            ["users", "wallets"] => "/api/v2/users",
            ["users", "assets"] => "/api/v2/users",
            ["users", "crypto-addresses"] => "/api/v2/users",
            ["users", var userId, "wallets", var walletId, "top-up"] => "/api/v2/transfers/wallet-topup",
            ["users", var userId, "wallets", .. var tail] => $"/api/v2/users/{Segment(userId)}/wallets{OptionalTail(tail)}",
            ["users", var userId, "assets", .. var tail] => $"/api/v2/users/{Segment(userId)}/assets{OptionalTail(tail)}",
            ["users", var userId, "crypto-addresses", .. var tail] => $"/api/v2/users/{Segment(userId)}/crypto-addresses{OptionalTail(tail)}",
            ["users", var userId, "kyc", "verify"] => $"/api/v2/users/{Segment(userId)}/kyc/verify",
            ["users", var userId, "tier"] => $"/api/v2/users/{Segment(userId)}/tier",
            ["users", .. var tail] => $"/api/v2/users{OptionalTail(tail)}",
            ["payments"] => "/api/v2/payments/requests",
            ["payments", var paymentId] => $"/api/v2/payments/requests/{Segment(paymentId)}",
            ["payments", .. var tail] => $"/api/v2/payments{OptionalTail(tail)}",
            ["withdrawals", "validate"] => "/api/v2/transfers/withdrawals/validate",
            ["withdrawals", var withdrawalId, "validate"] => "/api/v2/transfers/withdrawals/validate",
            ["withdrawals", var withdrawalId, "confirm"] => "/api/v2/transfers/withdrawals/crypto/confirm",
            ["withdrawals", ..] => "/api/v2/transfers/withdrawals/available-balance",
            ["transactions", "sync"] => "/api/v2/transactions/sync",
            ["transactions", "stats", ..] => "/api/v2/transactions/stats",
            ["transactions", "export"] => "/api/v2/transactions/export",
            ["transactions", var transactionId, "sync"] => "/api/v2/transactions/sync",
            ["transactions", var transactionId, "reports"] => "/api/v2/admin/support/messages/report-transaction",
            ["transactions", .. var tail] => $"/api/v2/transactions{OptionalTail(tail)}",
            _ => $"/api/v2/{Join(segments)}"
        };
    }

    private static HttpMethod MapAdminHoppaMethod(HttpMethod method, string? path)
    {
        var normalizedPath = (path ?? string.Empty).Trim('/');
        var segments = normalizedPath
            .Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        return segments switch
        {
            ["withdrawals", "validate"] => HttpMethod.Get,
            ["withdrawals", _, "validate"] => HttpMethod.Get,
            ["transactions", "stats", ..] => HttpMethod.Get,
            _ => method
        };
    }

    private static ApplicationError? ValidateMappedOperation(HttpMethod method, string upstreamPath)
    {
        var segments = upstreamPath.Trim('/')
            .Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        if (segments is ["api", "v2", "admin", ..])
        {
            return new ApplicationError(
                "admin.hoppa.private_route.unsupported",
                "This operation is not part of the public Hoppa API contract.",
                StatusCodes.Status501NotImplemented,
                "Use only routes published in the customer OpenAPI document.");
        }

        if (segments is ["api", "v2", "users", _, "tier"] && method != HttpMethod.Post)
        {
            return new ApplicationError(
                "admin.hoppa.method.unsupported",
                "Hoppa staging OpenAPI only exposes user tier changes as POST.",
                StatusCodes.Status405MethodNotAllowed,
                "Use POST with TierId and optional TierCycle to call /api/v2/users/{userId}/tier.");
        }

        return null;
    }

    private static bool PathConsumesUserId(string? path)
    {
        var normalizedPath = (path ?? string.Empty).Trim('/');
        var segments = normalizedPath
            .Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        return segments switch
        {
            ["banking", "budgets"] => true,
            ["users", "wallets"] => true,
            ["users", "assets"] => true,
            ["users", "crypto-addresses"] => true,
            _ => false
        };
    }

    private static bool TryGetQueryUserId(IReadOnlyDictionary<string, string?> query, out string userId)
    {
        userId = string.Empty;

        foreach (var key in new[] { "__hoppaUserId", "userId", "UserId" })
        {
            if (query.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value))
            {
                userId = value;
                return true;
            }
        }

        return false;
    }

    private static string Join(IEnumerable<string> segments)
    {
        return string.Join('/', segments.Select(Segment));
    }

    private static string OptionalTail(IEnumerable<string> segments)
    {
        var tail = Join(segments);
        return string.IsNullOrWhiteSpace(tail) ? string.Empty : $"/{tail}";
    }
}
