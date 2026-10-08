#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class AssistantUsageReservationConfiguration : IEntityTypeConfiguration<AssistantUsageReservation>
{
    public void Configure(EntityTypeBuilder<AssistantUsageReservation> builder)
    {
        builder.ToTable("assistant_usage_reservations");
        builder.ConfigureEntity();

        builder.HasOne<CompanyInstallation>().WithMany()
            .HasForeignKey(reservation => reservation.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Restrict);
        builder.HasOne<ApplicationUser>().WithMany()
            .HasForeignKey(reservation => reservation.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(reservation => new { reservation.CompanyInstallationId, reservation.UserId, reservation.ReservedAt });
        builder.HasIndex(reservation => new { reservation.CompanyInstallationId, reservation.UserId, reservation.ActiveUntil });
        builder.HasIndex(reservation => reservation.ReservedAt);
    }
}
