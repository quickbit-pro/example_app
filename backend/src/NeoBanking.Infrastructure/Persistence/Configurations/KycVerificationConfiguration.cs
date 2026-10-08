#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class KycVerificationConfiguration : IEntityTypeConfiguration<KycVerification>
{
    public void Configure(EntityTypeBuilder<KycVerification> builder)
    {
        builder.ToTable("kyc_verifications");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(kyc => kyc.Provider).IsRequired().HasMaxLength(ConfigurationDefaults.ProviderLength);
        builder.Property(kyc => kyc.ProviderReference).HasMaxLength(240);
        builder.Property(kyc => kyc.Status).IsRequired().HasMaxLength(ConfigurationDefaults.StatusLength);
        builder.Property(kyc => kyc.Level).IsRequired().HasMaxLength(40);
        builder.Property(kyc => kyc.CountryCode).IsRequired().HasMaxLength(ConfigurationDefaults.IsoCountryLength);
        builder.Property(kyc => kyc.ApplicantDataJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        builder.Property(kyc => kyc.DocumentChecksJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        builder.Property(kyc => kyc.RiskSignalsJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");

        builder
            .HasOne(kyc => kyc.CompanyInstallation)
            .WithMany()
            .HasForeignKey(kyc => kyc.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(kyc => kyc.User)
            .WithMany(user => user.KycVerifications)
            .HasForeignKey(kyc => kyc.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(kyc => kyc.OnboardingApplication)
            .WithMany(application => application.KycVerifications)
            .HasForeignKey(kyc => kyc.OnboardingApplicationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(kyc => new { kyc.CompanyInstallationId, kyc.UserId, kyc.Status });
        builder.HasIndex(kyc => new { kyc.CompanyInstallationId, kyc.Provider, kyc.ProviderReference });
    }
}
