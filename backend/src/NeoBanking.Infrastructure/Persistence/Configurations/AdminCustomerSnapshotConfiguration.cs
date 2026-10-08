#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class AdminCustomerSnapshotConfiguration : IEntityTypeConfiguration<AdminCustomerSnapshot>
{
    public void Configure(EntityTypeBuilder<AdminCustomerSnapshot> builder)
    {
        builder.ToTable("admin_customer_snapshots");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(snapshot => snapshot.ProviderUserId).HasMaxLength(160);
        builder.Property(snapshot => snapshot.CustomerType).HasMaxLength(40).IsRequired();
        builder.Property(snapshot => snapshot.OnboardingStatus).HasMaxLength(40).IsRequired();
        builder.Property(snapshot => snapshot.OnboardingStep).HasMaxLength(80).IsRequired();
        builder.Property(snapshot => snapshot.VerificationStatus).HasMaxLength(40).IsRequired();
        builder.Property(snapshot => snapshot.VerificationLevel).HasMaxLength(80);
        builder.Property(snapshot => snapshot.BalanceSummaryJson).HasColumnType("jsonb").IsRequired();
        builder.Property(snapshot => snapshot.AccountSummaryJson).HasColumnType("jsonb").IsRequired();
        builder.Property(snapshot => snapshot.CardSummaryJson).HasColumnType("jsonb").IsRequired();
        builder.Property(snapshot => snapshot.RecentTransactionsJson).HasColumnType("jsonb").IsRequired();
        builder.Property(snapshot => snapshot.VerificationDetailsJson).HasColumnType("jsonb").IsRequired();
        builder.Property(snapshot => snapshot.TransactionInflow30dJson).HasColumnType("jsonb").IsRequired();
        builder.Property(snapshot => snapshot.TransactionOutflow30dJson).HasColumnType("jsonb").IsRequired();
        builder.Property(snapshot => snapshot.LastSyncError).HasMaxLength(1000);

        builder
            .HasOne(snapshot => snapshot.User)
            .WithMany()
            .HasForeignKey(snapshot => snapshot.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder
            .HasOne(snapshot => snapshot.CompanyInstallation)
            .WithMany()
            .HasForeignKey(snapshot => snapshot.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(snapshot => new { snapshot.CompanyInstallationId, snapshot.UserId }).IsUnique();
        builder.HasIndex(snapshot => new { snapshot.CompanyInstallationId, snapshot.VerificationStatus });
        builder.HasIndex(snapshot => new { snapshot.CompanyInstallationId, snapshot.LastActivityAt });
        builder.HasIndex(snapshot => new { snapshot.CompanyInstallationId, snapshot.LastSyncedAt });
        builder.HasIndex(snapshot => new { snapshot.CompanyInstallationId, snapshot.NextSyncAt });
    }
}
