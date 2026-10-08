#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

internal static class ConfigurationDefaults
{
    internal const int ProviderLength = 80;
    internal const int StatusLength = 40;
    internal const int IsoCountryLength = 2;
    internal const int IsoCurrencyLength = 3;

    internal static void ConfigureEntity<T>(this EntityTypeBuilder<T> builder)
        where T : Entity
    {
        builder.HasKey(entity => entity.Id);

        builder
            .Property(entity => entity.Id)
            .ValueGeneratedNever();
    }

    internal static void ConfigureAuditableEntity<T>(this EntityTypeBuilder<T> builder)
        where T : AuditableEntity
    {
        builder.ConfigureEntity();

        builder
            .Property(entity => entity.CreatedAt)
            .IsRequired()
            .HasDefaultValueSql("now()");

        builder
            .Property(entity => entity.UpdatedAt)
            .IsRequired()
            .HasDefaultValueSql("now()");
    }

    internal static void ConfigureCompanyScopedEntity<T>(this EntityTypeBuilder<T> builder)
        where T : CompanyScopedEntity
    {
        builder.ConfigureAuditableEntity();

        builder
            .Property(entity => entity.CompanyInstallationId)
            .IsRequired();

        builder.HasIndex(entity => entity.CompanyInstallationId);
    }
}
