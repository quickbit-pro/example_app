#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class MarketRateSnapshotConfiguration : IEntityTypeConfiguration<MarketRateSnapshot>
{
    public void Configure(EntityTypeBuilder<MarketRateSnapshot> builder)
    {
        builder.ToTable("market_rate_snapshots");
        builder.ConfigureAuditableEntity();

        builder.Property(rate => rate.BaseCurrency)
            .IsRequired()
            .HasMaxLength(ConfigurationDefaults.IsoCurrencyLength);
        builder.Property(rate => rate.QuoteCurrency)
            .IsRequired()
            .HasMaxLength(12);
        builder.Property(rate => rate.Rate)
            .IsRequired()
            .HasPrecision(28, 12);
        builder.Property(rate => rate.Provider)
            .IsRequired()
            .HasMaxLength(ConfigurationDefaults.ProviderLength);
        builder.Property(rate => rate.ObservedAt).IsRequired();

        builder.HasIndex(rate => new
        {
            rate.BaseCurrency,
            rate.QuoteCurrency,
            rate.Provider,
            rate.ObservedAt
        }).IsUnique();

        builder.HasIndex(rate => new
        {
            rate.BaseCurrency,
            rate.QuoteCurrency,
            rate.ObservedAt
        });
    }
}
