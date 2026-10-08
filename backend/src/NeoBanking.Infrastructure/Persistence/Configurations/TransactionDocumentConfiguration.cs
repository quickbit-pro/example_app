using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;
namespace NeoBanking.Infrastructure.Persistence.Configurations;
public sealed class TransactionDocumentConfiguration : IEntityTypeConfiguration<TransactionDocument>
{
    public void Configure(EntityTypeBuilder<TransactionDocument> b)
    {
        b.ToTable("transaction_documents"); b.ConfigureCompanyScopedEntity();
        b.Property(x => x.TransactionId).HasMaxLength(200).IsRequired();
        b.HasOne(x => x.CompanyInstallation).WithMany().HasForeignKey(x => x.CompanyInstallationId).OnDelete(DeleteBehavior.Restrict);
        b.HasOne<ApplicationUser>().WithMany().HasForeignKey(x => x.OwnerUserId).OnDelete(DeleteBehavior.Restrict);
        b.HasOne(x => x.Document).WithMany().HasForeignKey(x => x.DocumentId).OnDelete(DeleteBehavior.Restrict);
        b.HasIndex(x => new { x.CompanyInstallationId, x.OwnerUserId, x.TransactionId, x.DocumentId }).IsUnique();
    }
}
