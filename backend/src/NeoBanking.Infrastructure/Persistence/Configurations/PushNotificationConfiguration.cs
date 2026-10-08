#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class PushNotificationConfiguration : IEntityTypeConfiguration<PushNotification>
{
    public void Configure(EntityTypeBuilder<PushNotification> builder)
    {
        builder.ToTable("push_notifications");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(notification => notification.EventId).IsRequired().HasMaxLength(180);
        builder.Property(notification => notification.EventType).IsRequired().HasMaxLength(100);
        builder.Property(notification => notification.Title).IsRequired().HasMaxLength(160);
        builder.Property(notification => notification.Body).IsRequired().HasMaxLength(500);
        builder.Property(notification => notification.Route).IsRequired().HasMaxLength(240);
        builder.Property(notification => notification.DataJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
        builder.Property(notification => notification.Status).IsRequired().HasMaxLength(24);
        builder.Property(notification => notification.ErrorMessage).HasMaxLength(1000);

        builder
            .HasOne(notification => notification.User)
            .WithMany(user => user.PushNotifications)
            .HasForeignKey(notification => notification.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(notification => new
        {
            notification.CompanyInstallationId,
            notification.UserId,
            notification.EventId
        }).IsUnique();
        builder.HasIndex(notification => new { notification.Status, notification.NextAttemptAt });
        builder.HasIndex(notification => new
        {
            notification.CompanyInstallationId,
            notification.UserId,
            notification.ReadAt,
            notification.CreatedAt
        });
    }
}
