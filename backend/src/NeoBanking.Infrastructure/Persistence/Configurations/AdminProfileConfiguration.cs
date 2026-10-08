#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class AdminProfileConfiguration : IEntityTypeConfiguration<AdminProfile>
{
    public void Configure(EntityTypeBuilder<AdminProfile> builder)
    {
        builder.ToTable("admin_profiles");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(profile => profile.UserId).IsRequired();
        builder.Property(profile => profile.Role).IsRequired().HasMaxLength(80);
        builder.Property(profile => profile.PermissionsJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'[]'::jsonb");

        builder
            .HasOne(profile => profile.CompanyInstallation)
            .WithMany()
            .HasForeignKey(profile => profile.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(profile => profile.User)
            .WithOne(user => user.AdminProfile)
            .HasForeignKey<AdminProfile>(profile => profile.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(profile => profile.UserId).IsUnique();
        builder.HasIndex(profile => new { profile.CompanyInstallationId, profile.Role });
    }
}
