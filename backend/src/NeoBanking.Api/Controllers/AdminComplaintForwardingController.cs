using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Api.Support;
using NeoBanking.Application.Security;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/support-tickets")]
public sealed class AdminComplaintForwardingController(NeoBankingDbContext db,
    IOptions<CompanyOptions> company, IHostEnvironment environment) : ApiControllerBase
{
    public sealed record ForwardComplaint(Guid Revision);

    [HttpPost("{id:guid}/forward-to-equals")]
    public async Task<ActionResult<SupportTicketDetail>> Forward(Guid id, [FromBody] ForwardComplaint request, CancellationToken ct)
    {
        if (!TryGetCompanyInstallationId(out var installation)) return Unauthorized();
        if (!company.Value.Features.EqualsMoneyEnabled) return NotFound();
        var ticket = await db.SupportTickets.Include(x => x.User).Include(x => x.Messages)
            .SingleOrDefaultAsync(x => x.Id == id && x.CompanyInstallationId == installation, ct);
        if (ticket?.User == null) return NotFound();
        if (ticket.Revision != request.Revision) return Conflict(new { message = "Refresh the ticket before forwarding it." });
        var existing = await db.EmailMessages.SingleOrDefaultAsync(x => x.Id == id && x.CompanyInstallationId == installation, ct);
        if (existing != null) {
            // An accepted or pending message must never be sent again on a repeat click.
            if (existing.TemplateKey == EqualsComplaintForwarding.Template && existing.Status is "failed" or "held") {
                existing.Status = environment.IsProduction() ? "pending" : "staging_preview";
                existing.AttemptCount = 0;
                existing.NextAttemptAt = DateTimeOffset.UtcNow;
                existing.ErrorMessage = null;
                await db.SaveChangesAsync(ct);
            }
            return Ok(await EqualsComplaintForwarding.Detail(db, ticket, true, ct));
        }
        var accountId = await db.ProviderMappings.AsNoTracking().Where(x =>
                x.CompanyInstallationId == installation && x.InternalEntityType == "user" && x.InternalEntityId == ticket.UserId && x.Provider == "hoppa" && x.ProviderEntityType == "user")
            .OrderByDescending(x => x.UpdatedAt).Select(x => x.ProviderEntityId).FirstOrDefaultAsync(ct);
        if (string.IsNullOrWhiteSpace(accountId)) return Conflict(new { message = "The customer's account reference is missing. Restore it before forwarding." });
        db.EmailMessages.Add(EqualsComplaintForwarding.Build(ticket, ticket.User, company.Value.BrandName, accountId, environment.IsProduction()));
        ticket.Revision = Guid.NewGuid();
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException) { return Conflict(new { message = "The ticket changed. Refresh its forwarding status before trying again." }); }
        return Ok(await EqualsComplaintForwarding.Detail(db, ticket, true, ct));
    }
}
