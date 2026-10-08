#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class WebhookEndpointConfiguration : IEntityTypeConfiguration<WebhookEndpoint>
{
    public void Configure(EntityTypeBuilder<WebhookEndpoint> builder)
    {
        builder.ToTable("webhook_endpoints");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(endpoint => endpoint.Provider).IsRequired().HasMaxLength(ConfigurationDefaults.ProviderLength);
        builder.Property(endpoint => endpoint.Url).IsRequired().HasMaxLength(1024);
        builder.Property(endpoint => endpoint.Description).HasMaxLength(240);
        builder.Property(endpoint => endpoint.SecretHash).IsRequired().HasMaxLength(128);
        builder.Property(endpoint => endpoint.Status).IsRequired().HasMaxLength(ConfigurationDefaults.StatusLength);
        builder.Property(endpoint => endpoint.EventTypesJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'[]'::jsonb");
        builder.Property(endpoint => endpoint.HeadersJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");

        builder
            .HasOne(endpoint => endpoint.CompanyInstallation)
            .WithMany(company => company.WebhookEndpoints)
            .HasForeignKey(endpoint => endpoint.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(endpoint => new { endpoint.CompanyInstallationId, endpoint.Provider, endpoint.Url }).IsUnique();
        builder.HasIndex(endpoint => new { endpoint.CompanyInstallationId, endpoint.Status });
    }
}
