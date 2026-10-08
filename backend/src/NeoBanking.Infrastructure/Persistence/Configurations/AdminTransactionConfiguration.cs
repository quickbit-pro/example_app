#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class AdminTransactionConfiguration : IEntityTypeConfiguration<AdminTransaction>
{
    public void Configure(EntityTypeBuilder<AdminTransaction> builder)
    {
        builder.ToTable("admin_transactions");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(row => row.ProviderTransactionId).HasMaxLength(100).IsRequired();
        builder.Property(row => row.RawType).HasMaxLength(64).IsRequired();
        builder.Property(row => row.RawStatus).HasMaxLength(40).IsRequired();
        builder.Property(row => row.StatusReason).HasMaxLength(160);
        builder.Property(row => row.Status).HasMaxLength(16).IsRequired();
        builder.Property(row => row.Kind).HasMaxLength(24).IsRequired();
        builder.Property(row => row.FeeType).HasMaxLength(24);
        builder.Property(row => row.Direction).HasMaxLength(10).IsRequired();
        builder.Property(row => row.Amount).HasPrecision(28, 8);
        builder.Property(row => row.Currency).HasMaxLength(12).IsRequired();
        builder.Property(row => row.Description).HasMaxLength(300).IsRequired();
        builder.Property(row => row.Merchant).HasMaxLength(120);
        builder.Property(row => row.MerchantCategory).HasMaxLength(80);
        builder.Property(row => row.CardReference).HasMaxLength(100);
        builder.Property(row => row.WalletReference).HasMaxLength(100);
        builder.Property(row => row.BudgetReference).HasMaxLength(100);
        builder.Property(row => row.AccountReference).HasMaxLength(100);
        builder.Property(row => row.ExternalReference).HasMaxLength(160);
        builder.Property(row => row.RelatedReference).HasMaxLength(160);
        builder.Property(row => row.ClientReference).HasMaxLength(160);
        builder.Property(row => row.FeeAmount).HasPrecision(28, 8);
        builder.Property(row => row.FeeCurrency).HasMaxLength(12);

        builder
            .HasOne(row => row.User)
            .WithMany()
            .HasForeignKey(row => row.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder
            .HasOne(row => row.CompanyInstallation)
            .WithMany()
            .HasForeignKey(row => row.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(row => new { row.CompanyInstallationId, row.ProviderTransactionId }).IsUnique();
        builder.HasIndex(row => new { row.CompanyInstallationId, row.OccurredAt });
        builder.HasIndex(row => new { row.CompanyInstallationId, row.UserId, row.OccurredAt });
        builder.HasIndex(row => new { row.CompanyInstallationId, row.Kind, row.OccurredAt });
    }
}
