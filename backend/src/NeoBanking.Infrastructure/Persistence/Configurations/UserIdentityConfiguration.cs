#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class UserIdentityConfiguration : IEntityTypeConfiguration<UserIdentity>
{
    public void Configure(EntityTypeBuilder<UserIdentity> builder)
    {
        builder.ToTable("user_identities");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(identity => identity.UserId).IsRequired();
        builder.Property(identity => identity.Provider).IsRequired().HasMaxLength(ConfigurationDefaults.ProviderLength);
        builder.Property(identity => identity.Subject).IsRequired().HasMaxLength(240);
        builder.Property(identity => identity.EmailAtProvider).HasMaxLength(320);
        builder.Property(identity => identity.PasswordHash).HasMaxLength(512);
        builder.Property(identity => identity.ClaimsJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");

        builder
            .HasOne(identity => identity.CompanyInstallation)
            .WithMany()
            .HasForeignKey(identity => identity.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(identity => identity.User)
            .WithMany(user => user.Identities)
            .HasForeignKey(identity => identity.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(identity => new { identity.CompanyInstallationId, identity.Provider, identity.Subject }).IsUnique();
        builder.HasIndex(identity => new { identity.UserId, identity.IsPrimary });
    }
}
