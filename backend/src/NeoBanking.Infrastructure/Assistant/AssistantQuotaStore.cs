#nullable enable

using System.Data;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Infrastructure.Assistant;

public sealed record AssistantQuotaLimits(int DailyLimit, int PerMinuteLimit, int GlobalDailyLimit, int LeaseSeconds = 60);

public enum AssistantQuotaOutcome
{
    Accepted,
    DailyLimit,
    RateLimit,
    Concurrent,
    GlobalLimit
}

public sealed record AssistantQuotaReservation(AssistantQuotaOutcome Outcome, Guid? Id, int Used);

public interface IAssistantQuotaStore
{
    Task<int> GetUsedAsync(Guid companyId, Guid userId, DateTimeOffset utcDay, CancellationToken cancellationToken);
    Task<AssistantQuotaReservation> ReserveAsync(Guid companyId, Guid userId, AssistantQuotaLimits limits, CancellationToken cancellationToken);
    Task ReleaseAsync(Guid reservationId, CancellationToken cancellationToken);
}

/// <summary>
/// Keeps limits durable across restarts and shared across API instances. All reservations use one
/// short PostgreSQL transaction lock, so user and global checks and charging are atomic together.
/// The lock is released before calling the provider; only the expiring user lease remains.
/// </summary>
public sealed class AssistantQuotaStore(NeoBankingDbContext db, TimeProvider timeProvider) : IAssistantQuotaStore
{
    public async Task<int> GetUsedAsync(Guid companyId, Guid userId, DateTimeOffset utcDay, CancellationToken cancellationToken)
    {
        EnsurePostgres();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(5));
        var start = new DateTimeOffset(utcDay.UtcDateTime.Date, TimeSpan.Zero);
        var end = start.AddDays(1);
        return await db.AssistantUsageReservations.AsNoTracking().CountAsync(reservation =>
            reservation.CompanyInstallationId == companyId && reservation.UserId == userId &&
            reservation.ReservedAt >= start && reservation.ReservedAt < end, timeout.Token);
    }

    public async Task<AssistantQuotaReservation> ReserveAsync(
        Guid companyId, Guid userId, AssistantQuotaLimits limits, CancellationToken cancellationToken)
    {
        EnsurePostgres();
        ArgumentOutOfRangeException.ThrowIfLessThan(limits.DailyLimit, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(limits.PerMinuteLimit, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(limits.GlobalDailyLimit, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(limits.LeaseSeconds, 60);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(5));
        cancellationToken = timeout.Token;

        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);
        // Fixed application-specific key. A transaction-scoped lock is released even on failure.
        await db.Database.ExecuteSqlRawAsync("SELECT pg_advisory_xact_lock(7198542843061841)", cancellationToken);

        var now = timeProvider.GetUtcNow();
        var day = new DateTimeOffset(now.UtcDateTime.Date, TimeSpan.Zero);
        var tomorrow = day.AddDays(1);
        var minute = now.AddMinutes(-1);
        var userReservations = db.AssistantUsageReservations.AsNoTracking().Where(reservation =>
            reservation.CompanyInstallationId == companyId && reservation.UserId == userId);
        var used = await userReservations.CountAsync(reservation =>
            reservation.ReservedAt >= day && reservation.ReservedAt < tomorrow, cancellationToken);

        if (used >= limits.DailyLimit)
            return new(AssistantQuotaOutcome.DailyLimit, null, used);

        var globalUsed = await db.AssistantUsageReservations.CountAsync(reservation =>
            reservation.ReservedAt >= day && reservation.ReservedAt < tomorrow, cancellationToken);
        if (globalUsed >= limits.GlobalDailyLimit)
            return new(AssistantQuotaOutcome.GlobalLimit, null, used);

        if (await userReservations.AnyAsync(reservation => reservation.ActiveUntil > now, cancellationToken))
            return new(AssistantQuotaOutcome.Concurrent, null, used);

        var minuteUsed = await userReservations.CountAsync(reservation => reservation.ReservedAt > minute, cancellationToken);
        if (minuteUsed >= limits.PerMinuteLimit)
            return new(AssistantQuotaOutcome.RateLimit, null, used);

        // Retain enough history for daily/minute checks and a short operational audit, without
        // accumulating a permanent activity history. The ReservedAt index also serves cleanup.
        var retentionCutoff = day.AddDays(-7);
        await db.AssistantUsageReservations.Where(reservation =>
                reservation.ReservedAt < retentionCutoff &&
                (reservation.ActiveUntil == null || reservation.ActiveUntil <= now))
            .ExecuteDeleteAsync(cancellationToken);

        var reservation = new AssistantUsageReservation
        {
            CompanyInstallationId = companyId,
            UserId = userId,
            ReservedAt = now,
            ActiveUntil = now.AddSeconds(limits.LeaseSeconds)
        };
        db.AssistantUsageReservations.Add(reservation);
        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new(AssistantQuotaOutcome.Accepted, reservation.Id, used + 1);
    }

    public async Task ReleaseAsync(Guid reservationId, CancellationToken cancellationToken)
    {
        EnsurePostgres();
        using var cleanupTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cleanupTimeout.CancelAfter(TimeSpan.FromSeconds(5));
        // A failed, cancelled or refused answer still counts. Only its concurrency lease is freed.
        await db.AssistantUsageReservations.Where(reservation => reservation.Id == reservationId)
            .ExecuteUpdateAsync(update => update.SetProperty(reservation => reservation.ActiveUntil, (DateTimeOffset?)null),
                cleanupTimeout.Token);
    }

    private void EnsurePostgres()
    {
        if (!db.Database.IsNpgsql())
            throw new InvalidOperationException("Assistant quotas require PostgreSQL for atomic, durable enforcement.");
    }
}
