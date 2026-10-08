#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class HoppaApiCallLogConfiguration : IEntityTypeConfiguration<HoppaApiCallLog>
{
    public void Configure(EntityTypeBuilder<HoppaApiCallLog> builder)
    {
        builder.ToTable("hoppa_api_call_logs");
        builder.ConfigureEntity();

        builder.Property(entry => entry.TraceId).HasMaxLength(120);
        builder.Property(entry => entry.IpAddress).HasMaxLength(64);
        builder.Property(entry => entry.UserAgent).HasMaxLength(512);
        builder.Property(entry => entry.OccurredAt).IsRequired().HasDefaultValueSql("now()");
        builder.Property(entry => entry.Direction).IsRequired().HasMaxLength(32).HasDefaultValue("outbound");
        builder.Property(entry => entry.AppMethod).IsRequired().HasMaxLength(16);
        builder.Property(entry => entry.AppPath).IsRequired().HasMaxLength(512);
        builder.Property(entry => entry.AppQueryString).HasMaxLength(2048);
        builder.Property(entry => entry.AppRequestJson).HasColumnType("jsonb");
        builder.Property(entry => entry.AppResponseJson).HasColumnType("jsonb");
        builder.Property(entry => entry.HoppaMethod).IsRequired().HasMaxLength(16);
        builder.Property(entry => entry.HoppaEndpoint).IsRequired().HasMaxLength(512);
        builder.Property(entry => entry.HoppaQueryString).HasMaxLength(2048);
        builder.Property(entry => entry.HoppaDurationMs).IsRequired();
        builder.Property(entry => entry.Succeeded).IsRequired();
        builder.Property(entry => entry.FailureCode).HasMaxLength(160);
        builder.Property(entry => entry.FailureMessage).HasMaxLength(512);
        builder.Property(entry => entry.HoppaRequestJson).HasColumnType("jsonb");
        builder.Property(entry => entry.HoppaResponseJson).HasColumnType("jsonb");

        builder
            .HasOne(entry => entry.CompanyInstallation)
            .WithMany()
            .HasForeignKey(entry => entry.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(entry => entry.ActorUser)
            .WithMany()
            .HasForeignKey(entry => entry.ActorUserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(entry => new { entry.CompanyInstallationId, entry.OccurredAt });
        builder.HasIndex(entry => new { entry.ActorUserId, entry.OccurredAt });
        builder.HasIndex(entry => entry.TraceId);
        builder.HasIndex(entry => new { entry.HoppaEndpoint, entry.OccurredAt });
        builder.HasIndex(entry => new { entry.Succeeded, entry.OccurredAt });
        builder.HasIndex(entry => new { entry.Direction, entry.OccurredAt });
    }
}
