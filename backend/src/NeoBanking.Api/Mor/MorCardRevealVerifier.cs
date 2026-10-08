using System.Security.Claims;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Auth;
using NeoBanking.Application.Common;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Mor;

public interface IMorCardRevealVerifier
{
    Task<ApplicationError?> Verify(ClaimsPrincipal caller, string password, string? code, CancellationToken ct);
}

// The public card-widget API delegates step-up verification to its backend client.
// Reuse this installation's password/TOTP mechanisms; never forward credentials.
public sealed class MorCardRevealVerifier(NeoBankingDbContext db, PasswordHasher<ApplicationUser> passwords,
    LoginAttemptTracker attempts) : IMorCardRevealVerifier
{
    public async Task<ApplicationError?> Verify(ClaimsPrincipal caller, string password, string? code, CancellationToken ct)
    {
        if (!Guid.TryParse(caller.FindFirstValue("local_user_id") ?? caller.FindFirstValue("sub"), out var localId))
            return new("mor.reveal.identity", "Sign in again before revealing card details.", 401);
        var key = $"mor-reveal:{localId}";
        if (attempts.LockedFor(key) is not null) return new("mor.reveal.locked", "Too many verification attempts. Try again later.", 429);
        var identity = await db.UserIdentities.Include(i => i.User).SingleOrDefaultAsync(i => i.UserId == localId && i.Provider == "local", ct);
        if (identity?.User is not { } user || user.LockedAt is not null || string.IsNullOrEmpty(identity.PasswordHash))
            return new("mor.reveal.denied", "Unable to verify this account.", 403);
        if (passwords.VerifyHashedPassword(user, identity.PasswordHash, password) == PasswordVerificationResult.Failed ||
            (user.TwoFactorEnabled && (string.IsNullOrEmpty(user.TwoFactorSecret) || !Totp.Verify(user.TwoFactorSecret, code))))
        {
            attempts.RecordFailure(key);
            return new("mor.reveal.invalid", "Your password or authenticator code is incorrect.", 403);
        }
        attempts.Reset(key);
        return null;
    }
}
