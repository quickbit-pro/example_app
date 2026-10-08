#nullable enable

namespace NeoBanking.Domain.Entities;

public abstract class Entity
{
    public Guid Id { get; set; } = Guid.CreateVersion7();
}

public abstract class AuditableEntity : Entity
{
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public abstract class CompanyScopedEntity : AuditableEntity
{
    public Guid CompanyInstallationId { get; set; }

    public CompanyInstallation? CompanyInstallation { get; set; }
}
