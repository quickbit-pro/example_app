#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class BankingSnapshotConfiguration : IEntityTypeConfiguration<BankingSnapshot>
{
    public void Configure(EntityTypeBuilder<BankingSnapshot> builder)
    {
        builder.ToTable("banking_snapshots");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(snapshot => snapshot.Provider).IsRequired().HasMaxLength(ConfigurationDefaults.ProviderLength);
        builder.Property(snapshot => snapshot.ProviderReference).IsRequired().HasMaxLength(240);
        builder.Property(snapshot => snapshot.SnapshotType).IsRequired().HasMaxLength(80);
        builder.Property(snapshot => snapshot.Currency).IsRequired().HasMaxLength(ConfigurationDefaults.IsoCurrencyLength);
        builder.Property(snapshot => snapshot.SourceHash).HasMaxLength(128);
        builder.Property(snapshot => snapshot.SnapshotJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");

        builder
            .HasOne(snapshot => snapshot.CompanyInstallation)
            .WithMany()
            .HasForeignKey(snapshot => snapshot.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(snapshot => snapshot.User)
            .WithMany(user => user.BankingSnapshots)
            .HasForeignKey(snapshot => snapshot.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasIndex(snapshot => new
            {
                snapshot.CompanyInstallationId,
                snapshot.Provider,
                snapshot.ProviderReference,
                snapshot.SnapshotType,
                snapshot.AsOf
            })
            .IsUnique();

        builder.HasIndex(snapshot => new { snapshot.CompanyInstallationId, snapshot.UserId, snapshot.AsOf });
        builder.HasIndex(snapshot => snapshot.SourceHash);
    }
}
