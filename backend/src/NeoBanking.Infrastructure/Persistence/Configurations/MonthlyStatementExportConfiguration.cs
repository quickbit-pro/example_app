using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;
namespace NeoBanking.Infrastructure.Persistence.Configurations;
public sealed class MonthlyStatementExportConfiguration : IEntityTypeConfiguration<MonthlyStatementExport>
{
    public void Configure(EntityTypeBuilder<MonthlyStatementExport> b)
    {
        b.ToTable("monthly_statement_exports"); b.ConfigureCompanyScopedEntity();
        b.Property(x => x.ProviderUserId).HasMaxLength(200).IsRequired();
        b.Property(x => x.Status).HasMaxLength(20).IsRequired();
        b.Property(x => x.BlobKey).HasMaxLength(200).IsRequired();
        b.Property(x => x.ErrorMessage).HasMaxLength(500).IsRequired();
        b.HasOne(x => x.CompanyInstallation).WithMany().HasForeignKey(x => x.CompanyInstallationId).OnDelete(DeleteBehavior.Restrict);
        b.HasOne<ApplicationUser>().WithMany().HasForeignKey(x => x.OwnerUserId).OnDelete(DeleteBehavior.Restrict);
        b.HasIndex(x => new { x.CompanyInstallationId, x.OwnerUserId, x.CreatedAt });
        b.HasIndex(x => new { x.Status, x.UpdatedAt });
        b.HasIndex(x => new { x.CompanyInstallationId, x.OwnerUserId }).IsUnique().HasFilter("\"Status\" IN ('queued', 'processing')");
    }
}
