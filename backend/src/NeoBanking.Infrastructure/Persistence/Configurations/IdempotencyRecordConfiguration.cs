#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class IdempotencyRecordConfiguration : IEntityTypeConfiguration<IdempotencyRecord>
{
    public void Configure(EntityTypeBuilder<IdempotencyRecord> builder)
    {
        builder.ToTable("idempotency_records");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(record => record.Scope).IsRequired().HasMaxLength(120);
        builder.Property(record => record.Key).IsRequired().HasMaxLength(240);
        builder.Property(record => record.RequestHash).IsRequired().HasMaxLength(128);
        builder.Property(record => record.Status).IsRequired().HasMaxLength(ConfigurationDefaults.StatusLength);
        builder.Property(record => record.ResponseBodyJson).HasColumnType("jsonb");

        builder
            .HasOne(record => record.CompanyInstallation)
            .WithMany(company => company.IdempotencyRecords)
            .HasForeignKey(record => record.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(record => new { record.CompanyInstallationId, record.Scope, record.Key }).IsUnique();
        builder.HasIndex(record => new { record.CompanyInstallationId, record.Status, record.LockedUntil });
        builder.HasIndex(record => record.ExpiresAt);
    }
}
