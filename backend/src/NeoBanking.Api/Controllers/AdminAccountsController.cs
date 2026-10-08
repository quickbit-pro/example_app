using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.DTOs.Auth;
using NeoBanking.Application.Security;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

/// <summary>Local account security administration: locked accounts and unlocking them.</summary>
[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/accounts")]
public sealed class AdminAccountsController(NeoBankingDbContext dbContext, ILogger<AdminAccountsController> logger) : ApiControllerBase
{
    /// <summary>A duress lock cannot be lifted before this much time has passed.</summary>
    public static readonly TimeSpan UnlockCoolingOff = TimeSpan.FromDays(2);

    [HttpGet("locked")]
    public async Task<ActionResult<IReadOnlyList<LockedAccountDto>>> ListLocked(CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }
        var users = await dbContext.Users
            .AsNoTracking()
            .Where(user => user.CompanyInstallationId == companyId && user.LockedAt != null)
            .OrderByDescending(user => user.LockedAt)
            .ToListAsync(cancellationToken);
        return Ok(users.Select(ToDto).ToList());
    }

    [HttpGet("{userId:guid}/lock")]
    public async Task<ActionResult<LockedAccountDto>> GetLock(Guid userId, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }
        var user = await dbContext.Users.AsNoTracking()
            .SingleOrDefaultAsync(candidate => candidate.Id == userId && candidate.CompanyInstallationId == companyId, cancellationToken);
        if (user is null)
        {
            return NotFound();
        }
        return user.LockedAt is null ? NoContent() : Ok(ToDto(user));
    }

    /// <summary>Lifts a lock once the cooling-off period has passed.</summary>
    [HttpPost("{userId:guid}/unlock")]
    public async Task<ActionResult<object>> Unlock(Guid userId, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Unauthorized();
        }
        var user = await dbContext.Users
            .SingleOrDefaultAsync(candidate => candidate.Id == userId && candidate.CompanyInstallationId == companyId, cancellationToken);
        if (user is null)
        {
            return NotFound();
        }
        if (user.LockedAt is null)
        {
            return Ok(new { unlocked = false, message = "This account is not locked." });
        }
        var availableAt = user.LockedAt.Value + UnlockCoolingOff;
        var now = DateTimeOffset.UtcNow;
        if (availableAt > now)
        {
            return StatusCode(StatusCodes.Status409Conflict, new
            {
                code = "admin.accounts.unlock_too_early",
                message = $"A {user.LockReason ?? "security"} lock can be lifted from {availableAt:u}.",
                unlockAvailableAt = availableAt
            });
        }

        user.LockedAt = null;
        user.LockReason = null;
        user.Status = "active";
        user.UpdatedAt = now;
        await dbContext.SaveChangesAsync(cancellationToken);
        logger.LogInformation("Admin {Admin} unlocked account {UserId}.", User.Identity?.Name, userId);
        return Ok(new { unlocked = true });
    }

    private static LockedAccountDto ToDto(Domain.Entities.ApplicationUser user) => new()
    {
        Id = user.Id,
        Email = user.Email,
        DisplayName = user.DisplayName,
        LockedAt = user.LockedAt ?? DateTimeOffset.MinValue,
        LockReason = user.LockReason,
        UnlockAvailableAt = (user.LockedAt ?? DateTimeOffset.MinValue) + UnlockCoolingOff
    };
}
