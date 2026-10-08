#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class ApplicationUserConfiguration : IEntityTypeConfiguration<ApplicationUser>
{
    public void Configure(EntityTypeBuilder<ApplicationUser> builder)
    {
        builder.ToTable("users");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(user => user.Email).IsRequired().HasMaxLength(320);
        builder.Property(user => user.EmailNormalized).IsRequired().HasMaxLength(320);
        builder.Property(user => user.PhoneNumber).HasMaxLength(40);
        builder.Property(user => user.Nickname).HasMaxLength(30);
        builder.HasIndex(user => new { user.CompanyInstallationId, user.Nickname })
            .IsUnique().HasDatabaseName("IX_users_company_nickname");
        builder.ToTable("users", table => table.HasCheckConstraint(
            "CK_users_nickname_format", "\"Nickname\" IS NULL OR \"Nickname\" ~ '^[a-z][a-z0-9_]{2,29}$'"));
        builder.Property(user => user.DisplayName).HasMaxLength(160);
        builder.Property(user => user.Status).IsRequired().HasMaxLength(ConfigurationDefaults.StatusLength);
        builder.Property(user => user.Locale).IsRequired().HasMaxLength(16);
        builder.Property(user => user.TimeZone).HasMaxLength(80);
        builder.Property(user => user.RiskProfileJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        builder.Property(user => user.MetadataJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        builder.Property(user => user.TwoFactorSecret).HasMaxLength(128);
        builder.Property(user => user.RecoveryCodesJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'[]'::jsonb");
        builder.Property(user => user.DuressPasswordHash).HasMaxLength(512);
        builder.Property(user => user.LockReason).HasMaxLength(80);

        builder
            .HasOne(user => user.CompanyInstallation)
            .WithMany(company => company.Users)
            .HasForeignKey(user => user.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(user => new { user.CompanyInstallationId, user.EmailNormalized }).IsUnique();
        builder.HasIndex(user => new { user.CompanyInstallationId, user.Status });
    }
}
