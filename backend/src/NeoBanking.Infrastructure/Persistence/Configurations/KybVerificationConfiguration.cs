#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class KybVerificationConfiguration : IEntityTypeConfiguration<KybVerification>
{
    public void Configure(EntityTypeBuilder<KybVerification> builder)
    {
        builder.ToTable("kyb_verifications");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(kyb => kyb.BusinessName).IsRequired().HasMaxLength(240);
        builder.Property(kyb => kyb.RegistrationNumber).HasMaxLength(120);
        builder.Property(kyb => kyb.CountryCode).IsRequired().HasMaxLength(ConfigurationDefaults.IsoCountryLength);
        builder.Property(kyb => kyb.Provider).IsRequired().HasMaxLength(ConfigurationDefaults.ProviderLength);
        builder.Property(kyb => kyb.ProviderReference).HasMaxLength(240);
        builder.Property(kyb => kyb.Status).IsRequired().HasMaxLength(ConfigurationDefaults.StatusLength);
        builder.Property(kyb => kyb.BusinessProfileJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        builder.Property(kyb => kyb.BeneficialOwnersJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'[]'::jsonb");
        builder.Property(kyb => kyb.DocumentChecksJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        builder.Property(kyb => kyb.RiskSignalsJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");

        builder
            .HasOne(kyb => kyb.CompanyInstallation)
            .WithMany()
            .HasForeignKey(kyb => kyb.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(kyb => kyb.OnboardingApplication)
            .WithMany(application => application.KybVerifications)
            .HasForeignKey(kyb => kyb.OnboardingApplicationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(kyb => new { kyb.CompanyInstallationId, kyb.Status });
        builder.HasIndex(kyb => new { kyb.CompanyInstallationId, kyb.Provider, kyb.ProviderReference });
        builder.HasIndex(kyb => new { kyb.CompanyInstallationId, kyb.RegistrationNumber });
    }
}
