using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Application.Common;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Hoppa;
using NeoBanking.Infrastructure.Persistence;
using NeoBanking.Api.Notifications;

namespace NeoBanking.Api.Controllers;

[AllowAnonymous]
[Route("api/v1/webhooks")]
public sealed class WebhooksController(
    NeoBankingDbContext dbContext,
    IOptions<HoppaOptions> hoppaOptions,
    PushNotificationOutbox pushNotificationOutbox,
    ILogger<WebhooksController> logger) : ApiControllerBase
{
    private const string HoppaProvider = "hoppa";
    private const string InboundWebhookDirection = "inbound_webhook";
    private static readonly HashSet<string> KnownHoppaWebhookEvents = new(StringComparer.OrdinalIgnoreCase)
    {
        "user.registered",
        "user.kyc.updated",
        "kyc.verified",
        "kyc.interlace_submission_failed",
        "legal_entity.status",
        "bank_account.status",
        "account.deposit.address",
        "account.created",
        "account.activated",
        "account.status_updated",
        "payment.completed",
        "payment.mandate.created",
        "payment.mandate.cancelled",
        "payment.request.created",
        "payment.request.cancelled",
        "payment.request.confirmed.direct",
        "payment.request.confirmed.with.exchange",
        "order.completed",
        "order.created",
        "order.cancelled",
        "payout.payment",
        "business_account.transaction",
        "wallet.topped_up",
        "wallet.withdrawal",
        "wallet.refund",
        "budget.created",
        "budget.updated",
        "budget.deleted",
        "budget.transaction.closed",
        "budget.credited",
        "budget.debited",
        "budget.credit_pending",
        "card.created",
        "card.activated",
        "card.updated",
        "card.deleted",
        "card.shipped",
        "card.transaction",
        "card.topup",
        "card.unload",
        "card.state_updated",
        "card.3ds.otp",
        "card.3ds_auth_request",
        "digitalwallet.token_transition",
        "cardholder.status",
        "cardholder.created",
        "cardholder.approved",
        "cardholder.deleted",
        "person.created",
        "kyc.update",
        "kyc.information_request",
        "recipient.created",
        "recipient.deleted",
        "payment.created",
        "payment.returned",
        "fee.created",
        "paymentbatch.created",
        "paymentbatch.cancelled",
        "paymentbatch.validation_error",
        "paymentbatch.processing",
        "paymentbatch.completed",
        "paymentbatchorder.created",
        "paymentbatchorder.completed",
        "paymentbatchorder.cancelled"
    };

    [HttpPost("hoppa")]
    public async Task<ActionResult<object>> ReceiveHoppaWebhook(CancellationToken cancellationToken)
    {
        using var reader = new StreamReader(Request.Body, Encoding.UTF8);
        var rawBody = await reader.ReadToEndAsync(cancellationToken);

        if (!IsValidHoppaSignature(rawBody))
        {
            var response = new
            {
                code = "webhooks.hoppa.invalid_signature",
                message = "The Hoppa webhook signature is invalid."
            };
            await PersistRejectedHoppaWebhookLogAsync(
                rawBody,
                StatusCodes.Status401Unauthorized,
                response.code,
                response.message,
                response,
                cancellationToken);

            return Unauthorized(response);
        }

        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(rawBody);
        }
        catch (JsonException)
        {
            var response = new
            {
                code = "webhooks.hoppa.invalid_json",
                message = "The Hoppa webhook body must be valid JSON."
            };
            await PersistRejectedHoppaWebhookLogAsync(
                rawBody,
                StatusCodes.Status400BadRequest,
                response.code,
                response.message,
                response,
                cancellationToken);

            return BadRequest(response);
        }

        using (document)
        {
            return await ReceiveWebhookAsync(HoppaProvider, document.RootElement.Clone(), rawBody, processHoppa: true, cancellationToken);
        }
    }

    [HttpPost("sumsub")]
    public async Task<ActionResult<object>> ReceiveSumSubWebhook(CancellationToken cancellationToken)
    {
        using var reader = new StreamReader(Request.Body, Encoding.UTF8);
        var rawBody = await reader.ReadToEndAsync(cancellationToken);
        if (!IsValidWebhookSignature(
                rawBody,
                hoppaOptions.Value.SumSubWebhookSecret,
                Request.Headers["X-Payload-Digest"].FirstOrDefault()))
        {
            return Unauthorized(new
            {
                code = "webhooks.sumsub.invalid_signature",
                message = "The SumSub webhook signature is invalid."
            });
        }

        try
        {
            using var document = JsonDocument.Parse(rawBody);
            return await ReceiveWebhookAsync(
                "sumsub",
                document.RootElement.Clone(),
                rawBody,
                processHoppa: false,
                cancellationToken);
        }
        catch (JsonException)
        {
            return BadRequest(new
            {
                code = "webhooks.sumsub.invalid_json",
                message = "The SumSub webhook body must be valid JSON."
            });
        }
    }

    private async Task<ActionResult<object>> ReceiveWebhookAsync(
        string provider,
        JsonElement payload,
        string rawBody,
        bool processHoppa,
        CancellationToken cancellationToken)
    {
        var company = await dbContext.CompanyInstallations
            .SingleOrDefaultAsync(
                installation => installation.Slug == "default",
                cancellationToken);
        if (company is null)
        {
            return ToActionResult<object>(ApplicationResult<object>.Failure(
                new ApplicationError(
                    "webhooks.default_company_missing",
                    "Default company installation is not seeded.",
                    StatusCodes.Status500InternalServerError)));
        }

        var eventId = GetString(payload, "eventId") ??
            GetString(payload, "id") ??
            Request.Headers["X-Event-Id"].FirstOrDefault() ??
            Request.Headers["X-Hoppacard-Event-Id"].FirstOrDefault() ??
            Request.Headers["X-Sumsub-Webhook-Id"].FirstOrDefault() ??
            HttpContext.TraceIdentifier;
        var eventType = GetString(payload, "eventType") ??
            GetString(payload, "type") ??
            Request.Headers["X-Event-Type"].FirstOrDefault() ??
            Request.Headers["X-Hoppacard-Event-Type"].FirstOrDefault() ??
            $"{provider}.webhook";
        var now = DateTimeOffset.UtcNow;

        var existing = await dbContext.WebhookDeliveries
            .SingleOrDefaultAsync(
                delivery => delivery.CompanyInstallationId == company.Id &&
                            delivery.Provider == provider &&
                            delivery.EventId == eventId,
                cancellationToken);
        var delivery = existing;
        if (existing is not null)
        {
            existing.Status = "received";
            existing.EventType = eventType;
            existing.ReceivedAt = now;
            existing.HeadersJson = SerializeHeaders();
            existing.PayloadJson = rawBody;
            existing.ErrorMessage = null;
            existing.ResponseBody = null;
            existing.UpdatedAt = now;
        }
        else
        {
            delivery = new WebhookDelivery
            {
                CompanyInstallationId = company.Id,
                Provider = provider,
                EventId = eventId,
                EventType = eventType,
                Status = "received",
                ReceivedAt = now,
                HeadersJson = SerializeHeaders(),
                PayloadJson = rawBody,
                IdempotencyKey = Request.Headers["Idempotency-Key"].FirstOrDefault(),
                CreatedAt = now,
                UpdatedAt = now
            };
            dbContext.WebhookDeliveries.Add(delivery);
        }

        // Persist the delivery before projecting it so a processing failure
        // is recorded (and retried by the provider) instead of rolled back.
        await dbContext.SaveChangesAsync(cancellationToken);
        var deliveryId = delivery!.Id;

        WebhookProcessingResult processingResult;
        try
        {
            processingResult = processHoppa
                ? await ProcessHoppaWebhookAsync(company, eventId, eventType, payload, now, cancellationToken)
                : WebhookProcessingResult.Skipped("No local processor is registered for this provider.");

            if (delivery is not null)
            {
                delivery.Status = processingResult.Status;
                delivery.ProcessedAt = processingResult.ProcessedAt;
                delivery.ResponseStatusCode = StatusCodes.Status202Accepted;
                delivery.ResponseBody = processingResult.Message;
                delivery.ErrorMessage = processingResult.ErrorMessage;
                delivery.UpdatedAt = now;
            }

            if (processHoppa)
            {
                AddHoppaWebhookLog(
                    company.Id,
                    eventId,
                    eventType,
                    rawBody,
                    now,
                    StatusCodes.Status202Accepted,
                    processingResult.Status != "failed",
                    processingResult.Status == "failed" ? "webhooks.hoppa.processing_failed" : null,
                    processingResult.ErrorMessage,
                    new
                    {
                        message = "Webhook accepted.",
                        provider,
                        eventId,
                        eventType,
                        status = processingResult.Status,
                        processedAt = processingResult.ProcessedAt
                    });
            }

            await dbContext.SaveChangesAsync(cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            logger.LogError(exception, "Webhook {Provider}/{EventType} {EventId} could not be projected.", provider, eventType, eventId);
            dbContext.ChangeTracker.Clear();
            var error = Truncate(exception.GetBaseException().Message, 1000);
            await dbContext.WebhookDeliveries
                .Where(candidate => candidate.Id == deliveryId)
                .ExecuteUpdateAsync(setters => setters
                    .SetProperty(candidate => candidate.Status, "failed")
                    .SetProperty(candidate => candidate.AttemptCount, candidate => candidate.AttemptCount + 1)
                    .SetProperty(candidate => candidate.LastAttemptAt, now)
                    .SetProperty(candidate => candidate.ErrorMessage, error)
                    .SetProperty(candidate => candidate.ResponseStatusCode, StatusCodes.Status500InternalServerError)
                    .SetProperty(candidate => candidate.UpdatedAt, now),
                    cancellationToken);
            if (processHoppa)
            {
                AddHoppaWebhookLog(
                    company.Id, eventId, eventType, rawBody, now,
                    StatusCodes.Status500InternalServerError, false,
                    "webhooks.hoppa.processing_failed", error,
                    new { message = "Webhook processing failed.", provider, eventId, eventType, error });
                await dbContext.SaveChangesAsync(cancellationToken);
            }

            return ToActionResult<object>(ApplicationResult<object>.Failure(new ApplicationError(
                "webhooks.processing_failed",
                "The webhook was recorded but could not be processed. It will be retried.",
                StatusCodes.Status500InternalServerError,
                error)));
        }


        return Accepted(new
        {
            message = "Webhook accepted.",
            provider,
            eventId,
            eventType,
            status = processingResult.Status,
            processedAt = processingResult.ProcessedAt
        });
    }

    private async Task<WebhookProcessingResult> ProcessHoppaWebhookAsync(
        CompanyInstallation company,
        string eventId,
        string eventType,
        JsonElement payload,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (!TryGetData(payload, out var data))
        {
            return WebhookProcessingResult.Failed("Hoppa webhook payload is missing the data object.");
        }

        if (!KnownHoppaWebhookEvents.Contains(eventType))
        {
            await UpsertGenericProviderMappingAsync(company, null, payload, data, eventType, now, cancellationToken);
            await AddBankingSnapshotAsync(company, null, payload, data, eventType, now, cancellationToken);
            return WebhookProcessingResult.Processed($"Unknown Hoppa webhook event '{eventType}' was stored without a typed projection.");
        }

        var user = await ResolveUserAsync(company.Id, data, eventType, cancellationToken);

        switch (eventType)
        {
            case "user.registered":
                user = await HandleUserRegisteredAsync(company, data, now, cancellationToken);
                break;
            case "user.kyc.updated":
            case "kyc.verified":
                await UpsertKycVerificationAsync(company, user, data, eventType, now, cancellationToken);
                break;
            case "kyc.interlace_submission_failed":
                await UpsertKycVerificationAsync(company, user, data, eventType, now, cancellationToken);
                break;
            case "legal_entity.status":
                await UpsertKybVerificationAsync(company, user, data, eventType, now, cancellationToken);
                break;
            case "kyc.update":
            case "kyc.information_request":
                await UpsertKycVerificationAsync(company, user, data, eventType, now, cancellationToken);
                break;
            case "account.created":
            case "account.activated":
            case "account.status_updated":
            case "bank_account.status":
            case "account.deposit.address":
                await HandleAccountWebhookAsync(company, user, payload, data, eventType, now, cancellationToken);
                break;
            case "payment.completed":
            case "payment.mandate.created":
            case "payment.mandate.cancelled":
            case "payment.request.created":
            case "payment.request.cancelled":
            case "payment.request.confirmed.direct":
            case "payment.request.confirmed.with.exchange":
            case "payment.created":
            case "payment.returned":
            case "payout.payment":
            case "business_account.transaction":
            case "fee.created":
                await HandleMoneyMovementWebhookAsync(company, user, payload, data, eventType, now, cancellationToken);
                break;
            case "order.completed":
            case "order.created":
            case "order.cancelled":
            case "paymentbatch.created":
            case "paymentbatch.cancelled":
            case "paymentbatch.validation_error":
            case "paymentbatch.processing":
            case "paymentbatch.completed":
            case "paymentbatchorder.created":
            case "paymentbatchorder.completed":
            case "paymentbatchorder.cancelled":
                await HandleBatchOrOrderWebhookAsync(company, user, payload, data, eventType, now, cancellationToken);
                break;
            case "wallet.topped_up":
            case "wallet.withdrawal":
            case "wallet.refund":
            case "budget.created":
            case "budget.updated":
            case "budget.deleted":
            case "budget.transaction.closed":
            case "budget.credited":
            case "budget.debited":
            case "budget.credit_pending":
                await HandleWalletOrBudgetWebhookAsync(company, user, payload, data, eventType, now, cancellationToken);
                break;
            case "card.created":
            case "card.activated":
            case "card.updated":
            case "card.deleted":
            case "card.shipped":
            case "card.state_updated":
                await UpsertCardAsync(company, user, data, eventType, now, cancellationToken);
                break;
            case "card.transaction":
            case "card.topup":
            case "card.unload":
            case "card.3ds.otp":
            case "card.3ds_auth_request":
            case "digitalwallet.token_transition":
                await HandleCardActivityWebhookAsync(company, user, payload, data, eventType, now, cancellationToken);
                break;
            case "cardholder.status":
            case "cardholder.created":
            case "cardholder.approved":
            case "cardholder.deleted":
                await HandleCardholderWebhookAsync(company, user, payload, data, eventType, now, cancellationToken);
                break;
            case "person.created":
            case "recipient.created":
            case "recipient.deleted":
                await HandleCounterpartyWebhookAsync(company, user, payload, data, eventType, now, cancellationToken);
                break;
        }

        await UpsertGenericProviderMappingAsync(company, user, payload, data, eventType, now, cancellationToken);
        await AddBankingSnapshotAsync(company, user, payload, data, eventType, now, cancellationToken);
        await UpdateOnboardingStatusAsync(company.Id, user?.Id, eventType, data, now, cancellationToken);
        if (user is not null)
        {
            var customerSnapshot = await dbContext.AdminCustomerSnapshots.SingleOrDefaultAsync(
                snapshot => snapshot.CompanyInstallationId == company.Id && snapshot.UserId == user.Id,
                cancellationToken);
            // Keep this timestamp separate from the sync schedule: an event arriving
            // during a refresh must remain pending for the following worker pass.
            if (customerSnapshot is not null) customerSnapshot.SyncRequestedAt = now;
            await pushNotificationOutbox.EnqueueHoppaEventAsync(
                company.Id,
                user.Id,
                eventId,
                eventType,
                data,
                now,
                cancellationToken);
        }

        return WebhookProcessingResult.Processed(user is null
            ? "Webhook processed without a local user match."
            : "Webhook processed.");
    }

    private async Task HandleAccountWebhookAsync(
        CompanyInstallation company,
        ApplicationUser? user,
        JsonElement payload,
        JsonElement data,
        string eventType,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        await UpsertPrimaryEntitiesAsync(company, user, payload, data, eventType, now, cancellationToken);
        await UpdateOnboardingStatusAsync(company.Id, user?.Id, eventType, data, now, cancellationToken);
    }

    private async Task HandleMoneyMovementWebhookAsync(
        CompanyInstallation company,
        ApplicationUser? user,
        JsonElement payload,
        JsonElement data,
        string eventType,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        await UpsertPrimaryEntitiesAsync(company, user, payload, data, eventType, now, cancellationToken);
        await AddBankingSnapshotAsync(company, user, payload, data, eventType, now, cancellationToken);
    }

    private async Task HandleBatchOrOrderWebhookAsync(
        CompanyInstallation company,
        ApplicationUser? user,
        JsonElement payload,
        JsonElement data,
        string eventType,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        await UpsertPrimaryEntitiesAsync(company, user, payload, data, eventType, now, cancellationToken);
        await AddBankingSnapshotAsync(company, user, payload, data, eventType, now, cancellationToken);
    }

    private async Task HandleWalletOrBudgetWebhookAsync(
        CompanyInstallation company,
        ApplicationUser? user,
        JsonElement payload,
        JsonElement data,
        string eventType,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        await UpsertPrimaryEntitiesAsync(company, user, payload, data, eventType, now, cancellationToken);
        await AddBankingSnapshotAsync(company, user, payload, data, eventType, now, cancellationToken);
    }

    private async Task HandleCardActivityWebhookAsync(
        CompanyInstallation company,
        ApplicationUser? user,
        JsonElement payload,
        JsonElement data,
        string eventType,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (eventType is "card.transaction" or "card.topup" or "card.unload" or "digitalwallet.token_transition")
        {
            await UpsertCardAsync(company, user, data, eventType, now, cancellationToken);
        }

        await UpsertPrimaryEntitiesAsync(company, user, payload, data, eventType, now, cancellationToken);
        await AddBankingSnapshotAsync(company, user, payload, data, eventType, now, cancellationToken);
    }

    private async Task HandleCardholderWebhookAsync(
        CompanyInstallation company,
        ApplicationUser? user,
        JsonElement payload,
        JsonElement data,
        string eventType,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        await UpsertProviderMappingAsync(
            company.Id,
            ProviderFromPayload(payload),
            "cardholder",
            GetString(data, "cardholderId") ?? GetUserId(data) ?? "unknown",
            "user",
            user?.Id,
            GetString(data, "status") ?? StatusFromEvent(eventType),
            data.GetRawText(),
            now,
            cancellationToken);
        await UpsertPrimaryEntitiesAsync(company, user, payload, data, eventType, now, cancellationToken);
    }

    private async Task HandleCounterpartyWebhookAsync(
        CompanyInstallation company,
        ApplicationUser? user,
        JsonElement payload,
        JsonElement data,
        string eventType,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        await UpsertPrimaryEntitiesAsync(company, user, payload, data, eventType, now, cancellationToken);
    }

    private async Task<ApplicationUser?> HandleUserRegisteredAsync(
        CompanyInstallation company,
        JsonElement data,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var hoppaUserId = GetUserId(data);
        if (string.IsNullOrWhiteSpace(hoppaUserId))
        {
            return null;
        }

        var user = await ResolveUserAsync(company.Id, data, "user.registered", cancellationToken);
        if (user is null)
        {
            var email = GetString(data, "email");
            if (!string.IsNullOrWhiteSpace(email))
            {
                user = await dbContext.Users
                    .SingleOrDefaultAsync(
                        candidate => candidate.CompanyInstallationId == company.Id &&
                                     candidate.EmailNormalized == email.Trim().ToUpperInvariant(),
                        cancellationToken);
            }
        }

        if (user is not null)
        {
            await UpsertProviderMappingAsync(
                company.Id,
                HoppaProvider,
                "user",
                hoppaUserId,
                "user",
                user.Id,
                "registered",
                data.GetRawText(),
                now,
                cancellationToken);
        }

        return user;
    }

    private async Task UpsertKycVerificationAsync(
        CompanyInstallation company,
        ApplicationUser? user,
        JsonElement data,
        string eventType,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (user is null)
        {
            return;
        }

        var provider = eventType switch
        {
            "kyc.interlace_submission_failed" => "interlace",
            "kyc.verified" => "sumsub",
            "kyc.update" or "kyc.information_request" => "equalsmoney",
            _ => GetString(data, "provider") ?? HoppaProvider
        };
        var reference = GetString(data, "applicantId") ?? GetString(data, "accountId") ?? GetUserId(data);
        var kyc = await dbContext.KycVerifications
            .OrderByDescending(candidate => candidate.UpdatedAt)
            .FirstOrDefaultAsync(
                candidate => candidate.CompanyInstallationId == company.Id &&
                             candidate.UserId == user.Id &&
                             candidate.Provider == provider &&
                             (reference == null || candidate.ProviderReference == reference),
                cancellationToken);

        if (kyc is null)
        {
            kyc = new KycVerification
            {
                CompanyInstallationId = company.Id,
                UserId = user.Id,
                Provider = provider,
                ProviderReference = reference,
                StartedAt = now,
                CreatedAt = now
            };
            dbContext.KycVerifications.Add(kyc);
        }

        var status = NormalizeStatus(GetString(data, "status") ?? StatusFromEvent(eventType));
        kyc.Status = status;
        kyc.Level = GetString(data, "kycLevel") ?? kyc.Level;
        kyc.ApplicantDataJson = data.GetRawText();
        kyc.SubmittedAt ??= now;
        if (IsTerminalStatus(status))
        {
            kyc.ReviewedAt = now;
        }
        kyc.UpdatedAt = now;

        user.Status = UserStatusFromKycStatus(status, user.Status);
        user.UpdatedAt = now;
    }

    private async Task UpsertKybVerificationAsync(
        CompanyInstallation company,
        ApplicationUser? user,
        JsonElement data,
        string eventType,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (user is null)
        {
            return;
        }

        var reference = GetString(data, "entityId") ?? GetString(data, "accountId") ?? GetUserId(data);
        var application = await GetLatestOnboardingApplicationAsync(company.Id, user.Id, "business", cancellationToken);
        var query = dbContext.KybVerifications
            .Where(candidate => candidate.CompanyInstallationId == company.Id &&
                                candidate.Provider == HoppaProvider &&
                                (reference == null || candidate.ProviderReference == reference));
        query = application is not null
            ? query.Where(candidate => candidate.OnboardingApplicationId == application.Id)
            : query.Where(candidate => candidate.OnboardingApplication != null &&
                                       candidate.OnboardingApplication.ApplicantUserId == user.Id);

        var kyb = await query
            .OrderByDescending(candidate => candidate.UpdatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        if (kyb is null)
        {
            kyb = new KybVerification
            {
                CompanyInstallationId = company.Id,
                OnboardingApplicationId = application?.Id,
                BusinessName = user.DisplayName ?? user.Email,
                Provider = "hoppa",
                ProviderReference = reference,
                SubmittedAt = now,
                CreatedAt = now
            };
            dbContext.KybVerifications.Add(kyb);
        }

        var status = NormalizeStatus(GetString(data, "status") ?? StatusFromEvent(eventType));
        kyb.Status = status;
        kyb.BusinessProfileJson = data.GetRawText();
        if (IsTerminalStatus(status))
        {
            kyb.ReviewedAt = now;
        }
        kyb.UpdatedAt = now;
    }

    private async Task UpsertCardAsync(
        CompanyInstallation company,
        ApplicationUser? user,
        JsonElement data,
        string eventType,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (user is null)
        {
            return;
        }

        var providerCardId = GetString(data, "externalCardId") ?? GetString(data, "cardId");
        if (string.IsNullOrWhiteSpace(providerCardId))
        {
            return;
        }

        var card = await dbContext.Cards
            .SingleOrDefaultAsync(
                candidate => candidate.CompanyInstallationId == company.Id &&
                             candidate.Provider == HoppaProvider &&
                             candidate.ProviderCardId == providerCardId,
                cancellationToken);
        if (card is null)
        {
            card = new PaymentCard
            {
                CompanyInstallationId = company.Id,
                UserId = user.Id,
                Provider = HoppaProvider,
                ProviderCardId = providerCardId,
                CreatedAt = now
            };
            dbContext.Cards.Add(card);
        }

        card.Status = NormalizeStatus(
            GetString(data, "newStatus") ??
            GetString(data, "currentState") ??
            GetString(data, "status") ??
            StatusFromEvent(eventType));
        card.LastFour = GetString(data, "lastFour") ?? LastFourFromMaskedCardNumber(GetString(data, "cardNumber")) ?? card.LastFour;
        card.Currency = NormalizeCurrency(GetString(data, "currency") ?? card.Currency);
        card.SpendingControlsJson = data.GetRawText();
        card.ActivatedAt = (eventType is "card.activated" or "card.created") && IsActiveStatus(card.Status) ? now : card.ActivatedAt;
        card.SuspendedAt = IsSuspendedStatus(card.Status) ? now : card.SuspendedAt;
        card.ClosedAt = eventType is "card.deleted" || IsClosedStatus(card.Status) ? now : card.ClosedAt;
        card.UpdatedAt = now;

        await UpsertProviderMappingAsync(
            company.Id,
            HoppaProvider,
            "card",
            providerCardId,
            "card",
            card.Id,
            card.Status,
            data.GetRawText(),
            now,
            cancellationToken);
    }

    private async Task UpsertGenericProviderMappingAsync(
        CompanyInstallation company,
        ApplicationUser? user,
        JsonElement payload,
        JsonElement data,
        string eventType,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var provider = ProviderFromPayload(payload);
        foreach (var (entityType, entityId) in ExtractProviderEntities(data, eventType))
        {
            await UpsertProviderMappingAsync(
                company.Id,
                provider,
                entityType,
                entityId,
                "user",
                user?.Id,
                NormalizeStatus(GetString(data, "status") ?? StatusFromEvent(eventType)),
                data.GetRawText(),
                now,
                cancellationToken);
        }
    }

    private async Task UpsertPrimaryEntitiesAsync(
        CompanyInstallation company,
        ApplicationUser? user,
        JsonElement payload,
        JsonElement data,
        string eventType,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        await UpsertGenericProviderMappingAsync(company, user, payload, data, eventType, now, cancellationToken);
    }

    private async Task UpsertProviderMappingAsync(
        Guid companyInstallationId,
        string provider,
        string providerEntityType,
        string providerEntityId,
        string internalEntityType,
        Guid? internalEntityId,
        string externalStatus,
        string syncStateJson,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(providerEntityId))
        {
            return;
        }

        // A single webhook upserts the same mapping from several handlers;
        // reuse the row queued earlier in this request before hitting the DB.
        var mapping = dbContext.ProviderMappings.Local.FirstOrDefault(
                candidate => candidate.CompanyInstallationId == companyInstallationId &&
                             candidate.Provider == provider &&
                             candidate.ProviderEntityType == providerEntityType &&
                             candidate.ProviderEntityId == providerEntityId) ??
            await dbContext.ProviderMappings
                .SingleOrDefaultAsync(
                    candidate => candidate.CompanyInstallationId == companyInstallationId &&
                                 candidate.Provider == provider &&
                                 candidate.ProviderEntityType == providerEntityType &&
                                 candidate.ProviderEntityId == providerEntityId,
                    cancellationToken);
        if (mapping is null)
        {
            if (internalEntityId is null)
            {
                return;
            }

            mapping = new ProviderMapping
            {
                CompanyInstallationId = companyInstallationId,
                Provider = provider,
                ProviderEntityType = providerEntityType,
                ProviderEntityId = providerEntityId,
                InternalEntityType = internalEntityType,
                InternalEntityId = internalEntityId.Value,
                CreatedAt = now
            };
            dbContext.ProviderMappings.Add(mapping);
        }

        mapping.ExternalStatus = Truncate(NormalizeStatus(externalStatus), 40);
        mapping.LastSyncedAt = now;
        mapping.SyncStateJson = syncStateJson;
        mapping.UpdatedAt = now;
    }

    private async Task AddBankingSnapshotAsync(
        CompanyInstallation company,
        ApplicationUser? user,
        JsonElement payload,
        JsonElement data,
        string eventType,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (!IsBankingSnapshotEvent(eventType))
        {
            return;
        }

        var providerReference =
            GetString(data, "transactionId") ??
            GetString(data, "externalTransactionId") ??
            GetString(data, "paymentId") ??
            GetString(data, "accountId") ??
            GetString(data, "bankAccountId") ??
            GetString(data, "budgetId") ??
            GetString(data, "cardId") ??
            eventType;
        // PostgreSQL stores microseconds; trim .NET's 100ns ticks so the
        // duplicate check below compares equal to what was persisted.
        var rawAsOf = GetDateTimeOffset(data, "transactionDate") ??
            GetDateTimeOffset(data, "eventTime") ??
            GetDateTimeOffset(payload, "timestamp") ??
            now;
        var asOf = rawAsOf.AddTicks(-(rawAsOf.Ticks % 10));
        var provider = ProviderFromPayload(payload);
        var snapshotType = Truncate(eventType, 80);

        // The same event can reach this method twice in one request (typed
        // handler + generic tail), so pending rows count as existing too.
        var pending = dbContext.BankingSnapshots.Local.Any(snapshot =>
            snapshot.CompanyInstallationId == company.Id &&
            snapshot.Provider == provider &&
            snapshot.ProviderReference == providerReference &&
            snapshot.SnapshotType == snapshotType &&
            snapshot.AsOf == asOf);
        if (pending)
        {
            return;
        }

        var exists = await dbContext.BankingSnapshots
            .AnyAsync(
                snapshot => snapshot.CompanyInstallationId == company.Id &&
                            snapshot.Provider == provider &&
                            snapshot.ProviderReference == providerReference &&
                            snapshot.SnapshotType == snapshotType &&
                            snapshot.AsOf == asOf,
                cancellationToken);
        if (exists)
        {
            return;
        }

        dbContext.BankingSnapshots.Add(new BankingSnapshot
        {
            CompanyInstallationId = company.Id,
            UserId = user?.Id,
            Provider = provider,
            ProviderReference = providerReference,
            SnapshotType = snapshotType,
            AsOf = asOf,
            Currency = NormalizeCurrency(GetString(data, "currency") ?? GetString(data, "transactionCurrency") ?? "USD"),
            CurrentBalanceMinor = ToMinorUnits(GetDecimal(data, "amount") ?? GetDecimal(data, "totalAmount")),
            SnapshotJson = data.GetRawText(),
            CreatedAt = now,
            UpdatedAt = now
        });
    }

    private async Task UpdateOnboardingStatusAsync(
        Guid companyInstallationId,
        Guid? userId,
        string eventType,
        JsonElement data,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (userId is null)
        {
            return;
        }

        var application = eventType.StartsWith("legal_entity.", StringComparison.OrdinalIgnoreCase)
            ? await GetLatestOnboardingApplicationAsync(companyInstallationId, userId.Value, "business", cancellationToken)
            : await GetLatestOnboardingApplicationAsync(companyInstallationId, userId.Value, null, cancellationToken);
        if (application is null)
        {
            return;
        }

        var status = NormalizeStatus(GetString(data, "status") ?? StatusFromEvent(eventType));
        if (eventType is "account.created" or "account.activated" or "account.status_updated" ||
            eventType is "bank_account.status" or "account.deposit.address" ||
            eventType.StartsWith("legal_entity.", StringComparison.OrdinalIgnoreCase))
        {
            application.Status = OnboardingStatusFromExternalStatus(status);
            application.DecisionJson = data.GetRawText();
            application.CompletedAt = IsTerminalStatus(application.Status) ? now : application.CompletedAt;
            application.UpdatedAt = now;
        }
    }

    private async Task<ApplicationUser?> ResolveUserAsync(
        Guid companyInstallationId,
        JsonElement data,
        string eventType,
        CancellationToken cancellationToken)
    {
        var hoppaUserId = GetUserId(data);
        if (!string.IsNullOrWhiteSpace(hoppaUserId))
        {
            var mappedUserId = await dbContext.ProviderMappings
                .AsNoTracking()
                .Where(mapping => mapping.CompanyInstallationId == companyInstallationId &&
                                  mapping.Provider == HoppaProvider &&
                                  mapping.ProviderEntityType == "user" &&
                                  mapping.ProviderEntityId == hoppaUserId &&
                                  mapping.InternalEntityType == "user")
                .OrderByDescending(mapping => mapping.UpdatedAt)
                .Select(mapping => (Guid?)mapping.InternalEntityId)
                .FirstOrDefaultAsync(cancellationToken);
            if (mappedUserId is not null)
            {
                return await dbContext.Users.SingleOrDefaultAsync(user => user.Id == mappedUserId, cancellationToken);
            }
        }

        foreach (var externalId in ExtractProviderEntities(data, eventType)
                     .Select(entity => entity.EntityId)
                     .Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var mappedUserId = await dbContext.ProviderMappings
                .AsNoTracking()
                .Where(mapping => mapping.CompanyInstallationId == companyInstallationId &&
                                  mapping.ProviderEntityId == externalId &&
                                  mapping.InternalEntityType == "user")
                .OrderByDescending(mapping => mapping.UpdatedAt)
                .Select(mapping => (Guid?)mapping.InternalEntityId)
                .FirstOrDefaultAsync(cancellationToken);
            if (mappedUserId is not null)
            {
                return await dbContext.Users.SingleOrDefaultAsync(user => user.Id == mappedUserId, cancellationToken);
            }
        }

        return null;
    }

    private async Task<OnboardingApplication?> GetLatestOnboardingApplicationAsync(
        Guid companyInstallationId,
        Guid userId,
        string? kind,
        CancellationToken cancellationToken)
    {
        var query = dbContext.OnboardingApplications
            .Where(application => application.CompanyInstallationId == companyInstallationId &&
                                  application.ApplicantUserId == userId);
        if (!string.IsNullOrWhiteSpace(kind))
        {
            query = query.Where(application => application.Kind == kind);
        }

        return await query
            .OrderByDescending(application => application.UpdatedAt)
            .FirstOrDefaultAsync(cancellationToken);
    }

    private bool IsValidHoppaSignature(string rawBody)
    {
        return IsValidWebhookSignature(
            rawBody,
            hoppaOptions.Value.WebhookSecret,
            Request.Headers["X-Hoppacard-Signature"].FirstOrDefault());
    }

    private static bool IsValidWebhookSignature(string rawBody, string? secret, string? signature)
    {
        if (string.IsNullOrWhiteSpace(secret) ||
            string.Equals(secret, "replace-with-secret", StringComparison.OrdinalIgnoreCase) ||
            string.IsNullOrWhiteSpace(signature))
        {
            return false;
        }

        var digest = HMACSHA256.HashData(
            Encoding.UTF8.GetBytes(secret),
            Encoding.UTF8.GetBytes(rawBody));
        var candidate = signature.Trim();
        if (candidate.StartsWith("sha256=", StringComparison.OrdinalIgnoreCase))
        {
            candidate = candidate[7..];
        }

        var expectedHex = Convert.ToHexString(digest).ToLowerInvariant();
        var normalizedCandidate = candidate.ToLowerInvariant();
        if (expectedHex.Length == normalizedCandidate.Length &&
            CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(expectedHex),
                Encoding.UTF8.GetBytes(normalizedCandidate)))
        {
            return true;
        }

        var expectedBase64 = Convert.ToBase64String(digest);
        return expectedBase64.Length == candidate.Length &&
            CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(expectedBase64),
                Encoding.UTF8.GetBytes(candidate));
    }

    private static string? GetString(JsonElement payload, string propertyName)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !TryGetProperty(payload, propertyName, out var property))
        {
            return null;
        }

        var value = property.ValueKind switch
        {
            JsonValueKind.String => property.GetString(),
            JsonValueKind.Number => property.GetRawText(),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            _ => null
        };
        return string.IsNullOrWhiteSpace(value) ? null : value;
    }

    private static bool TryGetData(JsonElement payload, out JsonElement data)
    {
        if (payload.ValueKind == JsonValueKind.Object &&
            TryGetProperty(payload, "data", out data) &&
            data.ValueKind == JsonValueKind.Object)
        {
            return true;
        }

        data = default;
        return false;
    }

    private static bool TryGetProperty(JsonElement payload, string propertyName, out JsonElement property)
    {
        if (payload.TryGetProperty(propertyName, out property))
        {
            return true;
        }

        foreach (var candidate in payload.EnumerateObject())
        {
            if (string.Equals(candidate.Name, propertyName, StringComparison.OrdinalIgnoreCase))
            {
                property = candidate.Value;
                return true;
            }
        }

        property = default;
        return false;
    }

    private static string ProviderFromPayload(JsonElement payload)
    {
        return GetString(payload, "provider")?.Trim().ToLowerInvariant() ?? HoppaProvider;
    }

    private static string? GetUserId(JsonElement data)
    {
        return GetString(data, "userId") ?? GetString(data, "UserId");
    }

    private static string NormalizeStatus(string status)
    {
        return Truncate(status.Trim().Replace(' ', '_').ToLowerInvariant(), 40);
    }

    private static string NormalizeCurrency(string currency)
    {
        var normalized = currency.Trim().ToUpperInvariant();
        return normalized.Length == 3 ? normalized : "USD";
    }

    private static string StatusFromEvent(string eventType)
    {
        if (eventType.Contains("failed", StringComparison.OrdinalIgnoreCase))
        {
            return "failed";
        }

        var suffix = eventType.Split('.', StringSplitOptions.RemoveEmptyEntries).LastOrDefault() ?? "received";
        return suffix switch
        {
            "created" => "created",
            "activated" => "active",
            "approved" => "approved",
            "completed" => "completed",
            "deleted" => "deleted",
            "cancelled" => "cancelled",
            "failed" => "failed",
            _ => "received"
        };
    }

    private static string UserStatusFromKycStatus(string status, string currentStatus)
    {
        return status switch
        {
            "approved" or "verified" or "completed" => "active",
            "rejected" or "declined" or "failed" => "restricted",
            "pending" or "in_review" or "submitted" => "pending",
            _ => currentStatus
        };
    }

    private static string OnboardingStatusFromExternalStatus(string status)
    {
        return status switch
        {
            "approved" or "active" or "activated" or "created" => "approved",
            "rejected" or "declined" or "failed" or "deleted" or "cancelled" => "rejected",
            "pending" or "pending_documents" or "in_review" or "submitted" => "submitted",
            _ => status
        };
    }

    private static bool IsTerminalStatus(string status)
    {
        return status is "approved" or "verified" or "completed" or "active" or "rejected" or "declined" or "failed" or "cancelled" or "deleted";
    }

    private static bool IsActiveStatus(string status)
    {
        return status is "active" or "activated" or "approved";
    }

    private static bool IsSuspendedStatus(string status)
    {
        return status is "suspended" or "blocked" or "frozen";
    }

    private static bool IsClosedStatus(string status)
    {
        return status is "deleted" or "cancelled" or "closed";
    }

    private static string? LastFourFromMaskedCardNumber(string? cardNumber)
    {
        if (string.IsNullOrWhiteSpace(cardNumber))
        {
            return null;
        }

        var digits = new string(cardNumber.Where(char.IsDigit).ToArray());
        return digits.Length >= 4 ? digits[^4..] : null;
    }

    private static decimal? GetDecimal(JsonElement data, string propertyName)
    {
        if (data.ValueKind != JsonValueKind.Object ||
            !data.TryGetProperty(propertyName, out var property))
        {
            return null;
        }

        if (property.ValueKind == JsonValueKind.Number && property.TryGetDecimal(out var number))
        {
            return number;
        }

        if (property.ValueKind == JsonValueKind.String &&
            decimal.TryParse(property.GetString(), out var parsed))
        {
            return parsed;
        }

        return null;
    }

    private static long? ToMinorUnits(decimal? value)
    {
        return value is null ? null : decimal.ToInt64(decimal.Round(value.Value * 100, 0, MidpointRounding.AwayFromZero));
    }

    private static DateTimeOffset? GetDateTimeOffset(JsonElement data, string propertyName)
    {
        var value = GetString(data, propertyName);
        return DateTimeOffset.TryParse(value, out var parsed) ? parsed : null;
    }

    private static bool IsBankingSnapshotEvent(string eventType)
    {
        return eventType.StartsWith("payment.", StringComparison.OrdinalIgnoreCase) ||
            eventType.StartsWith("paymentbatch", StringComparison.OrdinalIgnoreCase) ||
            eventType.StartsWith("order.", StringComparison.OrdinalIgnoreCase) ||
            eventType.StartsWith("wallet.", StringComparison.OrdinalIgnoreCase) ||
            eventType.StartsWith("budget.", StringComparison.OrdinalIgnoreCase) ||
            eventType.StartsWith("card.transaction", StringComparison.OrdinalIgnoreCase) ||
            eventType is "card.topup" or "card.unload" or "payout.payment" or "business_account.transaction" or "fee.created" ||
            eventType.StartsWith("account.", StringComparison.OrdinalIgnoreCase) ||
            eventType.StartsWith("bank_account.", StringComparison.OrdinalIgnoreCase);
    }

    private static IEnumerable<(string EntityType, string EntityId)> ExtractProviderEntities(JsonElement data, string eventType)
    {
        foreach (var propertyName in new[]
        {
            "accountId",
            "bankAccountId",
            "cardholderId",
            "personId",
            "recipientId",
            "paymentId",
            "paymentMandateId",
            "paymentRequestId",
            "transactionId",
            "externalTransactionId",
            "transferId",
            "batchId",
            "orderId",
            "budgetId",
            "walletId",
            "cardId",
            "externalCardId",
            "tokenId",
            "feeId",
            "entityId",
            "applicantId",
            "messageId",
            "correlationId"
        })
        {
            var entityId = GetString(data, propertyName);
            if (!string.IsNullOrWhiteSpace(entityId))
            {
                yield return (ProviderEntityType(propertyName, eventType), entityId);
            }
        }
    }

    private static string ProviderEntityType(string propertyName, string eventType)
    {
        return propertyName switch
        {
            "accountId" => "account",
            "bankAccountId" => "bank_account",
            "cardholderId" => "cardholder",
            "personId" => "person",
            "recipientId" => "recipient",
            "paymentId" => "payment",
            "paymentMandateId" => "payment_mandate",
            "paymentRequestId" => "payment_request",
            "transactionId" or "externalTransactionId" => "transaction",
            "transferId" => "transfer",
            "batchId" => "payment_batch",
            "orderId" => eventType.StartsWith("paymentbatchorder", StringComparison.OrdinalIgnoreCase) ? "payment_batch_order" : "order",
            "budgetId" => "budget",
            "walletId" => "wallet",
            "cardId" or "externalCardId" => "card",
            "tokenId" => "digital_wallet_token",
            "feeId" => "fee",
            "entityId" => "legal_entity",
            "applicantId" => "kyc_applicant",
            "messageId" => "webhook_message",
            "correlationId" => "correlation",
            _ => propertyName
        };
    }

    private static string Truncate(string value, int maxLength)
    {
        return value.Length <= maxLength ? value : value[..maxLength];
    }

    private string SerializeHeaders()
    {
        var headers = Request.Headers.ToDictionary(
            header => header.Key,
            header => header.Value.ToString());

        return JsonSerializer.Serialize(headers);
    }

    private async Task PersistRejectedHoppaWebhookLogAsync(
        string rawBody,
        int statusCode,
        string failureCode,
        string failureMessage,
        object response,
        CancellationToken cancellationToken)
    {
        AddHoppaWebhookLog(
            null,
            Request.Headers["X-Event-Id"].FirstOrDefault() ??
                Request.Headers["X-Hoppacard-Event-Id"].FirstOrDefault() ??
                HttpContext.TraceIdentifier,
            Request.Headers["X-Event-Type"].FirstOrDefault() ??
                Request.Headers["X-Hoppacard-Event-Type"].FirstOrDefault() ??
                "hoppa.webhook",
            rawBody,
            DateTimeOffset.UtcNow,
            statusCode,
            succeeded: false,
            failureCode,
            failureMessage,
            response);

        await dbContext.SaveChangesAsync(cancellationToken);
    }

    private void AddHoppaWebhookLog(
        Guid? companyInstallationId,
        string eventId,
        string eventType,
        string rawBody,
        DateTimeOffset occurredAt,
        int appStatusCode,
        bool succeeded,
        string? failureCode,
        string? failureMessage,
        object appResponse)
    {
        dbContext.HoppaApiCallLogs.Add(new HoppaApiCallLog
        {
            CompanyInstallationId = companyInstallationId,
            TraceId = HttpContext.TraceIdentifier,
            IpAddress = GetClientIpAddress(),
            UserAgent = Request.Headers.UserAgent.FirstOrDefault(),
            OccurredAt = occurredAt,
            Direction = InboundWebhookDirection,
            AppMethod = Request.Method,
            AppPath = Request.Path.Value ?? "/api/v1/webhooks/hoppa",
            AppQueryString = Request.QueryString.HasValue ? Request.QueryString.Value : null,
            AppStatusCode = appStatusCode,
            AppRequestJson = SerializeWebhookRequest(rawBody),
            AppResponseJson = JsonSerializer.Serialize(appResponse),
            HoppaMethod = "WEBHOOK",
            HoppaEndpoint = eventType,
            HoppaQueryString = string.IsNullOrWhiteSpace(eventId) ? null : $"?eventId={Uri.EscapeDataString(eventId)}",
            HoppaStatusCode = null,
            HoppaDurationMs = 0,
            Succeeded = succeeded,
            FailureCode = failureCode,
            FailureMessage = failureMessage,
            HoppaRequestJson = NormalizeJsonBody(rawBody),
            HoppaResponseJson = JsonSerializer.Serialize(new
            {
                accepted = succeeded,
                statusCode = appStatusCode,
                eventId,
                eventType
            })
        });
    }

    private string SerializeWebhookRequest(string rawBody)
    {
        return JsonSerializer.Serialize(new
        {
            headers = JsonSerializer.Deserialize<Dictionary<string, string>>(SerializeRedactedHeaders()),
            body = JsonSerializer.Deserialize<object>(NormalizeJsonBody(rawBody))
        });
    }

    private string SerializeRedactedHeaders()
    {
        var headers = Request.Headers.ToDictionary(
            header => header.Key,
            header => IsSensitiveHeader(header.Key) ? "***REDACTED***" : header.Value.ToString());

        return JsonSerializer.Serialize(headers);
    }

    private static bool IsSensitiveHeader(string header)
    {
        return header.Contains("authorization", StringComparison.OrdinalIgnoreCase) ||
            header.Contains("signature", StringComparison.OrdinalIgnoreCase) ||
            header.Contains("secret", StringComparison.OrdinalIgnoreCase) ||
            header.Contains("token", StringComparison.OrdinalIgnoreCase) ||
            header.Contains("api-key", StringComparison.OrdinalIgnoreCase);
    }

    private static string NormalizeJsonBody(string rawBody)
    {
        if (string.IsNullOrWhiteSpace(rawBody))
        {
            return "{}";
        }

        try
        {
            using var document = JsonDocument.Parse(rawBody);
            return document.RootElement.GetRawText();
        }
        catch (JsonException)
        {
            return JsonSerializer.Serialize(new { raw = rawBody });
        }
    }

    private sealed record WebhookProcessingResult(
        string Status,
        DateTimeOffset? ProcessedAt,
        string Message,
        string? ErrorMessage)
    {
        public static WebhookProcessingResult Processed(string message)
        {
            return new("processed", DateTimeOffset.UtcNow, message, null);
        }

        public static WebhookProcessingResult Skipped(string message)
        {
            return new("received", null, message, null);
        }

        public static WebhookProcessingResult Failed(string error)
        {
            return new("failed", DateTimeOffset.UtcNow, error, error);
        }
    }
}
