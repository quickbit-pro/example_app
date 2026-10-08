using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Admin;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Admin;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

/// <summary>
/// Everything a support agent needs about one customer in a single read-only call:
/// account and sign-in state, sessions and devices, tickets, messages we sent,
/// peer transfers, verification and onboarding history, audit trail and recent
/// provider failures. Company scoped like <see cref="AdminOperationsController"/>.
/// </summary>
[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/customers")]
public sealed class AdminCustomerSupportController(NeoBankingDbContext dbContext) : ApiControllerBase
{
    [HttpGet("{userId:guid}/referrals")]
    public async Task<ActionResult<System.Text.Json.JsonElement?>> Referrals(Guid userId,
        [FromServices] NeoBanking.Application.UseCases.Hoppa.IProxyHoppaRequestUseCase proxy,
        [FromQuery] string? direction, [FromQuery] long? afterId, [FromQuery] int pageSize = 50,
        CancellationToken ct = default)
    {
        if (!TryGetCompanyInstallationId(out var companyId)) return Unauthorized();
        if (!await dbContext.Users.AnyAsync(x => x.Id == userId && x.CompanyInstallationId == companyId && x.AdminProfile == null, ct))
            return NotFound();
        var mapping = await dbContext.ProviderMappings.AsNoTracking().Where(x =>
            x.CompanyInstallationId == companyId && x.Provider == "hoppa" && x.ProviderEntityType == "user" &&
            x.InternalEntityType == "user" && x.InternalEntityId == userId).Select(x => x.ProviderEntityId).SingleOrDefaultAsync(ct);
        if (!int.TryParse(mapping, out var providerId) || providerId <= 0)
            return NotFound(new { code = "referrals.customer_mapping_missing", message = "This customer is not linked to a referral account." });
        return ToActionResult(await proxy.ExecuteAsync(new NeoBanking.Application.UseCases.Hoppa.ProxyHoppaRequestCommand<object?>
        {
            Method = HttpMethod.Get, UpstreamPath = $"/api/v2/referrals/users/{providerId}/relationships",
            Query = Query(("direction",direction),("afterId",afterId),("pageSize",Math.Clamp(pageSize,1,200))),
            FailureCode = "admin.referrals.customer_failed", FailureMessage = "Unable to load customer referrals."
        }, ct));
    }

    private const int SessionLimit = 10;
    private const int DeviceLimit = 10;
    private const int TicketLimit = 10;
    private const int NotificationLimit = 20;
    private const int PeerTransferLimit = 10;
    private const int VerificationLimit = 20;
    private const int OnboardingApplicationLimit = 20;
    private const int AuditLimit = 25;
    private const int ApiFailureLimit = 10;

    [HttpGet("{userId:guid}/support")]
    public async Task<ActionResult<CustomerSupportResponse>> GetSupport(Guid userId, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return Problem(
                statusCode: StatusCodes.Status401Unauthorized,
                title: "Company context is missing",
                detail: "Sign in again to continue.");
        }

        var user = await dbContext.Users
            .AsNoTracking()
            .Include(candidate => candidate.Identities)
            .SingleOrDefaultAsync(candidate =>
                candidate.Id == userId &&
                candidate.CompanyInstallationId == companyId &&
                candidate.AdminProfile == null, cancellationToken);
        if (user is null)
        {
            return NotFound(new { message = "Customer was not found." });
        }

        var now = DateTimeOffset.UtcNow;

        var snapshot = await dbContext.AdminCustomerSnapshots
            .AsNoTracking()
            .Where(candidate => candidate.CompanyInstallationId == companyId && candidate.UserId == userId)
            .Select(candidate => new
            {
                candidate.CompletedTransactionCount30d,
                candidate.TransactionInflow30dJson,
                candidate.TransactionOutflow30dJson,
                candidate.LastTransactionAt,
                candidate.LastActivityAt
            })
            .FirstOrDefaultAsync(cancellationToken);

        var sessionQuery = dbContext.RefreshSessions
            .AsNoTracking()
            .Where(session => session.CompanyInstallationId == companyId && session.UserId == userId);
        var activeSessionCount = await sessionQuery
            .CountAsync(session => session.RevokedAt == null && session.ExpiresAt > now, cancellationToken);
        var sessions = await sessionQuery
            .OrderByDescending(session => session.LastUsedAt ?? session.CreatedAt)
            .ThenByDescending(session => session.Id)
            .Take(SessionLimit)
            .Select(session => new CustomerSupportSession(
                session.Id,
                session.DeviceName,
                session.IpAddress,
                session.UserAgent,
                session.CreatedAt,
                session.LastUsedAt,
                session.ExpiresAt,
                session.RevokedAt,
                session.RevocationReason))
            .ToListAsync(cancellationToken);

        var devices = await dbContext.PushDevices
            .AsNoTracking()
            .Where(device => device.CompanyInstallationId == companyId && device.UserId == userId)
            .OrderByDescending(device => device.LastSeenAt)
            .ThenByDescending(device => device.Id)
            .Take(DeviceLimit)
            .Select(device => new CustomerSupportDevice(
                device.Id,
                device.Platform,
                device.AppVersion,
                device.Locale,
                device.IsEnabled,
                device.LastSeenAt))
            .ToListAsync(cancellationToken);

        var ticketQuery = dbContext.SupportTickets
            .AsNoTracking()
            .Where(ticket => ticket.CompanyInstallationId == companyId && ticket.UserId == userId);
        var ticketCounts = await ticketQuery
            .GroupBy(ticket => ticket.Status)
            .Select(group => new { Status = group.Key, Count = group.Count() })
            .ToListAsync(cancellationToken);
        var tickets = await ticketQuery
            .OrderByDescending(ticket => ticket.UpdatedAt)
            .ThenByDescending(ticket => ticket.Id)
            .Take(TicketLimit)
            .Select(ticket => new
            {
                ticket.Id,
                ticket.Subject,
                ticket.Status,
                ticket.CreatedAt,
                ticket.UpdatedAt,
                MessageCount = ticket.Messages.Count(),
                LastMessage = ticket.Messages
                    .OrderByDescending(message => message.CreatedAt)
                    .ThenByDescending(message => message.Id)
                    .Select(message => new { message.CreatedAt, message.IsAdmin })
                    .FirstOrDefault()
            })
            .ToListAsync(cancellationToken);

        var pushNotifications = await dbContext.PushNotifications
            .AsNoTracking()
            .Where(notification => notification.CompanyInstallationId == companyId && notification.UserId == userId)
            .OrderByDescending(notification => notification.CreatedAt)
            .ThenByDescending(notification => notification.Id)
            .Take(NotificationLimit)
            .Select(notification => new CustomerSupportNotification(
                notification.Id,
                "push",
                notification.Title,
                notification.Status,
                notification.CreatedAt,
                notification.SentAt,
                notification.ReadAt,
                notification.ErrorMessage,
                notification.AttemptCount,
                notification.EventType,
                null))
            .ToListAsync(cancellationToken);

        var emails = await dbContext.EmailMessages
            .AsNoTracking()
            .Where(email => email.CompanyInstallationId == companyId && email.UserId == userId)
            .OrderByDescending(email => email.CreatedAt)
            .ThenByDescending(email => email.Id)
            .Take(NotificationLimit)
            .Select(email => new CustomerSupportNotification(
                email.Id,
                "email",
                email.Subject,
                email.Status,
                email.CreatedAt,
                email.SentAt,
                null,
                email.ErrorMessage,
                email.AttemptCount,
                null,
                email.TemplateKey))
            .ToListAsync(cancellationToken);

        var peerTransfers = await dbContext.PeerTransfers
            .AsNoTracking()
            .Where(transfer =>
                transfer.CompanyInstallationId == companyId &&
                (transfer.SenderUserId == userId || transfer.RecipientUserId == userId))
            .OrderByDescending(transfer => transfer.CreatedAt)
            .ThenByDescending(transfer => transfer.Id)
            .Take(PeerTransferLimit)
            .Select(transfer => new
            {
                transfer.Id,
                transfer.SenderUserId,
                transfer.Amount,
                transfer.Currency,
                transfer.Status,
                transfer.Note,
                transfer.ErrorCode,
                transfer.ErrorMessage,
                transfer.ExternalReferenceId,
                transfer.CreatedAt,
                transfer.CompletedAt,
                SenderName = transfer.Sender == null ? null : (transfer.Sender.DisplayName ?? transfer.Sender.Email),
                RecipientName = transfer.Recipient == null ? null : (transfer.Recipient.DisplayName ?? transfer.Recipient.Email)
            })
            .ToListAsync(cancellationToken);

        var onboardingApplications = await dbContext.OnboardingApplications
            .AsNoTracking()
            .Where(application => application.CompanyInstallationId == companyId && application.ApplicantUserId == userId)
            .OrderByDescending(application => application.CreatedAt)
            .ThenByDescending(application => application.Id)
            .Take(OnboardingApplicationLimit)
            .Select(application => new CustomerSupportOnboardingApplication(
                application.Id,
                application.Kind,
                application.Status,
                application.CurrentStep,
                application.WorkflowVersion,
                application.CreatedAt,
                application.UpdatedAt,
                application.SubmittedAt,
                application.CompletedAt))
            .ToListAsync(cancellationToken);
        var applicationIds = onboardingApplications.Select(application => application.Id).ToArray();

        var kycVerifications = await dbContext.KycVerifications
            .AsNoTracking()
            .Where(verification => verification.CompanyInstallationId == companyId && verification.UserId == userId)
            .OrderByDescending(verification => verification.StartedAt)
            .ThenByDescending(verification => verification.Id)
            .Take(VerificationLimit)
            .Select(verification => new CustomerSupportVerification(
                verification.Id,
                "kyc",
                verification.Provider,
                verification.ProviderReference,
                verification.Status,
                verification.Level,
                verification.CountryCode,
                verification.StartedAt,
                verification.SubmittedAt,
                verification.ReviewedAt,
                verification.ExpiresAt,
                null))
            .ToListAsync(cancellationToken);

        var kybVerifications = applicationIds.Length == 0
            ? []
            : await dbContext.KybVerifications
                .AsNoTracking()
                .Where(verification =>
                    verification.CompanyInstallationId == companyId &&
                    verification.OnboardingApplicationId != null &&
                    applicationIds.Contains(verification.OnboardingApplicationId.Value))
                .OrderByDescending(verification => verification.CreatedAt)
                .ThenByDescending(verification => verification.Id)
                .Take(VerificationLimit)
                .Select(verification => new CustomerSupportVerification(
                    verification.Id,
                    "kyb",
                    verification.Provider,
                    verification.ProviderReference,
                    verification.Status,
                    null,
                    verification.CountryCode,
                    verification.CreatedAt,
                    verification.SubmittedAt,
                    verification.ReviewedAt,
                    verification.ExpiresAt,
                    verification.BusinessName))
                .ToListAsync(cancellationToken);

        var auditTrail = await dbContext.AuditLogEntries
            .AsNoTracking()
            .Where(entry => entry.CompanyInstallationId == companyId && entry.ActorUserId == userId)
            .OrderByDescending(entry => entry.OccurredAt)
            .ThenByDescending(entry => entry.Id)
            .Take(AuditLimit)
            .Select(entry => new CustomerSupportAuditEntry(
                entry.Id,
                entry.Action,
                entry.EntityType,
                entry.EntityId,
                entry.OccurredAt,
                entry.IpAddress,
                entry.UserAgent))
            .ToListAsync(cancellationToken);

        var failedCallQuery = dbContext.HoppaApiCallLogs
            .AsNoTracking()
            .Where(entry => entry.CompanyInstallationId == companyId && entry.ActorUserId == userId && !entry.Succeeded);
        var last24h = now.AddHours(-24);
        var last7d = now.AddDays(-7);
        var failedLast24h = await failedCallQuery.CountAsync(entry => entry.OccurredAt >= last24h, cancellationToken);
        var failedLast7d = await failedCallQuery.CountAsync(entry => entry.OccurredAt >= last7d, cancellationToken);
        var recentFailures = await failedCallQuery
            .OrderByDescending(entry => entry.OccurredAt)
            .ThenByDescending(entry => entry.Id)
            .Take(ApiFailureLimit)
            .Select(entry => new CustomerSupportApiCallFailure(
                entry.Id,
                entry.OccurredAt,
                entry.AppMethod,
                entry.AppPath,
                entry.AppStatusCode,
                entry.HoppaMethod,
                entry.HoppaEndpoint,
                entry.HoppaStatusCode,
                entry.HoppaDurationMs,
                entry.FailureCode,
                entry.FailureMessage,
                entry.TraceId))
            .ToListAsync(cancellationToken);

        var response = new CustomerSupportResponse(
            now,
            ToAccount(user, now),
            new CustomerSupportActivity(
                snapshot?.CompletedTransactionCount30d ?? 0,
                CurrencyRows(snapshot?.TransactionInflow30dJson),
                CurrencyRows(snapshot?.TransactionOutflow30dJson),
                snapshot?.LastTransactionAt,
                snapshot?.LastActivityAt),
            new CustomerSupportSessions(activeSessionCount, sessions),
            devices,
            new CustomerSupportTickets(
                ticketCounts.Sum(group => group.Count),
                ticketCounts.Where(group => group.Status == SupportTicketStatuses.AwaitingSupport).Sum(group => group.Count),
                tickets.Select(ticket => new CustomerSupportTicket(
                    ticket.Id,
                    ticket.Subject,
                    ticket.Status,
                    ticket.CreatedAt,
                    ticket.UpdatedAt,
                    ticket.MessageCount,
                    ticket.LastMessage?.CreatedAt,
                    ticket.LastMessage?.IsAdmin ?? false)).ToArray()),
            pushNotifications.Concat(emails)
                .OrderByDescending(notification => notification.CreatedAt)
                .ThenByDescending(notification => notification.Id)
                .Take(NotificationLimit)
                .ToArray(),
            peerTransfers.Select(transfer =>
            {
                var sent = transfer.SenderUserId == userId;
                return new CustomerSupportPeerTransfer(
                    transfer.Id,
                    sent ? "sent" : "received",
                    (sent ? transfer.RecipientName : transfer.SenderName) ?? "Unknown customer",
                    transfer.Amount,
                    transfer.Currency,
                    transfer.Status,
                    transfer.Note,
                    transfer.ErrorCode,
                    transfer.ErrorMessage,
                    transfer.ExternalReferenceId,
                    transfer.CreatedAt,
                    transfer.CompletedAt);
            }).ToArray(),
            kycVerifications.Concat(kybVerifications)
                .OrderByDescending(verification => verification.StartedAt)
                .ThenByDescending(verification => verification.Id)
                .ToArray(),
            onboardingApplications,
            auditTrail,
            new CustomerSupportApiCalls(failedLast24h, failedLast7d, recentFailures));

        return Ok(response);
    }

    private static CustomerSupportAccount ToAccount(ApplicationUser user, DateTimeOffset now)
    {
        CustomerSupportLock? accountLock = null;
        if (user.LockedAt is { } lockedAt)
        {
            var unlockAvailableAt = lockedAt + AdminAccountsController.UnlockCoolingOff;
            accountLock = new CustomerSupportLock(lockedAt, user.LockReason, unlockAvailableAt, unlockAvailableAt <= now);
        }

        var signInMethods = user.Identities
            .OrderByDescending(identity => identity.IsPrimary)
            .ThenBy(identity => identity.Provider, StringComparer.OrdinalIgnoreCase)
            .Select(identity => new CustomerSupportSignInMethod(
                identity.Provider,
                identity.EmailAtProvider,
                identity.IsPrimary,
                identity.LastAuthenticatedAt))
            .ToArray();

        return new CustomerSupportAccount(
            user.DisplayName ?? user.Email,
            user.Email,
            user.EmailVerifiedAt,
            user.PhoneNumber,
            user.Status,
            user.Locale,
            user.TimeZone,
            user.CreatedAt,
            user.LastLoginAt,
            user.PasswordChangedAt,
            user.TwoFactorEnabled,
            user.TwoFactorEnabledAt,
            accountLock,
            signInMethods);
    }

    private static IReadOnlyList<CustomerSupportCurrencyAmount> CurrencyRows(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return [];
        }

        Dictionary<string, decimal> amounts;
        try
        {
            amounts = JsonSerializer.Deserialize<Dictionary<string, decimal>>(json) ?? [];
        }
        catch (JsonException)
        {
            return [];
        }

        return amounts
            .Where(pair => AdminCustomerSyncService.IsVisibleBalanceCurrency(pair.Key))
            .OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
            .Select(pair => new CustomerSupportCurrencyAmount(pair.Key, pair.Value))
            .ToArray();
    }
}
