#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class PushDeviceConfiguration : IEntityTypeConfiguration<PushDevice>
{
    public void Configure(EntityTypeBuilder<PushDevice> builder)
    {
        builder.ToTable("push_devices");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(device => device.RegistrationToken).IsRequired().HasMaxLength(4096);
        builder.Property(device => device.Platform).IsRequired().HasMaxLength(16);
        builder.Property(device => device.AppVersion).HasMaxLength(40);
        builder.Property(device => device.Locale).HasMaxLength(16);

        builder
            .HasOne(device => device.User)
            .WithMany(user => user.PushDevices)
            .HasForeignKey(device => device.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(device => device.RegistrationToken).IsUnique();
        builder.HasIndex(device => new { device.CompanyInstallationId, device.UserId, device.IsEnabled });
    }
}
