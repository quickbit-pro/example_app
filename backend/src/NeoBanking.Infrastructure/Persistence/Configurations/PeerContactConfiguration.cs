#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class PeerContactConfiguration : IEntityTypeConfiguration<PeerContact>
{
    public void Configure(EntityTypeBuilder<PeerContact> builder)
    {
        builder.ToTable("peer_contacts");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(contact => contact.Nickname).HasMaxLength(80);

        builder
            .HasOne(contact => contact.CompanyInstallation)
            .WithMany()
            .HasForeignKey(contact => contact.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(contact => contact.Owner)
            .WithMany()
            .HasForeignKey(contact => contact.OwnerUserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder
            .HasOne(contact => contact.Contact)
            .WithMany()
            .HasForeignKey(contact => contact.ContactUserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(contact => new { contact.CompanyInstallationId, contact.OwnerUserId, contact.ContactUserId }).IsUnique();
    }
}
