using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Api.Support;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/complaints")]
public sealed class MobileComplaintsController(NeoBankingDbContext db, IOptions<CompanyOptions> company,
    IHostEnvironment environment) : ApiControllerBase
{
    public sealed record ComplaintRequest(Guid RequestId,
        [Required, StringLength(140)] string Subject, [Required, StringLength(8000)] string Body);

    [HttpPost]
    public async Task<ActionResult<SupportTicketDetail>> Create([FromBody] ComplaintRequest request, CancellationToken ct)
    {
        if (!TryGetCompanyInstallationId(out var installation) || !TryGetLocalUserId(out var localId) ||
            !Guid.TryParse(localId, out var userId) || !TryGetCurrentUserId(out var accountId)) return Unauthorized();
        if (!company.Value.Features.EqualsMoneyEnabled) return NotFound();
        if (request.RequestId == Guid.Empty || string.IsNullOrWhiteSpace(request.Subject) || request.Subject.Length > 140 || !SupportTicketResponses.ValidBody(request.Body))
            return BadRequest(new { message = "Enter a subject and complaint details." });
        var user = await db.Users.SingleOrDefaultAsync(x => x.Id == userId && x.CompanyInstallationId == installation, ct);
        if (user == null) return Unauthorized();
        var existing = await db.SupportTickets.Include(x => x.Messages).SingleOrDefaultAsync(x => x.Id == request.RequestId, ct);
        if (existing != null) {
            if (existing.CompanyInstallationId != installation || existing.UserId != userId) return NotFound();
            return Ok(await EqualsComplaintForwarding.Detail(db, existing, false, ct));
        }
        var ticket = new SupportTicket {
            Id = request.RequestId, CompanyInstallationId = installation, UserId = userId,
            Subject = "[Complaint] " + request.Subject.Trim(),
            Messages = [new SupportTicketMessage { AuthorUserId = userId, Body = request.Body.Trim() }]
        };
        db.SupportTickets.Add(ticket);
        db.EmailMessages.Add(EqualsComplaintForwarding.Build(ticket, user, company.Value.BrandName, accountId, environment.IsProduction()));
        // Complaint and forwarding job commit together. No merits-based screen.
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException) {
            db.ChangeTracker.Clear();
            var raced = await db.SupportTickets.Include(x => x.Messages).SingleOrDefaultAsync(x => x.Id == request.RequestId && x.CompanyInstallationId == installation && x.UserId == userId, ct);
            if (raced == null) throw;
            return Ok(await EqualsComplaintForwarding.Detail(db, raced, false, ct));
        }
        return Created($"/api/v1/mobile/support-tickets/{ticket.Id}", await EqualsComplaintForwarding.Detail(db, ticket, false, ct));
    }
}
