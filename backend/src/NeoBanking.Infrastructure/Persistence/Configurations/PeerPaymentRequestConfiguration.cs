#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class PeerPaymentRequestConfiguration : IEntityTypeConfiguration<PeerPaymentRequest>
{
    public void Configure(EntityTypeBuilder<PeerPaymentRequest> builder)
    {
        builder.ToTable("peer_payment_requests");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(request => request.Amount).HasColumnType("numeric(24,8)");
        builder.Property(request => request.Currency).IsRequired().HasMaxLength(8);
        builder.Property(request => request.Note).HasMaxLength(250);
        builder.Property(request => request.Status).IsRequired().HasMaxLength(32);

        builder
            .HasOne(request => request.CompanyInstallation)
            .WithMany()
            .HasForeignKey(request => request.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(request => request.Requester)
            .WithMany()
            .HasForeignKey(request => request.RequesterUserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder
            .HasOne(request => request.Payer)
            .WithMany()
            .HasForeignKey(request => request.PayerUserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(request => new { request.CompanyInstallationId, request.PayerUserId, request.Status });
        builder.HasIndex(request => new { request.CompanyInstallationId, request.RequesterUserId, request.Status });
    }
}
