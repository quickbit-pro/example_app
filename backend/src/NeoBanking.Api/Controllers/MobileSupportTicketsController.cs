using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Support;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize]
[Route("api/v1/mobile/support-tickets")]
public sealed class MobileSupportTicketsController(NeoBankingDbContext db) : ApiControllerBase
{
    private bool Identity(out Guid companyId, out Guid userId)
    {
        userId = default;
        return TryGetCompanyInstallationId(out companyId) &&
            TryGetLocalUserId(out var localId) && Guid.TryParse(localId, out userId);
    }

    [HttpGet]
    public async Task<ActionResult<SupportTicketPage>> List(
        [FromQuery] int offset = 0, [FromQuery] int limit = 30, CancellationToken cancellationToken = default)
    {
        if (!Identity(out var companyId, out var userId)) return Unauthorized();
        var query = db.SupportTickets.AsNoTracking()
            .Where(x => x.CompanyInstallationId == companyId && x.UserId == userId);
        var count = await query.CountAsync(cancellationToken);
        var tickets = await query.OrderByDescending(x => x.UpdatedAt).ThenByDescending(x => x.Id)
            .Skip(Math.Max(0, offset)).Take(Math.Clamp(limit, 1, 100)).ToListAsync(cancellationToken);
        return Ok(new SupportTicketPage(tickets.Select(x => SupportTicketResponses.Summary(x)).ToList(), count));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<SupportTicketDetail>> Get(Guid id, CancellationToken cancellationToken)
    {
        if (!Identity(out var companyId, out var userId)) return Unauthorized();
        var ticket = await db.SupportTickets.AsNoTracking().Include(x => x.Messages)
            .SingleOrDefaultAsync(x => x.Id == id && x.CompanyInstallationId == companyId && x.UserId == userId, cancellationToken);
        return ticket is null ? NotFound() : Ok(SupportTicketResponses.Detail(ticket));
    }

    [HttpPost]
    public async Task<ActionResult<SupportTicketDetail>> Create(
        [FromBody] CreateSupportTicketRequest request, CancellationToken cancellationToken)
    {
        if (!Identity(out var companyId, out var userId)) return Unauthorized();
        if (string.IsNullOrWhiteSpace(request.Subject) || request.Subject.Length > 160 || !SupportTicketResponses.ValidBody(request.Body))
            return BadRequest(new { message = "Enter a subject (up to 160 characters) and a message (up to 8,000 characters)." });
        if (!await db.Users.AnyAsync(x => x.Id == userId && x.CompanyInstallationId == companyId, cancellationToken))
            return Unauthorized();
        var ticket = new SupportTicket
        {
            CompanyInstallationId = companyId, UserId = userId, Subject = request.Subject.Trim(),
            Messages = [new SupportTicketMessage { AuthorUserId = userId, Body = request.Body.Trim() }]
        };
        db.SupportTickets.Add(ticket);
        await db.SaveChangesAsync(cancellationToken);
        return CreatedAtAction(nameof(Get), new { id = ticket.Id }, SupportTicketResponses.Detail(ticket));
    }

    [HttpPost("{id:guid}/replies")]
    public async Task<ActionResult<SupportTicketDetail>> Reply(
        Guid id, [FromBody] ReplyToSupportTicketRequest request, CancellationToken cancellationToken)
    {
        if (!Identity(out var companyId, out var userId)) return Unauthorized();
        if (!SupportTicketResponses.ValidBody(request.Body)) return BadRequest(new { message = "Enter a reply of up to 8,000 characters." });
        var ticket = await db.SupportTickets.Include(x => x.Messages)
            .SingleOrDefaultAsync(x => x.Id == id && x.CompanyInstallationId == companyId && x.UserId == userId, cancellationToken);
        if (ticket is null) return NotFound();
        if (request.Revision != ticket.Revision) return TicketChanged();
        var message = new SupportTicketMessage { TicketId = ticket.Id, AuthorUserId = userId, Body = request.Body.Trim() };
        db.SupportTicketMessages.Add(message);
        // A reply on a resolved ticket reopens it for support.
        ticket.Status = SupportTicketStatuses.AwaitingSupport;
        ticket.Revision = Guid.NewGuid();
        try { await db.SaveChangesAsync(cancellationToken); }
        catch (DbUpdateConcurrencyException) { return TicketChanged(); }
        return Ok(SupportTicketResponses.Detail(ticket));
    }

    private ConflictObjectResult TicketChanged() => Conflict(new { message = "This ticket has changed. Refresh it before submitting your reply. Your draft has been kept." });
}
