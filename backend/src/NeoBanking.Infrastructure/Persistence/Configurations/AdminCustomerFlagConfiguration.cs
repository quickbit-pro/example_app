#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class AdminCustomerFlagConfiguration : IEntityTypeConfiguration<AdminCustomerFlag>
{
    public void Configure(EntityTypeBuilder<AdminCustomerFlag> builder)
    {
        builder.ToTable("admin_customer_flags");
        builder.ConfigureCompanyScopedEntity();

        builder
            .HasOne(flag => flag.User)
            .WithMany()
            .HasForeignKey(flag => flag.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder
            .HasOne(flag => flag.CompanyInstallation)
            .WithMany()
            .HasForeignKey(flag => flag.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(flag => new { flag.CompanyInstallationId, flag.UserId }).IsUnique();
    }
}
