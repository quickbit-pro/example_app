using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.Security;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/audit")]
public sealed class AdminAuditController(NeoBankingDbContext dbContext) : ApiControllerBase
{
    [HttpGet("~/api/v1/admin/audit-log")]
    [HttpGet("events")]
    public async Task<ActionResult<object>> ListEvents(
        [FromQuery] string? actorUserId,
        [FromQuery] string? entityType,
        [FromQuery] DateOnly? from,
        [FromQuery] DateOnly? to,
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

        var query = dbContext.AuditLogEntries
            .AsNoTracking()
            .Where(entry => entry.CompanyInstallationId == companyId);

        if (Guid.TryParse(actorUserId, out var parsedActorUserId))
        {
            query = query.Where(entry => entry.ActorUserId == parsedActorUserId);
        }

        if (!string.IsNullOrWhiteSpace(entityType))
        {
            query = query.Where(entry => entry.EntityType == entityType);
        }

        if (from is not null)
        {
            var fromDate = new DateTimeOffset(from.Value.ToDateTime(TimeOnly.MinValue), TimeSpan.Zero);
            query = query.Where(entry => entry.OccurredAt >= fromDate);
        }

        if (to is not null)
        {
            var toDate = new DateTimeOffset(to.Value.AddDays(1).ToDateTime(TimeOnly.MinValue), TimeSpan.Zero);
            query = query.Where(entry => entry.OccurredAt < toDate);
        }

        var take = Math.Clamp(limit ?? 100, 1, 500);
        var skip = Math.Max(0, offset ?? 0);
        var totalCount = await query.CountAsync(cancellationToken);

        var desc = !string.Equals(sortDir, "asc", StringComparison.OrdinalIgnoreCase);
        IOrderedQueryable<Domain.Entities.AuditLogEntry> ordered = (sortBy?.ToLowerInvariant()) switch
        {
            "action" => desc ? query.OrderByDescending(e => e.Action) : query.OrderBy(e => e.Action),
            "actor" => desc ? query.OrderByDescending(e => e.ActorUserId) : query.OrderBy(e => e.ActorUserId),
            "target" => desc ? query.OrderByDescending(e => e.EntityType) : query.OrderBy(e => e.EntityType),
            "traceid" => desc ? query.OrderByDescending(e => e.TraceId) : query.OrderBy(e => e.TraceId),
            _ => desc ? query.OrderByDescending(e => e.OccurredAt) : query.OrderBy(e => e.OccurredAt),
        };

        var auditEntries = await ordered
            .Skip(skip)
            .Take(take)
            .Select(entry => new
            {
                id = entry.Id,
                time = entry.OccurredAt,
                actor = entry.ActorUserId,
                action = entry.Action,
                target = entry.EntityType,
                traceId = entry.TraceId,
                metadata = entry.MetadataJson
            })
            .ToListAsync(cancellationToken);

        var events = auditEntries.Select(entry => new
        {
            entry.id,
            entry.time,
            entry.actor,
            entry.action,
            entry.target,
            result = MetadataIndicatesFailure(entry.metadata) ? "failed" : "success",
            entry.traceId,
            entry.metadata
        });

        return Ok(new { items = events, events, totalCount });
    }

    [HttpGet("events/{eventId}")]
    public async Task<ActionResult<object>> GetEvent(string eventId, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        if (!Guid.TryParse(eventId, out var parsedEventId))
        {
            return NotFound();
        }

        var entry = await dbContext.AuditLogEntries
            .AsNoTracking()
            .Where(auditEntry => auditEntry.CompanyInstallationId == companyId && auditEntry.Id == parsedEventId)
            .Select(auditEntry => new
            {
                id = auditEntry.Id,
                time = auditEntry.OccurredAt,
                actor = auditEntry.ActorUserId,
                action = auditEntry.Action,
                target = auditEntry.EntityType,
                traceId = auditEntry.TraceId,
                ipAddress = auditEntry.IpAddress,
                userAgent = auditEntry.UserAgent,
                before = auditEntry.BeforeJson,
                after = auditEntry.AfterJson,
                metadata = auditEntry.MetadataJson
            })
            .SingleOrDefaultAsync(cancellationToken);

        return entry is null ? NotFound() : Ok(entry);
    }

    private static bool MetadataIndicatesFailure(string? metadataJson)
    {
        return !string.IsNullOrWhiteSpace(metadataJson) &&
            metadataJson.Contains("failed", StringComparison.OrdinalIgnoreCase);
    }
}
