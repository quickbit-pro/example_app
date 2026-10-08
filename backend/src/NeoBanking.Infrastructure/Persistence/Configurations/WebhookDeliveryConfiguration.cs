#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class WebhookDeliveryConfiguration : IEntityTypeConfiguration<WebhookDelivery>
{
    public void Configure(EntityTypeBuilder<WebhookDelivery> builder)
    {
        builder.ToTable("webhook_deliveries");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(delivery => delivery.Provider).IsRequired().HasMaxLength(ConfigurationDefaults.ProviderLength);
        builder.Property(delivery => delivery.EventId).IsRequired().HasMaxLength(240);
        builder.Property(delivery => delivery.EventType).IsRequired().HasMaxLength(160);
        builder.Property(delivery => delivery.Status).IsRequired().HasMaxLength(ConfigurationDefaults.StatusLength);
        builder.Property(delivery => delivery.ResponseBody).HasMaxLength(4096);
        builder.Property(delivery => delivery.ErrorMessage).HasMaxLength(2048);
        builder.Property(delivery => delivery.IdempotencyKey).HasMaxLength(240);
        builder.Property(delivery => delivery.HeadersJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        builder.Property(delivery => delivery.PayloadJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");

        builder
            .HasOne(delivery => delivery.CompanyInstallation)
            .WithMany()
            .HasForeignKey(delivery => delivery.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(delivery => delivery.WebhookEndpoint)
            .WithMany(endpoint => endpoint.Deliveries)
            .HasForeignKey(delivery => delivery.WebhookEndpointId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(delivery => new { delivery.CompanyInstallationId, delivery.Provider, delivery.EventId }).IsUnique();
        builder.HasIndex(delivery => new { delivery.CompanyInstallationId, delivery.Status, delivery.NextAttemptAt });
        builder.HasIndex(delivery => delivery.IdempotencyKey);
    }
}
