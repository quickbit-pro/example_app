using System.Collections.Concurrent;

namespace NeoBanking.Api.Auth;

/// <summary>
/// In-memory failed-login counter: after <see cref="MaxFailures"/> failures for the
/// same email within <see cref="Window"/>, sign-in is refused for <see cref="Lockout"/>.
/// Per instance by design; the IP rate limiter covers distributed spraying.
/// </summary>
public sealed class LoginAttemptTracker
{
    public const int MaxFailures = 5;
    public static readonly TimeSpan Window = TimeSpan.FromMinutes(15);
    public static readonly TimeSpan Lockout = TimeSpan.FromMinutes(15);

    private readonly ConcurrentDictionary<string, Entry> _entries = new(StringComparer.OrdinalIgnoreCase);

    public TimeSpan? LockedFor(string key)
    {
        if (!_entries.TryGetValue(key, out var entry))
        {
            return null;
        }
        var now = DateTimeOffset.UtcNow;
        if (entry.LockedUntil is { } until && until > now)
        {
            return until - now;
        }
        return null;
    }

    public void RecordFailure(string key)
    {
        var now = DateTimeOffset.UtcNow;
        _entries.AddOrUpdate(
            key,
            _ => new Entry(1, now, null),
            (_, existing) =>
            {
                var count = now - existing.FirstFailureAt > Window ? 1 : existing.Failures + 1;
                var firstAt = count == 1 ? now : existing.FirstFailureAt;
                var lockedUntil = count >= MaxFailures ? now + Lockout : existing.LockedUntil;
                return new Entry(count, firstAt, lockedUntil);
            });

        if (_entries.Count > 10_000)
        {
            foreach (var stale in _entries.Where(pair => now - pair.Value.FirstFailureAt > Window && (pair.Value.LockedUntil ?? now) <= now).Select(pair => pair.Key).ToList())
            {
                _entries.TryRemove(stale, out _);
            }
        }
    }

    public void Reset(string key) => _entries.TryRemove(key, out _);

    private sealed record Entry(int Failures, DateTimeOffset FirstFailureAt, DateTimeOffset? LockedUntil);
}
