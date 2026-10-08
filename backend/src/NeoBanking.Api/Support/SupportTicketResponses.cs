using System.ComponentModel.DataAnnotations;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Api.Support;

public sealed record CreateSupportTicketRequest(
    [Required, StringLength(160)] string Subject,
    [Required, StringLength(8000)] string Body);
public sealed record ReplyToSupportTicketRequest(
    [Required, StringLength(8000)] string Body, Guid Revision);
public sealed record SetSupportTicketStatusRequest(string Status, Guid Revision);
public sealed record SupportMessageResponse(Guid Id, bool IsAdmin, string Body, DateTimeOffset CreatedAt);
public sealed record SupportTicketSummary(
    Guid Id, string Subject, string Status, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt,
    Guid Revision, Guid? CustomerId, string? CustomerName, string? CustomerEmail);
public sealed record SupportTicketPage(IReadOnlyList<SupportTicketSummary> Items, int TotalCount);
public sealed record SupportTicketDetail(SupportTicketSummary Ticket, IReadOnlyList<SupportMessageResponse> Messages);

public static class SupportTicketResponses
{
    public static SupportTicketSummary Summary(SupportTicket ticket, bool admin = false) => new(
        ticket.Id, ticket.Subject, ticket.Status, ticket.CreatedAt, ticket.UpdatedAt, ticket.Revision,
        admin ? ticket.UserId : null,
        admin ? ticket.User?.DisplayName : null, admin ? ticket.User?.Email : null);

    public static SupportTicketDetail Detail(SupportTicket ticket, bool admin = false) => new(
        Summary(ticket, admin), ticket.Messages.OrderBy(x => x.CreatedAt).ThenBy(x => x.Id)
            .Select(x => new SupportMessageResponse(x.Id, x.IsAdmin, x.Body, x.CreatedAt)).ToList());

    public static bool ValidBody(string? body) => !string.IsNullOrWhiteSpace(body) && body.Length <= 8000;
}
