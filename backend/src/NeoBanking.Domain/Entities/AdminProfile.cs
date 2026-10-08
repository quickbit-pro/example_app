#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class AdminProfile : CompanyScopedEntity
{
    public Guid UserId { get; set; }

    public ApplicationUser? User { get; set; }

    public string Role { get; set; } = "support";

    public string PermissionsJson { get; set; } = "[]";

    public bool IsBreakGlass { get; set; }

    public Guid? ApprovedByUserId { get; set; }

    public DateTimeOffset? ApprovedAt { get; set; }
}
