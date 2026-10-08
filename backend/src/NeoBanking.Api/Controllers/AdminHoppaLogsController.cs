using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.Security;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/hoppa-logs")]
public sealed class AdminHoppaLogsController(NeoBankingDbContext dbContext) : ApiControllerBase
{
    [HttpGet]
    public async Task<ActionResult<object>> ListLogs(
        [FromQuery] string? appPath,
        [FromQuery] string? hoppaEndpoint,
        [FromQuery] string? direction,
        [FromQuery] string? result,
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

        var query = dbContext.HoppaApiCallLogs
            .AsNoTracking()
            .Where(entry => entry.CompanyInstallationId == companyId);

        if (!string.IsNullOrWhiteSpace(appPath))
        {
            query = query.Where(entry => entry.AppPath.Contains(appPath.Trim()));
        }

        if (!string.IsNullOrWhiteSpace(hoppaEndpoint))
        {
            query = query.Where(entry => entry.HoppaEndpoint.Contains(hoppaEndpoint.Trim()));
        }

        if (!string.IsNullOrWhiteSpace(direction))
        {
            query = query.Where(entry => entry.Direction == direction.Trim());
        }

        if (string.Equals(result, "success", StringComparison.OrdinalIgnoreCase))
        {
            query = query.Where(entry => entry.Succeeded);
        }
        else if (string.Equals(result, "failed", StringComparison.OrdinalIgnoreCase))
        {
            query = query.Where(entry => !entry.Succeeded);
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
        IOrderedQueryable<Domain.Entities.HoppaApiCallLog> ordered = (sortBy?.ToLowerInvariant()) switch
        {
            "appendpoint" => desc ? query.OrderByDescending(e => e.AppPath) : query.OrderBy(e => e.AppPath),
            "hoppaendpoint" => desc ? query.OrderByDescending(e => e.HoppaEndpoint) : query.OrderBy(e => e.HoppaEndpoint),
            "appstatus" => desc ? query.OrderByDescending(e => e.AppStatusCode) : query.OrderBy(e => e.AppStatusCode),
            "hoppastatus" => desc ? query.OrderByDescending(e => e.HoppaStatusCode) : query.OrderBy(e => e.HoppaStatusCode),
            "duration" => desc ? query.OrderByDescending(e => e.HoppaDurationMs) : query.OrderBy(e => e.HoppaDurationMs),
            "direction" => desc ? query.OrderByDescending(e => e.Direction) : query.OrderBy(e => e.Direction),
            "result" => desc ? query.OrderByDescending(e => e.Succeeded) : query.OrderBy(e => e.Succeeded),
            "traceid" => desc ? query.OrderByDescending(e => e.TraceId) : query.OrderBy(e => e.TraceId),
            _ => desc ? query.OrderByDescending(e => e.OccurredAt) : query.OrderBy(e => e.OccurredAt),
        };

        var logs = await ordered
            .Skip(skip)
            .Take(take)
            .Select(entry => new
            {
                id = entry.Id,
                time = entry.OccurredAt,
                direction = entry.Direction,
                appEndpoint = entry.AppMethod + " " + entry.AppPath,
                appStatus = entry.AppStatusCode,
                hoppaEndpoint = entry.HoppaMethod + " " + entry.HoppaEndpoint,
                hoppaStatus = entry.HoppaStatusCode,
                duration = entry.HoppaDurationMs,
                result = entry.Succeeded ? "success" : "failed",
                failureCode = entry.FailureCode,
                traceId = entry.TraceId
            })
            .ToListAsync(cancellationToken);

        return Ok(new { items = logs, logs, totalCount });
    }

    [HttpGet("{logId}")]
    public async Task<ActionResult<object>> GetLog(string logId, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        if (!Guid.TryParse(logId, out var parsedLogId))
        {
            return NotFound();
        }

        var log = await dbContext.HoppaApiCallLogs
            .AsNoTracking()
            .Where(entry => entry.CompanyInstallationId == companyId && entry.Id == parsedLogId)
            .Select(entry => new
            {
                id = entry.Id,
                time = entry.OccurredAt,
                direction = entry.Direction,
                traceId = entry.TraceId,
                actorUserId = entry.ActorUserId,
                ipAddress = entry.IpAddress,
                userAgent = entry.UserAgent,
                result = entry.Succeeded ? "success" : "failed",
                failureCode = entry.FailureCode,
                failureMessage = entry.FailureMessage,
                app = new
                {
                    method = entry.AppMethod,
                    path = entry.AppPath,
                    queryString = entry.AppQueryString,
                    statusCode = entry.AppStatusCode,
                    request = entry.AppRequestJson,
                    response = entry.AppResponseJson
                },
                hoppa = new
                {
                    method = entry.HoppaMethod,
                    endpoint = entry.HoppaEndpoint,
                    queryString = entry.HoppaQueryString,
                    statusCode = entry.HoppaStatusCode,
                    durationMs = entry.HoppaDurationMs,
                    request = entry.HoppaRequestJson,
                    response = entry.HoppaResponseJson
                }
            })
            .SingleOrDefaultAsync(cancellationToken);

        return log is null ? NotFound() : Ok(log);
    }
}
