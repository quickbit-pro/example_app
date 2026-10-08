using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Admin;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/users")]
public sealed class AdminUsersController : HoppaProxyControllerBase
{
    private readonly NeoBankingDbContext _dbContext;

    public AdminUsersController(
        IProxyHoppaRequestUseCase proxyHoppa,
        NeoBankingDbContext dbContext)
        : base(proxyHoppa)
    {
        _dbContext = dbContext;
    }

    [HttpGet]
    public async Task<ActionResult<JsonElement?>> ListUsers(
        [FromQuery] string? status,
        [FromQuery] int? limit,
        [FromQuery] string? cursor,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            "users",
            null,
            "admin.users.list.failed",
            "Hoppa failed to list users.",
            cancellationToken,
            Query(("status", status), ("limit", limit), ("cursor", cursor))));
    }

    [HttpGet("summaries")]
    public async Task<ActionResult<AdminUserListResponseDto>> ListUserSummaries(
        [FromQuery] string? status,
        [FromQuery] int? limit,
        [FromQuery] int? offset,
        [FromQuery] string? sortBy,
        [FromQuery] string? sortDir,
        CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var pageSize = ClampLimit(limit);
        var skip = Math.Max(0, offset ?? 0);
        var baseQuery = _dbContext.Users
            .AsNoTracking()
            .Where(user => user.CompanyInstallationId == companyId &&
                           user.AdminProfile == null &&
                           (status == null || user.Status == status));

        var totalCount = await baseQuery.CountAsync(cancellationToken);
        var ordered = ApplyUserSort(baseQuery, sortBy, sortDir);

        var users = await ordered
            .Skip(skip)
            .Take(pageSize)
            .Select(user => new AdminUserProjection(
                user.Id,
                user.Email,
                user.DisplayName,
                user.Status,
                user.CreatedAt,
                user.UpdatedAt,
                user.LastLoginAt))
            .ToListAsync(cancellationToken);

        var summaries = await EnrichUsersAsync(companyId, users, cancellationToken);

        return Ok(new AdminUserListResponseDto
        {
            Items = summaries,
            TotalCount = totalCount
        });
    }

    private static IOrderedQueryable<Domain.Entities.ApplicationUser> ApplyUserSort(
        IQueryable<Domain.Entities.ApplicationUser> query,
        string? sortBy,
        string? sortDir)
    {
        var desc = !string.Equals(sortDir, "asc", StringComparison.OrdinalIgnoreCase);
        return (sortBy?.ToLowerInvariant()) switch
        {
            "email" => desc ? query.OrderByDescending(u => u.Email) : query.OrderBy(u => u.Email),
            "displayname" => desc ? query.OrderByDescending(u => u.DisplayName) : query.OrderBy(u => u.DisplayName),
            "status" => desc ? query.OrderByDescending(u => u.Status) : query.OrderBy(u => u.Status),
            "lastloginat" => desc ? query.OrderByDescending(u => u.LastLoginAt) : query.OrderBy(u => u.LastLoginAt),
            "updatedat" => desc ? query.OrderByDescending(u => u.UpdatedAt) : query.OrderBy(u => u.UpdatedAt),
            _ => desc ? query.OrderByDescending(u => u.CreatedAt) : query.OrderBy(u => u.CreatedAt),
        };
    }

    [HttpGet("search")]
    public async Task<ActionResult<AdminUserListResponseDto>> SearchUsers(
        [FromQuery] string? q,
        [FromQuery] int? limit,
        CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var pageSize = ClampLimit(limit);
        var term = q?.Trim();
        if (string.IsNullOrWhiteSpace(term))
        {
            return await ListUserSummaries(null, pageSize, 0, null, null, cancellationToken);
        }

        return Ok(await SearchUsersCoreAsync(companyId, term, pageSize, cancellationToken));
    }

    [HttpGet("lookup/{lookup}")]
    public async Task<ActionResult<AdminUserSummaryDto>> LookupUser(string lookup, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var term = lookup.Trim();
        if (string.IsNullOrWhiteSpace(term))
        {
            return ToActionResult(ApplicationResult<AdminUserSummaryDto>.Failure(new ApplicationError(
                "admin.users.lookup.invalid",
                "User lookup is required.",
                StatusCodes.Status400BadRequest)));
        }

        var response = await SearchUsersCoreAsync(companyId, term, 1, cancellationToken);
        var summary = response.Items.FirstOrDefault();
        if (summary is null)
        {
            return ToActionResult(ApplicationResult<AdminUserSummaryDto>.Failure(new ApplicationError(
                "admin.users.lookup.not_found",
                "No user matched the supplied local UUID, Hoppa ID, email, or name.",
                StatusCodes.Status404NotFound)));
        }

        return Ok(summary);
    }

    [HttpGet("{userId}")]
    public async Task<ActionResult<JsonElement?>> GetUser(string userId, CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            $"users/{Segment(userId)}",
            null,
            "admin.users.get.failed",
            "Hoppa failed to load user.",
            cancellationToken));
    }

    [HttpPost("{userId}/decisions")]
    public async Task<ActionResult<JsonElement?>> CreateDecision(
        string userId,
        [FromBody] AdminUserDecisionRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = userId;
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "admin.users.decisions.unsupported",
            "Hoppa staging OpenAPI does not expose a user decision endpoint.");
    }

    [HttpPatch("{userId}/status")]
    public async Task<ActionResult<JsonElement?>> UpdateStatus(
        string userId,
        [FromBody] AdminStatusUpdateRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = userId;
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "admin.users.status.unsupported",
            "Hoppa staging OpenAPI does not expose a generic user status update endpoint.");
    }

    private async Task<IReadOnlyList<AdminUserSummaryDto>> EnrichUsersAsync(
        Guid companyId,
        IReadOnlyList<AdminUserProjection> users,
        CancellationToken cancellationToken)
    {
        if (users.Count == 0)
        {
            return Array.Empty<AdminUserSummaryDto>();
        }

        var userIds = users.Select(user => user.LocalUserId).ToArray();

        var hoppaMappingRows = await _dbContext.ProviderMappings
            .AsNoTracking()
            .Where(mapping => mapping.CompanyInstallationId == companyId &&
                              mapping.Provider == "hoppa" &&
                              mapping.ProviderEntityType == "user" &&
                              mapping.InternalEntityType == "user" &&
                              userIds.Contains(mapping.InternalEntityId))
            .OrderByDescending(mapping => mapping.UpdatedAt)
            .Select(mapping => new
            {
                LocalUserId = mapping.InternalEntityId,
                HoppaUserId = mapping.ProviderEntityId
            })
            .ToListAsync(cancellationToken);

        var hoppaMappings = hoppaMappingRows
            .GroupBy(mapping => mapping.LocalUserId)
            .ToDictionary(group => group.Key, group => group.First().HoppaUserId);

        var kycRows = await _dbContext.KycVerifications
            .AsNoTracking()
            .Where(kyc => kyc.CompanyInstallationId == companyId && userIds.Contains(kyc.UserId))
            .OrderByDescending(kyc => kyc.UpdatedAt)
            .Select(kyc => new
            {
                LocalUserId = kyc.UserId,
                kyc.Status,
                kyc.Level,
                kyc.Provider,
                kyc.ProviderReference
            })
            .ToListAsync(cancellationToken);

        var kycSummaries = kycRows
            .GroupBy(kyc => kyc.LocalUserId)
            .ToDictionary(group => group.Key, group => group.First());

        return users
            .Select(user =>
            {
                hoppaMappings.TryGetValue(user.LocalUserId, out var hoppaUserId);
                kycSummaries.TryGetValue(user.LocalUserId, out var kyc);

                return new AdminUserSummaryDto
                {
                    LocalUserId = user.LocalUserId,
                    HoppaUserId = hoppaUserId,
                    DisplayName = user.DisplayName,
                    Email = user.Email,
                    Status = user.Status,
                    CreatedAt = user.CreatedAt,
                    UpdatedAt = user.UpdatedAt,
                    LastLoginAt = user.LastLoginAt,
                    KycStatus = kyc?.Status,
                    KycLevel = kyc?.Level,
                    KycProvider = kyc?.Provider,
                    KycProviderReference = kyc?.ProviderReference,
                    Tier = null
                };
            })
            .ToArray();
    }

    private async Task<AdminUserListResponseDto> SearchUsersCoreAsync(
        Guid companyId,
        string term,
        int pageSize,
        CancellationToken cancellationToken)
    {
        var matchedUserIds = new HashSet<Guid>();
        if (Guid.TryParse(term, out var localUserId))
        {
            matchedUserIds.Add(localUserId);
        }

        var mappedUserIds = await _dbContext.ProviderMappings
            .AsNoTracking()
            .Where(mapping => mapping.CompanyInstallationId == companyId &&
                              mapping.Provider == "hoppa" &&
                              mapping.ProviderEntityType == "user" &&
                              mapping.InternalEntityType == "user" &&
                              mapping.ProviderEntityId == term)
            .Select(mapping => mapping.InternalEntityId)
            .ToListAsync(cancellationToken);

        foreach (var mappedUserId in mappedUserIds)
        {
            matchedUserIds.Add(mappedUserId);
        }

        var exactUserIds = matchedUserIds.ToArray();
        var normalizedEmailTerm = term.ToUpperInvariant();
        var loweredTerm = term.ToLower();
        var usersQuery = _dbContext.Users
            .AsNoTracking()
            .Where(user => user.CompanyInstallationId == companyId &&
                user.AdminProfile == null &&
                (exactUserIds.Contains(user.Id) ||
                 user.EmailNormalized.Contains(normalizedEmailTerm) ||
                 user.Email.ToLower().Contains(loweredTerm) ||
                 (user.DisplayName != null && user.DisplayName.ToLower().Contains(loweredTerm))))
            .OrderByDescending(user => exactUserIds.Contains(user.Id))
            .ThenByDescending(user => user.CreatedAt);

        var totalCount = await usersQuery.CountAsync(cancellationToken);
        var users = await usersQuery
            .Take(pageSize)
            .Select(user => new AdminUserProjection(
                user.Id,
                user.Email,
                user.DisplayName,
                user.Status,
                user.CreatedAt,
                user.UpdatedAt,
                user.LastLoginAt))
            .ToListAsync(cancellationToken);

        var summaries = await EnrichUsersAsync(companyId, users, cancellationToken);

        return new AdminUserListResponseDto
        {
            Items = summaries,
            TotalCount = totalCount
        };
    }

    private static int ClampLimit(int? limit)
    {
        return Math.Clamp(limit ?? 50, 1, 100);
    }

    private sealed record AdminUserProjection(
        Guid LocalUserId,
        string Email,
        string? DisplayName,
        string Status,
        DateTimeOffset CreatedAt,
        DateTimeOffset UpdatedAt,
        DateTimeOffset? LastLoginAt);
}
