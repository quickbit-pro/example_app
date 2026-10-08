#nullable enable
namespace NeoBanking.Domain.Entities;

public sealed class SupportTicket : CompanyScopedEntity
{
    public Guid UserId { get; set; }
    public ApplicationUser? User { get; set; }
    public string Subject { get; set; } = string.Empty;
    public string Status { get; set; } = SupportTicketStatuses.AwaitingSupport;
    public Guid Revision { get; set; } = Guid.NewGuid();
    public ICollection<SupportTicketMessage> Messages { get; set; } = new List<SupportTicketMessage>();
}

public sealed class SupportTicketMessage : AuditableEntity
{
    public Guid TicketId { get; set; }
    public SupportTicket? Ticket { get; set; }
    public Guid AuthorUserId { get; set; }
    public bool IsAdmin { get; set; }
    public string Body { get; set; } = string.Empty;
}

public static class SupportTicketStatuses
{
    public const string AwaitingSupport = "awaiting_support";
    public const string AwaitingUser = "awaiting_user";
    public const string Resolved = "resolved";
    public static bool IsValid(string? status) => status is AwaitingSupport or AwaitingUser or Resolved;
}
