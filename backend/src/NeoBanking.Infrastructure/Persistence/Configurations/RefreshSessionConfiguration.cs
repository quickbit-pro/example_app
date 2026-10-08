#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class RefreshSessionConfiguration : IEntityTypeConfiguration<RefreshSession>
{
    public void Configure(EntityTypeBuilder<RefreshSession> builder)
    {
        builder.ToTable("refresh_sessions");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(session => session.UserId).IsRequired();
        builder.Property(session => session.TokenHash).IsRequired().HasMaxLength(128);
        builder.Property(session => session.RotatedFromTokenHash).HasMaxLength(128);
        builder.Property(session => session.DeviceId).HasMaxLength(120);
        builder.Property(session => session.DeviceName).HasMaxLength(160);
        builder.Property(session => session.IpAddress).HasMaxLength(64);
        builder.Property(session => session.UserAgent).HasMaxLength(512);
        builder.Property(session => session.RevocationReason).HasMaxLength(240);
        builder.Property(session => session.MetadataJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");

        builder
            .HasOne(session => session.CompanyInstallation)
            .WithMany()
            .HasForeignKey(session => session.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(session => session.User)
            .WithMany(user => user.RefreshSessions)
            .HasForeignKey(session => session.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(session => session.TokenHash).IsUnique();
        builder.HasIndex(session => new { session.CompanyInstallationId, session.UserId, session.ExpiresAt });
        builder.HasIndex(session => session.RevokedAt);
    }
}
