#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class AuditLogEntryConfiguration : IEntityTypeConfiguration<AuditLogEntry>
{
    public void Configure(EntityTypeBuilder<AuditLogEntry> builder)
    {
        builder.ToTable("audit_log_entries");
        builder.ConfigureEntity();

        builder.Property(entry => entry.Action).IsRequired().HasMaxLength(160);
        builder.Property(entry => entry.EntityType).IsRequired().HasMaxLength(120);
        builder.Property(entry => entry.TraceId).HasMaxLength(120);
        builder.Property(entry => entry.IpAddress).HasMaxLength(64);
        builder.Property(entry => entry.UserAgent).HasMaxLength(512);
        builder.Property(entry => entry.OccurredAt).IsRequired().HasDefaultValueSql("now()");
        builder.Property(entry => entry.BeforeJson).HasColumnType("jsonb");
        builder.Property(entry => entry.AfterJson).HasColumnType("jsonb");
        builder.Property(entry => entry.MetadataJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");

        builder
            .HasOne(entry => entry.CompanyInstallation)
            .WithMany(company => company.AuditLogs)
            .HasForeignKey(entry => entry.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(entry => entry.ActorUser)
            .WithMany(user => user.AuditLogs)
            .HasForeignKey(entry => entry.ActorUserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(entry => new { entry.CompanyInstallationId, entry.OccurredAt });
        builder.HasIndex(entry => new { entry.ActorUserId, entry.OccurredAt });
        builder.HasIndex(entry => new { entry.EntityType, entry.EntityId });
        builder.HasIndex(entry => entry.TraceId);
    }
}
