using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize]
[Route("api/v1/mobile/notifications")]
public sealed class MobileNotificationsController(NeoBankingDbContext dbContext) : ApiControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<MobileNotificationResponse>>> List(
        [FromQuery] bool unreadOnly = false,
        [FromQuery] int limit = 50,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var userId))
        {
            return Unauthorized(new { code = "notifications.user_missing", message = "The authenticated local user is missing." });
        }

        var query = dbContext.PushNotifications
            .AsNoTracking()
            .Where(notification => notification.UserId == userId);
        if (unreadOnly)
        {
            query = query.Where(notification => notification.ReadAt == null);
        }

        var notifications = await query
            .OrderByDescending(notification => notification.CreatedAt)
            .Take(Math.Clamp(limit, 1, 100))
            .Select(notification => new MobileNotificationResponse(
                notification.Id,
                notification.EventType,
                notification.Title,
                notification.Body,
                notification.Route,
                notification.DataJson,
                notification.CreatedAt,
                notification.SentAt,
                notification.ReadAt))
            .ToListAsync(cancellationToken);
        return Ok(notifications);
    }

    [HttpGet("unread-count")]
    public async Task<ActionResult<object>> UnreadCount(CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var userId))
        {
            return Unauthorized(new { code = "notifications.user_missing", message = "The authenticated local user is missing." });
        }

        var count = await dbContext.PushNotifications.CountAsync(
            notification => notification.UserId == userId && notification.ReadAt == null,
            cancellationToken);
        return Ok(new { count });
    }

    [HttpPatch("{notificationId:guid}")]
    public async Task<ActionResult<object>> SetReadState(
        Guid notificationId,
        [FromBody] SetNotificationReadStateRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var userId))
        {
            return Unauthorized(new { code = "notifications.user_missing", message = "The authenticated local user is missing." });
        }

        var notification = await dbContext.PushNotifications.SingleOrDefaultAsync(
            candidate => candidate.Id == notificationId && candidate.UserId == userId,
            cancellationToken);
        if (notification is null)
        {
            return NotFound(new { code = "notifications.not_found", message = "Notification not found." });
        }

        notification.ReadAt = request.Read ? DateTimeOffset.UtcNow : null;
        await dbContext.SaveChangesAsync(cancellationToken);
        return Ok(new { notification.Id, read = notification.ReadAt is not null, notification.ReadAt });
    }

    [HttpPost("read-all")]
    public async Task<ActionResult<object>> ReadAll(CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var userId))
        {
            return Unauthorized(new { code = "notifications.user_missing", message = "The authenticated local user is missing." });
        }

        var now = DateTimeOffset.UtcNow;
        var updated = await dbContext.PushNotifications
            .Where(notification => notification.UserId == userId && notification.ReadAt == null)
            .ExecuteUpdateAsync(
                setters => setters
                    .SetProperty(notification => notification.ReadAt, now)
                    .SetProperty(notification => notification.UpdatedAt, now),
                cancellationToken);
        return Ok(new { updated });
    }

    [HttpPost("devices")]
    public async Task<ActionResult<object>> RegisterDevice(
        [FromBody] RegisterPushDeviceRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var userId))
        {
            return Unauthorized(new { code = "notifications.user_missing", message = "The authenticated local user is missing." });
        }

        var token = request.Token?.Trim();
        var platform = request.Platform?.Trim().ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(token) || token.Length > 4096 || platform is not ("android" or "ios"))
        {
            return BadRequest(new
            {
                code = "notifications.invalid_device",
                message = "A valid Firebase token and android or ios platform are required."
            });
        }

        var user = await dbContext.Users.SingleOrDefaultAsync(candidate => candidate.Id == userId, cancellationToken);
        if (user is null)
        {
            return Unauthorized(new { code = "notifications.user_missing", message = "The authenticated user no longer exists." });
        }

        var now = DateTimeOffset.UtcNow;
        var device = await dbContext.PushDevices.SingleOrDefaultAsync(
            candidate => candidate.RegistrationToken == token,
            cancellationToken);
        if (device is null)
        {
            device = new PushDevice
            {
                CompanyInstallationId = user.CompanyInstallationId,
                UserId = user.Id,
                RegistrationToken = token,
                CreatedAt = now
            };
            dbContext.PushDevices.Add(device);
        }
        else
        {
            device.CompanyInstallationId = user.CompanyInstallationId;
            device.UserId = user.Id;
        }

        device.Platform = platform;
        device.AppVersion = Trim(request.AppVersion, 40);
        device.Locale = Trim(request.Locale, 16);
        device.IsEnabled = true;
        device.LastSeenAt = now;
        device.UpdatedAt = now;
        await dbContext.SaveChangesAsync(cancellationToken);

        return Ok(new { registered = true });
    }

    [HttpPost("devices/unregister")]
    public async Task<ActionResult<object>> UnregisterDevice(
        [FromBody] UnregisterPushDeviceRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var userId))
        {
            return Unauthorized(new { code = "notifications.user_missing", message = "The authenticated local user is missing." });
        }

        var token = request.Token?.Trim();
        if (string.IsNullOrWhiteSpace(token))
        {
            return BadRequest(new { code = "notifications.token_required", message = "The Firebase token is required." });
        }

        var device = await dbContext.PushDevices.SingleOrDefaultAsync(
            candidate => candidate.UserId == userId && candidate.RegistrationToken == token,
            cancellationToken);
        if (device is not null)
        {
            device.IsEnabled = false;
            device.UpdatedAt = DateTimeOffset.UtcNow;
            await dbContext.SaveChangesAsync(cancellationToken);
        }

        return Ok(new { unregistered = true });
    }

    private static string? Trim(string? value, int length)
    {
        var trimmed = value?.Trim();
        if (string.IsNullOrEmpty(trimmed)) return null;
        return trimmed.Length <= length ? trimmed : trimmed[..length];
    }
}

public sealed record RegisterPushDeviceRequest(string? Token, string? Platform, string? AppVersion, string? Locale);

public sealed record UnregisterPushDeviceRequest(string? Token);

public sealed record SetNotificationReadStateRequest(bool Read);

public sealed record MobileNotificationResponse(
    Guid Id,
    string EventType,
    string Title,
    string Body,
    string Route,
    string DataJson,
    DateTimeOffset CreatedAt,
    DateTimeOffset? SentAt,
    DateTimeOffset? ReadAt);
