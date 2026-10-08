#nullable enable

namespace NeoBanking.Domain.Entities;

/// <summary>Operator-owned facts about a customer that the provider sync never touches.</summary>
public sealed class AdminCustomerFlag : CompanyScopedEntity
{
    public Guid UserId { get; set; }

    public ApplicationUser? User { get; set; }

    /// <summary>Internal and test accounts are left out of KPIs.</summary>
    public bool IsTestAccount { get; set; }

    public Guid? UpdatedByUserId { get; set; }
}
