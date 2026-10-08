using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Notifications;

public sealed class PushNotificationOutbox(NeoBankingDbContext dbContext)
{
    public async Task EnqueueHoppaEventAsync(
        Guid companyInstallationId,
        Guid userId,
        string eventId,
        string eventType,
        JsonElement data,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var message = HoppaUserNotificationMapper.Map(eventType, data);
        if (message is null)
        {
            return;
        }

        await EnqueueAsync(companyInstallationId, userId, eventId, eventType, message, now, cancellationToken);
    }

    /// <summary>Queues an app-originated notification (peer transfers, requests) once per event id.</summary>
    public async Task EnqueueAsync(
        Guid companyInstallationId,
        Guid userId,
        string eventId,
        string eventType,
        UserPushMessage message,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var exists = dbContext.PushNotifications.Local.Any(notification =>
                notification.CompanyInstallationId == companyInstallationId &&
                notification.UserId == userId &&
                notification.EventId == eventId) ||
            await dbContext.PushNotifications.AnyAsync(notification =>
                notification.CompanyInstallationId == companyInstallationId &&
                notification.UserId == userId &&
                notification.EventId == eventId,
                cancellationToken);
        if (exists)
        {
            return;
        }

        dbContext.PushNotifications.Add(new PushNotification
        {
            CompanyInstallationId = companyInstallationId,
            UserId = userId,
            EventId = eventId,
            EventType = eventType,
            Title = message.Title,
            Body = message.Body,
            Route = message.Route,
            DataJson = JsonSerializer.Serialize(message.Data),
            Status = "pending",
            NextAttemptAt = now,
            CreatedAt = now,
            UpdatedAt = now
        });
    }
}
