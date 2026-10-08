#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class ProviderMappingConfiguration : IEntityTypeConfiguration<ProviderMapping>
{
    public void Configure(EntityTypeBuilder<ProviderMapping> builder)
    {
        builder.ToTable("provider_mappings");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(mapping => mapping.Provider).IsRequired().HasMaxLength(ConfigurationDefaults.ProviderLength);
        builder.Property(mapping => mapping.ProviderEntityType).IsRequired().HasMaxLength(80);
        builder.Property(mapping => mapping.ProviderEntityId).IsRequired().HasMaxLength(240);
        builder.Property(mapping => mapping.InternalEntityType).IsRequired().HasMaxLength(80);
        builder.Property(mapping => mapping.InternalEntityId).IsRequired();
        builder.Property(mapping => mapping.ExternalStatus).IsRequired().HasMaxLength(ConfigurationDefaults.StatusLength);
        builder.Property(mapping => mapping.SyncStateJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");

        builder
            .HasOne(mapping => mapping.CompanyInstallation)
            .WithMany(company => company.ProviderMappings)
            .HasForeignKey(mapping => mapping.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasIndex(mapping => new
            {
                mapping.CompanyInstallationId,
                mapping.Provider,
                mapping.ProviderEntityType,
                mapping.ProviderEntityId
            })
            .IsUnique();

        builder.HasIndex(mapping => new { mapping.CompanyInstallationId, mapping.InternalEntityType, mapping.InternalEntityId });
    }
}
