using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Admin;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

/// <summary>How the installation reports: the time zone that decides where a reporting day starts.</summary>
[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/reporting-settings")]
public sealed class AdminReportingController(NeoBankingDbContext dbContext) : ApiControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        var settings = await dbContext.CompanyInstallations
            .AsNoTracking()
            .Where(company => company.Id == companyId)
            .Select(company => company.SettingsJson)
            .FirstOrDefaultAsync(cancellationToken);
        return Ok(new { timeZone = AdminReportingSettings.ReadTimeZone(settings), suggestedTimeZones = AdminReportingSettings.SuggestedTimeZones });
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] ReportingSettingsRequest request, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }

        if (!AdminReportingSettings.TryResolve(request.TimeZone, out _))
        {
            return BadRequest(new ValidationProblemDetails(new Dictionary<string, string[]>
            {
                ["timeZone"] = ["Choose a time zone such as Europe/Berlin or UTC."]
            }) { Title = "Check the reporting time zone.", Status = StatusCodes.Status400BadRequest });
        }

        var company = await dbContext.CompanyInstallations.SingleOrDefaultAsync(candidate => candidate.Id == companyId, cancellationToken);
        if (company is null)
        {
            return NotFound();
        }

        var before = AdminReportingSettings.ReadTimeZone(company.SettingsJson);
        var timeZone = request.TimeZone!.Trim();
        company.SettingsJson = AdminReportingSettings.WriteTimeZone(company.SettingsJson, timeZone);
        dbContext.AuditLogEntries.Add(new AuditLogEntry
        {
            CompanyInstallationId = companyId,
            ActorUserId = TryGetLocalUserId(out var actor) && Guid.TryParse(actor, out var actorId) ? actorId : null,
            Action = "reporting_settings.updated",
            EntityType = "company_reporting_settings",
            EntityId = companyId,
            TraceId = HttpContext.TraceIdentifier,
            IpAddress = GetClientIpAddress(),
            UserAgent = Request.Headers.UserAgent.ToString(),
            BeforeJson = JsonSerializer.Serialize(new { timeZone = before }),
            AfterJson = JsonSerializer.Serialize(new { timeZone }),
            MetadataJson = "{\"source\":\"wl_admin\"}"
        });
        await dbContext.SaveChangesAsync(cancellationToken);
        return Ok(new { timeZone, suggestedTimeZones = AdminReportingSettings.SuggestedTimeZones });
    }

    public sealed record ReportingSettingsRequest(string? TimeZone);
}
