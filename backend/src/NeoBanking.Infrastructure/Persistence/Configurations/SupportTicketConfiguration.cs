using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class SupportTicketConfiguration : IEntityTypeConfiguration<SupportTicket>
{
    public void Configure(EntityTypeBuilder<SupportTicket> builder)
    {
        builder.ToTable("support_tickets");
        builder.ConfigureCompanyScopedEntity();
        builder.Property(x => x.Subject).IsRequired().HasMaxLength(160);
        builder.Property(x => x.Status).IsRequired().HasMaxLength(24);
        builder.Property(x => x.Revision).IsConcurrencyToken();
        builder.HasOne(x => x.CompanyInstallation).WithMany()
            .HasForeignKey(x => x.CompanyInstallationId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne(x => x.User).WithMany()
            .HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        builder.HasIndex(x => new { x.CompanyInstallationId, x.UserId, x.UpdatedAt });
        builder.HasIndex(x => new { x.CompanyInstallationId, x.Status, x.UpdatedAt });
    }
}

public sealed class SupportTicketMessageConfiguration : IEntityTypeConfiguration<SupportTicketMessage>
{
    public void Configure(EntityTypeBuilder<SupportTicketMessage> builder)
    {
        builder.ToTable("support_ticket_messages");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Body).IsRequired().HasMaxLength(8000);
        builder.HasOne(x => x.Ticket).WithMany(x => x.Messages)
            .HasForeignKey(x => x.TicketId).OnDelete(DeleteBehavior.Cascade);
        builder.HasIndex(x => new { x.TicketId, x.CreatedAt });
    }
}
