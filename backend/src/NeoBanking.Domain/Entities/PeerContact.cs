#nullable enable

namespace NeoBanking.Domain.Entities;

/// <summary>Saved recipient for peer transfers (the "favourites" row).</summary>
public sealed class PeerContact : CompanyScopedEntity
{
    public Guid OwnerUserId { get; set; }

    public ApplicationUser? Owner { get; set; }

    public Guid ContactUserId { get; set; }

    public ApplicationUser? Contact { get; set; }

    public string? Nickname { get; set; }
}
