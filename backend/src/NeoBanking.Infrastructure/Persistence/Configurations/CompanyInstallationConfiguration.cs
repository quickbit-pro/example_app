#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class CompanyInstallationConfiguration : IEntityTypeConfiguration<CompanyInstallation>
{
    public void Configure(EntityTypeBuilder<CompanyInstallation> builder)
    {
        builder.ToTable("company_installations");
        builder.ConfigureAuditableEntity();

        builder.Property(company => company.Slug).IsRequired().HasMaxLength(80);
        builder.Property(company => company.LegalName).IsRequired().HasMaxLength(240);
        builder.Property(company => company.DisplayName).IsRequired().HasMaxLength(160);
        builder.Property(company => company.Status).IsRequired().HasMaxLength(ConfigurationDefaults.StatusLength);
        builder.Property(company => company.CountryCode).IsRequired().HasMaxLength(ConfigurationDefaults.IsoCountryLength);
        builder.Property(company => company.DefaultCurrency).IsRequired().HasMaxLength(ConfigurationDefaults.IsoCurrencyLength);
        builder.Property(company => company.SettingsJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");

        builder.HasIndex(company => company.Slug).IsUnique();
        builder.HasIndex(company => company.Status);
    }
}
