using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Notifications;
using NeoBanking.Api.Support;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/support-tickets")]
public sealed class AdminSupportTicketsController(NeoBankingDbContext db, PushNotificationOutbox outbox) : ApiControllerBase
{
    [HttpGet]
    public async Task<ActionResult<SupportTicketPage>> List(
        [FromQuery] string? status = null, [FromQuery] int offset = 0, [FromQuery] int limit = 30,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetCompanyInstallationId(out var companyId)) return Unauthorized();
        if (status is not null && !SupportTicketStatuses.IsValid(status)) return BadRequest(new { message = "Unknown ticket status." });
        var query = db.SupportTickets.AsNoTracking().Include(x => x.User)
            .Where(x => x.CompanyInstallationId == companyId);
        if (status is not null) query = query.Where(x => x.Status == status);
        var count = await query.CountAsync(cancellationToken);
        var tickets = await query.OrderByDescending(x => x.UpdatedAt).ThenByDescending(x => x.Id)
            .Skip(Math.Max(0, offset)).Take(Math.Clamp(limit, 1, 100)).ToListAsync(cancellationToken);
        return Ok(new SupportTicketPage(tickets.Select(x => SupportTicketResponses.Summary(x, true)).ToList(), count));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<SupportTicketDetail>> Get(Guid id, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId)) return Unauthorized();
        var ticket = await db.SupportTickets.AsNoTracking().Include(x => x.User).Include(x => x.Messages)
            .SingleOrDefaultAsync(x => x.Id == id && x.CompanyInstallationId == companyId, cancellationToken);
        return ticket is null ? NotFound() : Ok(SupportTicketResponses.Detail(ticket, true));
    }

    [HttpPost("{id:guid}/replies")]
    public async Task<ActionResult<SupportTicketDetail>> Reply(
        Guid id, [FromBody] ReplyToSupportTicketRequest request, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId) || !TryGetLocalUserId(out var localId) || !Guid.TryParse(localId, out var adminId))
            return Unauthorized();
        if (!SupportTicketResponses.ValidBody(request.Body)) return BadRequest(new { message = "Enter a reply of up to 8,000 characters." });
        var ticket = await Find(id, companyId, cancellationToken);
        if (ticket is null) return NotFound();
        if (ticket.Revision != request.Revision) return TicketChanged();
        var message = new SupportTicketMessage { TicketId = ticket.Id, AuthorUserId = adminId, IsAdmin = true, Body = request.Body.Trim() };
        db.SupportTicketMessages.Add(message);
        ticket.Status = SupportTicketStatuses.AwaitingUser;
        ticket.Revision = Guid.NewGuid();
        await Notify(ticket, $"support-reply:{message.Id}", "support.reply", "Support has replied",
            "There is a new reply to your support ticket. Open the app to read it.", cancellationToken);
        return await Save(ticket, cancellationToken);
    }

    [HttpPatch("{id:guid}/status")]
    public async Task<ActionResult<SupportTicketDetail>> SetStatus(
        Guid id, [FromBody] SetSupportTicketStatusRequest request, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId)) return Unauthorized();
        // Waiting for the customer is only set by actually sending a reply.
        if (request.Status is not (SupportTicketStatuses.AwaitingSupport or SupportTicketStatuses.Resolved))
            return BadRequest(new { message = "Choose resolved or awaiting support." });
        var ticket = await Find(id, companyId, cancellationToken);
        if (ticket is null) return NotFound();
        if (ticket.Revision != request.Revision) return TicketChanged();
        if (ticket.Status == request.Status) return Ok(SupportTicketResponses.Detail(ticket, true));
        ticket.Status = request.Status;
        ticket.Revision = Guid.NewGuid();
        await Notify(ticket, $"support-status:{ticket.Revision}", "support.status", "Support ticket updated",
            request.Status == SupportTicketStatuses.Resolved
                ? "Your support ticket was marked resolved. You can reply to reopen it if you still need help."
                : "Your support ticket has been reopened. Our team will review it and reply here.", cancellationToken);
        return await Save(ticket, cancellationToken);
    }

    private Task<SupportTicket?> Find(Guid id, Guid companyId, CancellationToken ct) =>
        db.SupportTickets.Include(x => x.User).Include(x => x.Messages)
            .SingleOrDefaultAsync(x => x.Id == id && x.CompanyInstallationId == companyId, ct);

    private Task Notify(SupportTicket ticket, string eventId, string eventType, string title, string body, CancellationToken ct) =>
        outbox.EnqueueAsync(ticket.CompanyInstallationId, ticket.UserId, eventId, eventType,
            new UserPushMessage(title, body, $"/support/{ticket.Id}", new Dictionary<string, string> { ["ticketId"] = ticket.Id.ToString() }),
            DateTimeOffset.UtcNow, ct);

    private async Task<ActionResult<SupportTicketDetail>> Save(SupportTicket ticket, CancellationToken ct)
    {
        // The reply, status, and notification commit together.
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateConcurrencyException) { return TicketChanged(); }
        return Ok(SupportTicketResponses.Detail(ticket, true));
    }

    private ConflictObjectResult TicketChanged() => Conflict(new { message = "This ticket has changed. Refresh it before submitting. Your draft has been kept." });
}
