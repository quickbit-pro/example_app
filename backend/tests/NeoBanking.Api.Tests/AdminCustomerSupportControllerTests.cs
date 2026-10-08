using System.Reflection;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Admin;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AdminCustomerSupportControllerTests
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private static readonly JsonSerializerOptions WebJson = new(JsonSerializerDefaults.Web);

    // Words that must never appear in a property name of the serialized response.
    private static readonly string[] ForbiddenFieldWords = ["hash", "token", "secret", "recovery", "json", "body"];

    [Fact]
    public void EndpointRequiresAdminPolicy()
    {
        Assert.Equal(AuthorizationPolicyNames.Admin,
            typeof(AdminCustomerSupportController).GetCustomAttribute<AuthorizeAttribute>()?.Policy);
    }

    [Fact]
    public async Task ReturnsNotFoundForCustomersOutsideTheCompanyAndForAdmins()
    {
        await using var db = CreateDatabase();
        var companyA = Guid.NewGuid();
        var companyB = Guid.NewGuid();
        var stranger = SeedUser(db, companyB, "stranger@example.test");
        var adminUser = SeedUser(db, companyA, "admin@example.test");
        db.AdminProfiles.Add(new AdminProfile { CompanyInstallationId = companyA, UserId = adminUser.Id, Role = "support" });
        db.RefreshSessions.Add(new RefreshSession
        {
            CompanyInstallationId = companyB, UserId = stranger.Id, TokenHash = "other-company-token-hash", ExpiresAt = DateTimeOffset.UtcNow.AddDays(1)
        });
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();

        var controller = Controller(db, companyA);
        var forStranger = await controller.GetSupport(stranger.Id, Ct);
        var notFound = Assert.IsType<NotFoundObjectResult>(forStranger.Result);
        Assert.Equal("Customer was not found.", JsonSerializer.SerializeToElement(notFound.Value, WebJson).GetProperty("message").GetString());

        var forAdmin = await controller.GetSupport(adminUser.Id, Ct);
        Assert.IsType<NotFoundObjectResult>(forAdmin.Result);

        var forUnknown = await controller.GetSupport(Guid.NewGuid(), Ct);
        Assert.IsType<NotFoundObjectResult>(forUnknown.Result);
    }

    [Fact]
    public async Task ReturnsSupportViewWithCountsOrderingLockStateAndNoSecrets()
    {
        await using var db = CreateDatabase();
        var now = DateTimeOffset.UtcNow;
        var companyId = Guid.NewGuid();
        var otherCompanyId = Guid.NewGuid();
        var user = SeedUser(db, companyId, "customer@example.test", u =>
        {
            u.DisplayName = "Ada Lovelace";
            u.PhoneNumber = "+15550100";
            u.Status = "locked";
            u.TwoFactorEnabled = true;
            u.TwoFactorEnabledAt = now.AddDays(-30);
            u.TwoFactorSecret = "TOTP-SECRET-VALUE";
            u.RecoveryCodesJson = "[\"RECOVERY-CODE-VALUE\"]";
            u.DuressPasswordHash = "DURESS-HASH-VALUE";
            u.LockedAt = now.AddDays(-1);
            u.LockReason = "duress";
            u.EmailVerifiedAt = now.AddDays(-40);
            u.PasswordChangedAt = now.AddDays(-10);
            u.LastLoginAt = now.AddHours(-2);
            u.CreatedAt = now.AddDays(-60);
        });
        var friend = SeedUser(db, companyId, "friend@example.test", u => u.DisplayName = "Grace Hopper");
        var nameless = SeedUser(db, companyId, "nameless@example.test", u => u.DisplayName = null);
        var neighbour = SeedUser(db, companyId, "neighbour@example.test");
        var outsider = SeedUser(db, otherCompanyId, "outsider@example.test");

        db.UserIdentities.Add(new UserIdentity
        {
            CompanyInstallationId = companyId, UserId = user.Id, Provider = "password", Subject = "customer@example.test",
            PasswordHash = "PASSWORD-HASH-VALUE", IsPrimary = true, LastAuthenticatedAt = now.AddHours(-2)
        });
        db.UserIdentities.Add(new UserIdentity
        {
            CompanyInstallationId = companyId, UserId = user.Id, Provider = "apple", Subject = "apple-subject",
            EmailAtProvider = "ada@privaterelay.example", IsPrimary = false
        });

        // Sessions: revoked (most recently used), expired, live (oldest).
        var revokedSession = new RefreshSession
        {
            CompanyInstallationId = companyId, UserId = user.Id, TokenHash = "REVOKED-TOKEN-HASH", RotatedFromTokenHash = "ROTATED-TOKEN-HASH",
            DeviceName = "Ada's iPhone", IpAddress = "203.0.113.7", UserAgent = "ExampleApp/1.4.2 iOS/17.5",
            CreatedAt = now.AddDays(-3), LastUsedAt = now.AddHours(-1), ExpiresAt = now.AddDays(27),
            RevokedAt = now.AddMinutes(-30), RevocationReason = "password_reset"
        };
        var expiredSession = new RefreshSession
        {
            CompanyInstallationId = companyId, UserId = user.Id, TokenHash = "EXPIRED-TOKEN-HASH",
            DeviceName = "Old laptop", CreatedAt = now.AddDays(-40), LastUsedAt = now.AddDays(-35), ExpiresAt = now.AddDays(-10)
        };
        var liveSession = new RefreshSession
        {
            CompanyInstallationId = companyId, UserId = user.Id, TokenHash = "LIVE-TOKEN-HASH",
            DeviceName = "Ada's iPad", CreatedAt = now.AddDays(-2), LastUsedAt = null, ExpiresAt = now.AddDays(28)
        };
        db.RefreshSessions.AddRange(revokedSession, expiredSession, liveSession,
            new RefreshSession { CompanyInstallationId = companyId, UserId = neighbour.Id, TokenHash = "NEIGHBOUR-TOKEN-HASH", ExpiresAt = now.AddDays(1) },
            new RefreshSession { CompanyInstallationId = otherCompanyId, UserId = outsider.Id, TokenHash = "OUTSIDER-TOKEN-HASH", ExpiresAt = now.AddDays(1) });

        db.PushDevices.Add(new PushDevice
        {
            CompanyInstallationId = companyId, UserId = user.Id, RegistrationToken = "FCM-REGISTRATION-TOKEN-VALUE",
            Platform = "ios", AppVersion = "1.4.2", Locale = "en-GB", LastSeenAt = now.AddHours(-1)
        });

        var pushNotification = new PushNotification
        {
            CompanyInstallationId = companyId, UserId = user.Id, EventId = "support-reply:1", EventType = "support.reply",
            Title = "Support has replied", Body = "There is a new reply.", Status = "sent", AttemptCount = 1,
            CreatedAt = now.AddHours(-5), SentAt = now.AddHours(-5)
        };
        var failedEmail = new EmailMessage
        {
            CompanyInstallationId = companyId, UserId = user.Id, TemplateKey = "welcome", ToEmail = user.Email, Subject = "Welcome to Example",
            HtmlBody = "<p>secret html body</p>", TextBody = "secret text body", Status = "failed", AttemptCount = 3,
            ErrorMessage = "Mailbox unavailable", CreatedAt = now.AddHours(-3)
        };
        db.PushNotifications.Add(pushNotification);
        db.EmailMessages.Add(failedEmail);
        db.EmailMessages.Add(new EmailMessage
        {
            CompanyInstallationId = companyId, UserId = neighbour.Id, TemplateKey = "welcome", ToEmail = neighbour.Email, Subject = "Not yours", Status = "sent"
        });

        var ticket = new SupportTicket
        {
            CompanyInstallationId = companyId, UserId = user.Id, Subject = "Card delivery", Status = SupportTicketStatuses.AwaitingSupport,
            CreatedAt = now.AddDays(-1), UpdatedAt = now.AddHours(-4)
        };
        db.SupportTickets.Add(ticket);
        db.SupportTicketMessages.AddRange(
            new SupportTicketMessage { TicketId = ticket.Id, AuthorUserId = user.Id, IsAdmin = false, Body = "Where is my card?", CreatedAt = now.AddDays(-1) },
            new SupportTicketMessage { TicketId = ticket.Id, AuthorUserId = Guid.NewGuid(), IsAdmin = true, Body = "On its way.", CreatedAt = now.AddHours(-4) });

        var sentTransfer = new PeerTransfer
        {
            CompanyInstallationId = companyId, SenderUserId = user.Id, RecipientUserId = friend.Id, Amount = 10.5m, Currency = "USD",
            Status = "completed", ExternalReferenceId = "p2p-sent-1", CreatedAt = now.AddHours(-6), CompletedAt = now.AddHours(-6)
        };
        var receivedTransfer = new PeerTransfer
        {
            CompanyInstallationId = companyId, SenderUserId = nameless.Id, RecipientUserId = user.Id, Amount = 25m, Currency = "EUR",
            Status = "failed", ErrorCode = "insufficient_funds", ErrorMessage = "Not enough balance", ExternalReferenceId = "p2p-recv-1",
            CreatedAt = now.AddHours(-2)
        };
        db.PeerTransfers.AddRange(sentTransfer, receivedTransfer,
            new PeerTransfer { CompanyInstallationId = companyId, SenderUserId = friend.Id, RecipientUserId = neighbour.Id, Amount = 1m, ExternalReferenceId = "p2p-other" });

        var application = new OnboardingApplication
        {
            CompanyInstallationId = companyId, ApplicantUserId = user.Id, Kind = "business", Status = "submitted",
            CurrentStep = "identity_verification", SubmittedAt = now.AddDays(-5), CreatedAt = now.AddDays(-6), UpdatedAt = now.AddDays(-5),
            FormDataJson = "{\"ssn\":\"FORM-DATA-SECRET\"}"
        };
        db.OnboardingApplications.Add(application);
        db.KycVerifications.Add(new KycVerification
        {
            CompanyInstallationId = companyId, UserId = user.Id, OnboardingApplicationId = application.Id, Provider = "sumsub",
            ProviderReference = "kyc-ref-1", Status = "approved", Level = "standard", CountryCode = "DE",
            StartedAt = now.AddDays(-5), SubmittedAt = now.AddDays(-5), ReviewedAt = now.AddDays(-4),
            ApplicantDataJson = "{\"documentNumber\":\"APPLICANT-DATA-SECRET\"}"
        });
        db.KybVerifications.Add(new KybVerification
        {
            CompanyInstallationId = companyId, OnboardingApplicationId = application.Id, BusinessName = "Analytical Engines Ltd",
            Provider = "sumsub", Status = "pending", CountryCode = "GB", CreatedAt = now.AddDays(-3), SubmittedAt = now.AddDays(-3)
        });

        db.AuditLogEntries.AddRange(
            new AuditLogEntry
            {
                CompanyInstallationId = companyId, ActorUserId = user.Id, Action = "auth.login", EntityType = "user", EntityId = user.Id,
                OccurredAt = now.AddHours(-2), IpAddress = "203.0.113.7", UserAgent = "ExampleApp/1.4.2", BeforeJson = "{\"before\":\"AUDIT-SECRET\"}"
            },
            new AuditLogEntry
            {
                CompanyInstallationId = companyId, ActorUserId = user.Id, Action = "profile.update", EntityType = "user", OccurredAt = now.AddDays(-1)
            },
            new AuditLogEntry { CompanyInstallationId = null, ActorUserId = user.Id, Action = "system.no_company", EntityType = "user", OccurredAt = now },
            new AuditLogEntry { CompanyInstallationId = companyId, ActorUserId = neighbour.Id, Action = "auth.login", EntityType = "user", OccurredAt = now });

        db.HoppaApiCallLogs.AddRange(
            new HoppaApiCallLog
            {
                CompanyInstallationId = companyId, ActorUserId = user.Id, OccurredAt = now.AddHours(-1), AppMethod = "POST",
                AppPath = "/api/v1/mobile/transfers", AppStatusCode = 502, HoppaMethod = "POST", HoppaEndpoint = "/transfers",
                HoppaStatusCode = 500, HoppaDurationMs = 1200, Succeeded = false, FailureCode = "upstream_error", FailureMessage = "Upstream failed",
                TraceId = "trace-1", AppRequestJson = "{\"pin\":\"REQUEST-BODY-SECRET\"}", HoppaResponseJson = "{\"x\":\"RESPONSE-BODY-SECRET\"}"
            },
            new HoppaApiCallLog
            {
                CompanyInstallationId = companyId, ActorUserId = user.Id, OccurredAt = now.AddDays(-3), AppMethod = "GET",
                AppPath = "/api/v1/mobile/cards", AppStatusCode = 504, HoppaMethod = "GET", HoppaEndpoint = "/cards", Succeeded = false
            },
            new HoppaApiCallLog
            {
                CompanyInstallationId = companyId, ActorUserId = user.Id, OccurredAt = now.AddMinutes(-5), AppMethod = "GET",
                AppPath = "/api/v1/mobile/cards", AppStatusCode = 200, HoppaMethod = "GET", HoppaEndpoint = "/cards", Succeeded = true
            },
            new HoppaApiCallLog
            {
                CompanyInstallationId = companyId, ActorUserId = neighbour.Id, OccurredAt = now, AppMethod = "GET",
                AppPath = "/api/v1/mobile/cards", HoppaMethod = "GET", HoppaEndpoint = "/cards", Succeeded = false
            });

        db.AdminCustomerSnapshots.Add(new AdminCustomerSnapshot
        {
            CompanyInstallationId = companyId, UserId = user.Id, CompletedTransactionCount30d = 4,
            TransactionInflow30dJson = "{\"USD\":120.5,\"EUR\":40}", TransactionOutflow30dJson = "{\"USD\":80}",
            LastTransactionAt = now.AddDays(-1), LastActivityAt = now.AddHours(-1)
        });
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();

        var result = await Controller(db, companyId).GetSupport(user.Id, Ct);
        var response = Assert.IsType<CustomerSupportResponse>(Assert.IsType<OkObjectResult>(result.Result).Value);

        // Account and lock.
        Assert.Equal("Ada Lovelace", response.Account.DisplayName);
        Assert.Equal("customer@example.test", response.Account.Email);
        Assert.Equal("+15550100", response.Account.Phone);
        Assert.True(response.Account.TwoFactorEnabled);
        Assert.NotNull(response.Account.Lock);
        Assert.Equal("duress", response.Account.Lock!.LockReason);
        Assert.Equal(user.LockedAt!.Value + AdminAccountsController.UnlockCoolingOff, response.Account.Lock.UnlockAvailableAt);
        Assert.False(response.Account.Lock.CanUnlockNow);
        Assert.Equal(2, response.Account.SignInMethods.Count);
        Assert.Equal("password", response.Account.SignInMethods[0].Provider);
        Assert.True(response.Account.SignInMethods[0].IsPrimary);
        Assert.Equal("ada@privaterelay.example", response.Account.SignInMethods[1].EmailAtProvider);

        // 30-day activity from the snapshot.
        Assert.Equal(4, response.Activity30d.CompletedTransactionCount);
        Assert.Equal(["EUR", "USD"], response.Activity30d.Inflow.Select(row => row.Currency));
        Assert.Equal(120.5m, response.Activity30d.Inflow.Single(row => row.Currency == "USD").Amount);
        Assert.Equal(80m, Assert.Single(response.Activity30d.Outflow).Amount);

        // Sessions: only this user's, ordered by (lastUsedAt ?? createdAt) desc, one live.
        Assert.Equal(1, response.Sessions.ActiveCount);
        Assert.Equal([revokedSession.Id, liveSession.Id, expiredSession.Id], response.Sessions.Items.Select(session => session.Id));
        Assert.Equal("password_reset", response.Sessions.Items[0].RevocationReason);
        Assert.Equal("203.0.113.7", response.Sessions.Items[0].IpAddress);

        var device = Assert.Single(response.Devices);
        Assert.Equal("ios", device.Platform);
        Assert.Equal("1.4.2", device.AppVersion);

        // Tickets.
        Assert.Equal(1, response.Tickets.TotalCount);
        Assert.Equal(1, response.Tickets.AwaitingSupportCount);
        var ticketRow = Assert.Single(response.Tickets.Items);
        Assert.Equal("Card delivery", ticketRow.Subject);
        Assert.Equal(2, ticketRow.MessageCount);
        Assert.True(ticketRow.LastMessageFromAdmin);
        Assert.Equal(now.AddHours(-4), ticketRow.LastMessageAt);

        // Notifications: push + email merged, newest first.
        Assert.Equal(2, response.Notifications.Count);
        Assert.Equal(["email", "push"], response.Notifications.Select(notification => notification.Kind));
        Assert.Equal(failedEmail.Id, response.Notifications[0].Id);
        Assert.Equal("Welcome to Example", response.Notifications[0].Title);
        Assert.Equal("failed", response.Notifications[0].Status);
        Assert.Equal("Mailbox unavailable", response.Notifications[0].ErrorMessage);
        Assert.Equal(3, response.Notifications[0].AttemptCount);
        Assert.Equal("welcome", response.Notifications[0].TemplateKey);
        Assert.Null(response.Notifications[0].EventType);
        Assert.Equal("support.reply", response.Notifications[1].EventType);
        Assert.Null(response.Notifications[1].TemplateKey);

        // Peer transfers: newest first, direction and counterparty from the user's point of view.
        Assert.Equal([receivedTransfer.Id, sentTransfer.Id], response.PeerTransfers.Select(transfer => transfer.Id));
        Assert.Equal("received", response.PeerTransfers[0].Direction);
        Assert.Equal("nameless@example.test", response.PeerTransfers[0].CounterpartyName);
        Assert.Equal("insufficient_funds", response.PeerTransfers[0].ErrorCode);
        Assert.Equal("sent", response.PeerTransfers[1].Direction);
        Assert.Equal("Grace Hopper", response.PeerTransfers[1].CounterpartyName);
        Assert.Equal(10.5m, response.PeerTransfers[1].Amount);

        // Verification history: KYB (newer) then KYC.
        Assert.Equal(["kyb", "kyc"], response.VerificationHistory.Select(verification => verification.Type));
        Assert.Equal("Analytical Engines Ltd", response.VerificationHistory[0].BusinessName);
        Assert.Null(response.VerificationHistory[0].Level);
        Assert.Equal("approved", response.VerificationHistory[1].Status);
        Assert.Equal("standard", response.VerificationHistory[1].Level);
        Assert.Equal("DE", response.VerificationHistory[1].CountryCode);

        var applicationRow = Assert.Single(response.OnboardingApplications);
        Assert.Equal(application.Id, applicationRow.Id);
        Assert.Equal("identity_verification", applicationRow.CurrentStep);

        // Audit trail: this user's actions in this company only, newest first.
        Assert.Equal(["auth.login", "profile.update"], response.AuditTrail.Select(entry => entry.Action));

        // Provider failures: this user's only.
        Assert.Equal(1, response.ApiCalls.FailedLast24h);
        Assert.Equal(2, response.ApiCalls.FailedLast7d);
        Assert.Equal(2, response.ApiCalls.RecentFailures.Count);
        Assert.Equal("trace-1", response.ApiCalls.RecentFailures[0].TraceId);
        Assert.Equal(502, response.ApiCalls.RecentFailures[0].AppStatusCode);
        Assert.Equal(1200, response.ApiCalls.RecentFailures[0].HoppaDurationMs);

        // Serialized form: camelCase, no secret-bearing fields, no secret values.
        var json = JsonSerializer.Serialize(response, WebJson);
        using var document = JsonDocument.Parse(json);
        Assert.True(document.RootElement.TryGetProperty("generatedAt", out _));
        Assert.True(document.RootElement.GetProperty("account").GetProperty("lock").TryGetProperty("canUnlockNow", out _));
        var propertyNames = PropertyNames(document.RootElement).Distinct().ToList();
        foreach (var word in ForbiddenFieldWords)
        {
            Assert.DoesNotContain(propertyNames, name => name.Contains(word, StringComparison.OrdinalIgnoreCase));
        }
        foreach (var secret in new[]
                 {
                     "TOTP-SECRET-VALUE", "RECOVERY-CODE-VALUE", "DURESS-HASH-VALUE", "PASSWORD-HASH-VALUE", "REVOKED-TOKEN-HASH",
                     "ROTATED-TOKEN-HASH", "EXPIRED-TOKEN-HASH", "LIVE-TOKEN-HASH", "FCM-REGISTRATION-TOKEN-VALUE", "secret html body",
                     "secret text body", "FORM-DATA-SECRET", "APPLICANT-DATA-SECRET", "AUDIT-SECRET", "REQUEST-BODY-SECRET", "RESPONSE-BODY-SECRET",
                     "Where is my card?", "On its way."
                 })
        {
            Assert.DoesNotContain(secret, json);
        }
    }

    [Fact]
    public async Task LockCanBeLiftedOnceCoolingOffHasPassed()
    {
        await using var db = CreateDatabase();
        var companyId = Guid.NewGuid();
        var lockedAt = DateTimeOffset.UtcNow - AdminAccountsController.UnlockCoolingOff - TimeSpan.FromMinutes(1);
        var user = SeedUser(db, companyId, "locked@example.test", u => { u.LockedAt = lockedAt; u.LockReason = "duress"; });
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();

        var response = Assert.IsType<CustomerSupportResponse>(
            Assert.IsType<OkObjectResult>((await Controller(db, companyId).GetSupport(user.Id, Ct)).Result).Value);
        Assert.NotNull(response.Account.Lock);
        Assert.True(response.Account.Lock!.CanUnlockNow);
        Assert.Equal(lockedAt + AdminAccountsController.UnlockCoolingOff, response.Account.Lock.UnlockAvailableAt);
        Assert.Empty(response.Sessions.Items);
        Assert.Equal(0, response.Activity30d.CompletedTransactionCount);
        Assert.Empty(response.Activity30d.Inflow);
        Assert.Empty(response.Notifications);
        Assert.Empty(response.VerificationHistory);
    }

    private static IEnumerable<string> PropertyNames(JsonElement element)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                foreach (var property in element.EnumerateObject())
                {
                    yield return property.Name;
                    foreach (var nested in PropertyNames(property.Value)) yield return nested;
                }
                break;
            case JsonValueKind.Array:
                foreach (var item in element.EnumerateArray())
                {
                    foreach (var nested in PropertyNames(item)) yield return nested;
                }
                break;
        }
    }

    private static AdminCustomerSupportController Controller(NeoBankingDbContext db, Guid companyId) => new(db)
    {
        ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(
                [
                    new Claim("company_installation_id", companyId.ToString()),
                    new Claim("local_user_id", Guid.NewGuid().ToString())
                ], "test"))
            }
        }
    };

    private static ApplicationUser SeedUser(NeoBankingDbContext db, Guid companyId, string email, Action<ApplicationUser>? configure = null)
    {
        var user = new ApplicationUser
        {
            CompanyInstallationId = companyId, Email = email, EmailNormalized = email.ToUpperInvariant(),
            DisplayName = "Test customer", Status = "active"
        };
        configure?.Invoke(user);
        db.Users.Add(user);
        return user;
    }

    private static NeoBankingDbContext CreateDatabase() => new(
        new DbContextOptionsBuilder<NeoBankingDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString("N")).Options);
}
