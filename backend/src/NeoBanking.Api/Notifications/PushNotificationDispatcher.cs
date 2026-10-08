using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Notifications;

public sealed class PushNotificationDispatcher(
    IServiceScopeFactory scopeFactory,
    FirebasePushSender sender,
    IOptions<PushNotificationOptions> options,
    ILogger<PushNotificationDispatcher> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (options.Value.Enabled && sender.IsConfigured)
                {
                    await DispatchBatchAsync(stoppingToken);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "Push notification dispatch cycle failed.");
            }

            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        }
    }

    private async Task DispatchBatchAsync(CancellationToken cancellationToken)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<NeoBankingDbContext>();
        var now = DateTimeOffset.UtcNow;
        var notifications = await dbContext.PushNotifications
            .Where(notification =>
                (notification.Status == "pending" ||
                 notification.Status == "retry" ||
                 (notification.Status == "processing" && notification.UpdatedAt < now.AddMinutes(-5))) &&
                (notification.NextAttemptAt == null || notification.NextAttemptAt <= now) &&
                notification.AttemptCount < Math.Max(1, options.Value.MaxAttempts))
            .OrderBy(notification => notification.CreatedAt)
            .Take(25)
            .ToListAsync(cancellationToken);

        foreach (var notification in notifications)
        {
            var claimed = await dbContext.PushNotifications
                .Where(candidate =>
                    candidate.Id == notification.Id &&
                    (candidate.Status == "pending" ||
                     candidate.Status == "retry" ||
                     (candidate.Status == "processing" && candidate.UpdatedAt < now.AddMinutes(-5))))
                .ExecuteUpdateAsync(setters => setters
                    .SetProperty(candidate => candidate.Status, "processing")
                    .SetProperty(candidate => candidate.AttemptCount, candidate => candidate.AttemptCount + 1)
                    .SetProperty(candidate => candidate.UpdatedAt, now),
                    cancellationToken);
            if (claimed == 0)
            {
                continue;
            }
            notification.Status = "processing";
            notification.AttemptCount++;

            var tokens = await dbContext.PushDevices
                .Where(device =>
                    device.CompanyInstallationId == notification.CompanyInstallationId &&
                    device.UserId == notification.UserId &&
                    device.IsEnabled)
                .Select(device => device.RegistrationToken)
                .Distinct()
                .ToListAsync(cancellationToken);
            if (tokens.Count == 0)
            {
                notification.Status = "skipped";
                notification.ErrorMessage = "No active push devices were registered for the user.";
                notification.UpdatedAt = now;
                continue;
            }

            try
            {
                var data = JsonSerializer.Deserialize<Dictionary<string, string>>(notification.DataJson) ?? [];
                data["notificationId"] = notification.Id.ToString();
                var result = await sender.SendAsync(
                    tokens,
                    notification.Title,
                    notification.Body,
                    data,
                    cancellationToken);

                if (result.PermanentlyFailedTokens.Count > 0)
                {
                    await dbContext.PushDevices
                        .Where(device => result.PermanentlyFailedTokens.Contains(device.RegistrationToken))
                        .ExecuteUpdateAsync(setters => setters
                            .SetProperty(device => device.IsEnabled, false)
                            .SetProperty(device => device.UpdatedAt, now),
                            cancellationToken);
                }

                if (result.SuccessCount > 0)
                {
                    notification.Status = "sent";
                    notification.SentAt = now;
                    notification.ErrorMessage = result.FailureCount == 0
                        ? null
                        : $"Delivered to {result.SuccessCount} device(s); {result.FailureCount} target(s) failed.";
                }
                else if (result.PermanentlyFailedTokens.Count == tokens.Count)
                {
                    notification.Status = "undeliverable";
                    notification.NextAttemptAt = null;
                    notification.ErrorMessage = "Firebase rejected every registered device token permanently.";
                }
                else
                {
                    ScheduleRetry(notification, now, "Firebase did not accept the notification for any registered device.");
                }
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Push notification {NotificationId} delivery failed.", notification.Id);
                ScheduleRetry(notification, now, exception.Message);
            }
            notification.UpdatedAt = now;
        }

        await dbContext.SaveChangesAsync(cancellationToken);
    }

    private void ScheduleRetry(Domain.Entities.PushNotification notification, DateTimeOffset now, string error)
    {
        notification.ErrorMessage = error.Length <= 1000 ? error : error[..1000];
        if (notification.AttemptCount >= Math.Max(1, options.Value.MaxAttempts))
        {
            notification.Status = "failed";
            notification.NextAttemptAt = null;
            return;
        }
        notification.Status = "retry";
        notification.NextAttemptAt = now.AddSeconds(Math.Pow(2, notification.AttemptCount) * 15);
    }
}
