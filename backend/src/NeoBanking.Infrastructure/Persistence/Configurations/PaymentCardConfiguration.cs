#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class PaymentCardConfiguration : IEntityTypeConfiguration<PaymentCard>
{
    public void Configure(EntityTypeBuilder<PaymentCard> builder)
    {
        builder.ToTable("cards");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(card => card.Provider).IsRequired().HasMaxLength(ConfigurationDefaults.ProviderLength);
        builder.Property(card => card.ProviderCardId).IsRequired().HasMaxLength(240);
        builder.Property(card => card.Status).IsRequired().HasMaxLength(ConfigurationDefaults.StatusLength);
        builder.Property(card => card.CardType).IsRequired().HasMaxLength(40);
        builder.Property(card => card.LastFour).IsRequired().HasMaxLength(4);
        builder.Property(card => card.Bin).HasMaxLength(8);
        builder.Property(card => card.Currency).IsRequired().HasMaxLength(ConfigurationDefaults.IsoCurrencyLength);
        builder.Property(card => card.SpendingControlsJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        builder.Property(card => card.BillingAddressJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");

        builder
            .HasOne(card => card.CompanyInstallation)
            .WithMany()
            .HasForeignKey(card => card.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(card => card.User)
            .WithMany(user => user.Cards)
            .HasForeignKey(card => card.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(card => new { card.CompanyInstallationId, card.Provider, card.ProviderCardId }).IsUnique();
        builder.HasIndex(card => new { card.CompanyInstallationId, card.UserId, card.Status });
        builder.HasIndex(card => new { card.CompanyInstallationId, card.LastFour });
    }
}
