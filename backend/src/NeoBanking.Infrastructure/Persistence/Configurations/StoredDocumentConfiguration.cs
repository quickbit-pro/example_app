using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;
namespace NeoBanking.Infrastructure.Persistence.Configurations;
public sealed class StoredDocumentConfiguration : IEntityTypeConfiguration<StoredDocument>
{
    public void Configure(EntityTypeBuilder<StoredDocument> b)
    {
        b.ToTable("stored_documents"); b.ConfigureCompanyScopedEntity();
        b.Property(x => x.BlobKey).HasMaxLength(200).IsRequired();
        b.Property(x => x.FileName).HasMaxLength(160).IsRequired();
        b.Property(x => x.ContentType).HasMaxLength(80).IsRequired();
        b.Property(x => x.Sha256).HasMaxLength(64).IsRequired();
        b.HasOne(x => x.CompanyInstallation).WithMany().HasForeignKey(x => x.CompanyInstallationId).OnDelete(DeleteBehavior.Restrict);
        b.HasOne<ApplicationUser>().WithMany().HasForeignKey(x => x.OwnerUserId).OnDelete(DeleteBehavior.Restrict);
        b.HasIndex(x => new { x.CompanyInstallationId, x.OwnerUserId, x.Sha256 }).IsUnique();
    }
}
