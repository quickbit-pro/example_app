#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class OnboardingApplicationConfiguration : IEntityTypeConfiguration<OnboardingApplication>
{
    public void Configure(EntityTypeBuilder<OnboardingApplication> builder)
    {
        builder.ToTable("onboarding_applications");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(application => application.Kind).IsRequired().HasMaxLength(40);
        builder.Property(application => application.Status).IsRequired().HasMaxLength(ConfigurationDefaults.StatusLength);
        builder.Property(application => application.CurrentStep).IsRequired().HasMaxLength(120);
        builder.Property(application => application.FormDataJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        builder.Property(application => application.DecisionJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        builder.Property(application => application.MetadataJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");

        builder
            .HasOne(application => application.CompanyInstallation)
            .WithMany(company => company.OnboardingApplications)
            .HasForeignKey(application => application.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(application => application.ApplicantUser)
            .WithMany()
            .HasForeignKey(application => application.ApplicantUserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(application => new { application.CompanyInstallationId, application.Kind, application.Status });
        builder.HasIndex(application => application.ApplicantUserId);
    }
}
