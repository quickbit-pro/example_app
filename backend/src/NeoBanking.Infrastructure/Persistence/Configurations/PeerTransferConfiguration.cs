#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class PeerTransferConfiguration : IEntityTypeConfiguration<PeerTransfer>
{
    public void Configure(EntityTypeBuilder<PeerTransfer> builder)
    {
        builder.ToTable("peer_transfers");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(transfer => transfer.Amount).HasColumnType("numeric(24,8)");
        builder.Property(transfer => transfer.FeeAmount).HasColumnType("numeric(24,8)");
        builder.Property(transfer => transfer.Currency).IsRequired().HasMaxLength(8);
        builder.Property(transfer => transfer.Note).HasMaxLength(250);
        builder.Property(transfer => transfer.Status).IsRequired().HasMaxLength(32);
        builder.Property(transfer => transfer.ExternalReferenceId).IsRequired().HasMaxLength(80);
        builder.Property(transfer => transfer.DebitTransferId).HasMaxLength(80);
        builder.Property(transfer => transfer.CreditTransferId).HasMaxLength(80);
        builder.Property(transfer => transfer.RefundTransferId).HasMaxLength(80);
        builder.Property(transfer => transfer.ErrorCode).HasMaxLength(80);
        builder.Property(transfer => transfer.ErrorMessage).HasMaxLength(500);

        builder
            .HasOne(transfer => transfer.CompanyInstallation)
            .WithMany()
            .HasForeignKey(transfer => transfer.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(transfer => transfer.Sender)
            .WithMany()
            .HasForeignKey(transfer => transfer.SenderUserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(transfer => transfer.Recipient)
            .WithMany()
            .HasForeignKey(transfer => transfer.RecipientUserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(transfer => transfer.ExternalReferenceId).IsUnique();
        builder.HasIndex(transfer => new { transfer.CompanyInstallationId, transfer.SenderUserId, transfer.CreatedAt });
        builder.HasIndex(transfer => new { transfer.CompanyInstallationId, transfer.RecipientUserId, transfer.CreatedAt });
        builder.HasIndex(transfer => transfer.Status);
    }
}
