using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.DTOs.Admin;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/kyc")]
public sealed class AdminKycController : HoppaProxyControllerBase
{
    private readonly NeoBankingDbContext _dbContext;

    public AdminKycController(
        IProxyHoppaRequestUseCase proxyHoppa,
        NeoBankingDbContext dbContext)
        : base(proxyHoppa)
    {
        _dbContext = dbContext;
    }

    [HttpGet("cases")]
    public async Task<ActionResult<JsonElement?>> ListCases(
        [FromQuery] string? status,
        [FromQuery] int? limit,
        [FromQuery] string? cursor,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            "users",
            null,
            "admin.kyc.cases.list.failed",
            "Hoppa failed to list KYC cases.",
            cancellationToken,
            Query(("status", status), ("limit", limit), ("cursor", cursor))));
    }

    [HttpGet("local-cases")]
    public async Task<ActionResult<AdminKycCaseListResponseDto>> ListLocalCases(
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

        var pageSize = Math.Clamp(limit ?? 50, 1, 100);
        var skip = Math.Max(0, offset ?? 0);
        var baseQuery = _dbContext.KycVerifications
            .AsNoTracking()
            .Where(kyc => kyc.CompanyInstallationId == companyId &&
                          (status == null || kyc.Status == status));

        var totalCount = await baseQuery.CountAsync(cancellationToken);
        var desc = !string.Equals(sortDir, "asc", StringComparison.OrdinalIgnoreCase);
        IOrderedQueryable<Domain.Entities.KycVerification> ordered = (sortBy?.ToLowerInvariant()) switch
        {
            "status" => desc ? baseQuery.OrderByDescending(k => k.Status) : baseQuery.OrderBy(k => k.Status),
            "level" => desc ? baseQuery.OrderByDescending(k => k.Level) : baseQuery.OrderBy(k => k.Level),
            "provider" => desc ? baseQuery.OrderByDescending(k => k.Provider) : baseQuery.OrderBy(k => k.Provider),
            "countrycode" => desc ? baseQuery.OrderByDescending(k => k.CountryCode) : baseQuery.OrderBy(k => k.CountryCode),
            "startedat" => desc ? baseQuery.OrderByDescending(k => k.StartedAt) : baseQuery.OrderBy(k => k.StartedAt),
            "submittedat" => desc ? baseQuery.OrderByDescending(k => k.SubmittedAt) : baseQuery.OrderBy(k => k.SubmittedAt),
            "reviewedat" => desc ? baseQuery.OrderByDescending(k => k.ReviewedAt) : baseQuery.OrderBy(k => k.ReviewedAt),
            _ => desc ? baseQuery.OrderByDescending(k => k.UpdatedAt) : baseQuery.OrderBy(k => k.UpdatedAt),
        };

        var cases = await ordered
            .Skip(skip)
            .Take(pageSize)
            .Select(kyc => new
            {
                CaseId = kyc.Id,
                kyc.UserId,
                kyc.User!.DisplayName,
                kyc.User.Email,
                kyc.Status,
                kyc.Level,
                kyc.Provider,
                kyc.ProviderReference,
                kyc.CountryCode,
                kyc.StartedAt,
                kyc.SubmittedAt,
                kyc.ReviewedAt
            })
            .ToListAsync(cancellationToken);

        var userIds = cases.Select(kyc => kyc.UserId).ToArray();
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

        return Ok(new AdminKycCaseListResponseDto
        {
            TotalCount = totalCount,
            Items = cases
                .Select(kyc =>
                {
                    hoppaMappings.TryGetValue(kyc.UserId, out var hoppaUserId);

                    return new AdminKycCaseSummaryDto
                    {
                        CaseId = kyc.CaseId,
                        LocalUserId = kyc.UserId,
                        HoppaUserId = hoppaUserId,
                        DisplayName = kyc.DisplayName,
                        Email = kyc.Email,
                        Status = kyc.Status,
                        Level = kyc.Level,
                        Provider = kyc.Provider,
                        ProviderReference = kyc.ProviderReference,
                        CountryCode = kyc.CountryCode,
                        StartedAt = kyc.StartedAt,
                        SubmittedAt = kyc.SubmittedAt,
                        ReviewedAt = kyc.ReviewedAt
                    };
                })
                .ToArray()
        });
    }

    [HttpGet("cases/{caseId}")]
    public async Task<ActionResult<JsonElement?>> GetCase(string caseId, CancellationToken cancellationToken)
    {
        return ToActionResult(await SendAdminHoppaAsync<object?>(
            HttpMethod.Get,
            $"users/{Segment(caseId)}/kyc/detailed-status",
            null,
            "admin.kyc.cases.get.failed",
            "Hoppa failed to load KYC case.",
            cancellationToken));
    }

    [HttpPost("cases/{caseId}/decisions")]
    public async Task<ActionResult<JsonElement?>> CreateDecision(
        string caseId,
        [FromBody] AdminUserDecisionRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var decision = request.Decision?.Trim().ToLowerInvariant();
        if (decision is not ("approved" or "rejected") || string.IsNullOrWhiteSpace(request.Reason))
        {
            return BadRequest(new { message = "An approved or rejected decision and a reason are required." });
        }

        var customerId = await _dbContext.ProviderMappings
            .AsNoTracking()
            .Where(mapping => mapping.CompanyInstallationId == companyId &&
                              mapping.Provider == "hoppa" &&
                              mapping.ProviderEntityType == "user" &&
                              mapping.ProviderEntityId == caseId)
            .Select(mapping => (Guid?)mapping.InternalEntityId)
            .FirstOrDefaultAsync(cancellationToken);
        if (!customerId.HasValue)
        {
            return NotFound(new { message = "Verification case was not found." });
        }

        var result = await SendAdminHoppaAsync(
            HttpMethod.Post,
            $"users/{Segment(caseId)}/kyc/verify",
            request,
            "admin.kyc.cases.decisions.create.failed",
            "Hoppa failed to create KYC decision.",
            cancellationToken);

        if (result.IsSuccess)
        {
            _dbContext.AuditLogEntries.Add(new Domain.Entities.AuditLogEntry
            {
                CompanyInstallationId = companyId,
                ActorUserId = TryGetLocalUserId(out var actorId) && Guid.TryParse(actorId, out var parsedActorId) ? parsedActorId : null,
                Action = $"verification.{decision}",
                EntityType = "customer_verification",
                EntityId = customerId,
                TraceId = HttpContext.TraceIdentifier,
                IpAddress = GetClientIpAddress(),
                UserAgent = Request.Headers.UserAgent.ToString(),
                AfterJson = JsonSerializer.Serialize(new { decision, reason = request.Reason }),
                MetadataJson = "{\"result\":\"success\"}"
            });
            await _dbContext.SaveChangesAsync(cancellationToken);
        }

        return ToActionResult(result);
    }
}
