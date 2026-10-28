using System.Net;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Support;

public static class EqualsComplaintForwarding
{
    public const string Template = "equals_complaint_forward";
    public const string Recipient = "complaints@equalsmoney.com";

    // The initial forwarding message uses the ticket ID. This gives one durable
    // forwarding record per complaint without changing existing ticket tables.
    public static EmailMessage Build(SupportTicket ticket, ApplicationUser user,
        string programme, string accountId, bool production)
    {
        var text = $"Programme: {programme}\nCustomer account identifier: {accountId}\nCustomer: {user.DisplayName}\nCustomer email: {user.Email}\nComplaint reference: {ticket.Id}\nReceived: {DateTimeOffset.UtcNow:O}\nSubject: {ticket.Subject}\n\n" +
            string.Join("\n\n", ticket.Messages.OrderBy(x => x.CreatedAt).Select(x =>
                $"{(x.IsAdmin ? "Support" : "Customer")} ({x.CreatedAt:O}):\n{x.Body}"));
        return new EmailMessage {
            Id = ticket.Id, CompanyInstallationId = ticket.CompanyInstallationId, UserId = ticket.UserId,
            TemplateKey = Template, ToEmail = Recipient, ToName = "Equals Money Complaints",
            Subject = $"{programme} complaint {ticket.Id}", TextBody = text,
            HtmlBody = $"<pre style=\"white-space:pre-wrap;font-family:Arial,sans-serif\">{WebUtility.HtmlEncode(text)}</pre>",
            Status = production ? "pending" : "staging_preview", NextAttemptAt = DateTimeOffset.UtcNow,
            MetadataJson = JsonSerializer.Serialize(new { ticketId = ticket.Id, accountId, programme })
        };
    }

    public static async Task<SupportTicketDetail> Detail(NeoBankingDbContext db, SupportTicket ticket,
        bool admin, CancellationToken ct)
    {
        var email = await db.EmailMessages.AsNoTracking().SingleOrDefaultAsync(x =>
            x.Id == ticket.Id && x.CompanyInstallationId == ticket.CompanyInstallationId && x.TemplateKey == Template, ct);
        return SupportTicketResponses.Detail(ticket, admin) with {
            ComplaintForwarding = email == null ? null : new ComplaintForwardingResponse(email.Status, email.SentAt)
        };
    }
}
