#nullable enable

using System.Globalization;
using NeoBanking.Domain.Identity;
using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Notifications;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Peer;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Peer;

/// <summary>
/// Customer-to-customer money movement inside one installation, built on the
/// provider's public transfer API: the sender is debited into the programme's
/// master account and the recipient is credited from it. Requests, contacts
/// and the anti-spam pacing live in our own database.
/// </summary>
public sealed class PeerTransferService(
    NeoBankingDbContext dbContext,
    IProxyHoppaRequestUseCase proxyHoppa,
    PasswordHasher<ApplicationUser> passwordHasher,
    PushNotificationOutbox pushOutbox,
    ILogger<PeerTransferService> logger)
{
    private const string HoppaProvider = "hoppa";

    public const string PeerRoute = "/send";

    // ─── Lookup & contacts ──────────────────────────────────────────────────

    public async Task<ApplicationResult<PeerUserDto>> LookupAsync(
        Guid companyId,
        Guid requesterId,
        PeerLookupRequestDto request,
        CancellationToken cancellationToken)
    {
        var email = request.Email?.Trim();
        var phone = request.PhoneNumber?.Trim();
        var nickname = request.Nickname is null ? null : UserNickname.Normalize(request.Nickname);
        var queryCount = new[] { email, phone, nickname }.Count(value => !string.IsNullOrEmpty(value));
        if (queryCount != 1)
        {
            return Fail<PeerUserDto>("peer.lookup.query_required", "Enter one nickname, email address or phone number.", StatusCodes.Status400BadRequest);
        }

        ApplicationUser? match = null;
        if (!string.IsNullOrEmpty(nickname))
        {
            if (!UserNickname.IsValid(nickname))
                return Fail<PeerUserDto>("peer.lookup.nickname_invalid", UserNickname.RulesMessage, StatusCodes.Status400BadRequest);
            match = await ActiveUsers(companyId)
                .SingleOrDefaultAsync(user => user.Nickname == nickname, cancellationToken);
        }
        else if (!string.IsNullOrEmpty(email))
        {
            var normalized = email.ToUpperInvariant();
            match = await ActiveUsers(companyId)
                .FirstOrDefaultAsync(user => user.EmailNormalized == normalized, cancellationToken);
            // Members who signed up on the provider's own dashboard exist
            // there but not here yet: search the provider and link them.
            if (match is null || !await HasProviderAccountAsync(companyId, match.Id, cancellationToken))
            {
                match = await LinkProviderUserByEmailAsync(companyId, email, match, cancellationToken) ?? match;
            }
        }
        else
        {
            var digits = PeerTransferRules.NormalizePhone(phone);
            if (digits.Length < 6)
            {
                return Fail<PeerUserDto>("peer.lookup.phone_invalid", "Enter the full phone number including the country code.", StatusCodes.Status400BadRequest);
            }

            var tail = digits[^4..];
            var candidates = await ActiveUsers(companyId)
                .Where(user => user.PhoneNumber != null && user.PhoneNumber.Contains(tail))
                .Take(200)
                .ToListAsync(cancellationToken);
            match = candidates.FirstOrDefault(user => PeerTransferRules.PhonesMatch(user.PhoneNumber, phone));
        }

        if (match is null)
        {
            return Fail<PeerUserDto>("peer.lookup.not_found", "No member with those details was found.", StatusCodes.Status404NotFound);
        }

        if (match.Id == requesterId)
        {
            return Fail<PeerUserDto>("peer.lookup.self", "That is your own account.", StatusCodes.Status400BadRequest);
        }

        if (!await HasProviderAccountAsync(companyId, match.Id, cancellationToken))
        {
            return Fail<PeerUserDto>("peer.lookup.not_ready", "That member has not finished setting up their account yet.", StatusCodes.Status409Conflict);
        }

        var isContact = await dbContext.PeerContacts.AnyAsync(
            contact => contact.CompanyInstallationId == companyId &&
                       contact.OwnerUserId == requesterId &&
                       contact.ContactUserId == match.Id,
            cancellationToken);
        return ApplicationResult<PeerUserDto>.Success(ToUserDto(match, isContact));
    }

    public async Task<IReadOnlyList<PeerContactDto>> ListContactsAsync(Guid companyId, Guid ownerId, CancellationToken cancellationToken)
    {
        var contacts = await dbContext.PeerContacts
            .AsNoTracking()
            .Include(contact => contact.Contact)
            .Where(contact => contact.CompanyInstallationId == companyId && contact.OwnerUserId == ownerId)
            .OrderBy(contact => contact.CreatedAt)
            .ToListAsync(cancellationToken);
        return contacts
            .Where(contact => contact.Contact is not null)
            .Select(contact => new PeerContactDto
            {
                Id = contact.Id.ToString(),
                User = ToUserDto(contact.Contact!, isContact: true),
                Nickname = contact.Nickname,
                AddedAt = contact.CreatedAt
            })
            .ToList();
    }

    public async Task<ApplicationResult<PeerContactDto>> AddContactAsync(
        Guid companyId,
        Guid ownerId,
        PeerAddContactDto request,
        CancellationToken cancellationToken)
    {
        if (!Guid.TryParse(request.UserId, out var contactUserId))
        {
            return Fail<PeerContactDto>("peer.contact.invalid", "Choose a member to save.", StatusCodes.Status400BadRequest);
        }

        if (contactUserId == ownerId)
        {
            return Fail<PeerContactDto>("peer.contact.self", "You cannot save yourself as a contact.", StatusCodes.Status400BadRequest);
        }

        var user = await ActiveUsers(companyId).FirstOrDefaultAsync(candidate => candidate.Id == contactUserId, cancellationToken);
        if (user is null)
        {
            return Fail<PeerContactDto>("peer.contact.not_found", "That member was not found.", StatusCodes.Status404NotFound);
        }

        var existing = await dbContext.PeerContacts.FirstOrDefaultAsync(
            contact => contact.CompanyInstallationId == companyId &&
                       contact.OwnerUserId == ownerId &&
                       contact.ContactUserId == contactUserId,
            cancellationToken);
        var nickname = string.IsNullOrWhiteSpace(request.Nickname) ? null : request.Nickname.Trim();
        if (existing is null)
        {
            existing = new PeerContact
            {
                CompanyInstallationId = companyId,
                OwnerUserId = ownerId,
                ContactUserId = contactUserId,
                Nickname = nickname
            };
            dbContext.PeerContacts.Add(existing);
        }
        else if (nickname is not null)
        {
            existing.Nickname = nickname;
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        return ApplicationResult<PeerContactDto>.Success(new PeerContactDto
        {
            Id = existing.Id.ToString(),
            User = ToUserDto(user, isContact: true),
            Nickname = existing.Nickname,
            AddedAt = existing.CreatedAt
        });
    }

    public async Task<ApplicationResult<bool>> RemoveContactAsync(Guid companyId, Guid ownerId, Guid contactId, CancellationToken cancellationToken)
    {
        var contact = await dbContext.PeerContacts.FirstOrDefaultAsync(
            candidate => candidate.Id == contactId &&
                         candidate.CompanyInstallationId == companyId &&
                         candidate.OwnerUserId == ownerId,
            cancellationToken);
        if (contact is null)
        {
            return Fail<bool>("peer.contact.not_found", "That contact was not found.", StatusCodes.Status404NotFound);
        }

        dbContext.PeerContacts.Remove(contact);
        await dbContext.SaveChangesAsync(cancellationToken);
        return ApplicationResult<bool>.Success(true);
    }

    // ─── Fee & pacing ───────────────────────────────────────────────────────

    public async Task<PeerFeeInfoDto> GetFeeInfoAsync(
        Guid companyId,
        Guid userId,
        decimal? amount,
        string? currency,
        CancellationToken cancellationToken)
    {
        var code = PeerTransferRules.NormalizeCurrency(currency) ?? "USD";
        var pricing = await PricingAsync(companyId, userId, amount ?? 0m, code, DateTimeOffset.UtcNow, cancellationToken);
        return new PeerFeeInfoDto
        {
            FreeTransfersPerDay = PeerTransferRules.FreeTransfersPerDay,
            TransfersUsedToday = pricing.TransfersUsedToday,
            FreeTransfersRemaining = pricing.FreeTransfersRemaining,
            FeePercent = PeerTransferRules.FeePercent,
            FeeAmount = pricing.FeeAmount,
            FeeCurrency = code,
            FeeApplies = pricing.FeeApplies,
            IsRateLimited = pricing.IsRateLimited,
            RateLimitSecondsRemaining = pricing.RateLimitSecondsRemaining,
            NextTransferAllowedAt = pricing.NextAllowedAt,
            DailySendLimit = PeerTransferRules.MaxSendsPerDay,
            SendsRemainingToday = pricing.SendsRemainingToday,
            MinAmount = PeerTransferRules.MinAmount,
            MaxAmount = PeerTransferRules.MaxAmount,
            Currencies = PeerTransferRules.SupportedCurrencies
        };
    }

    private async Task<PeerTransferRules.Pricing> PricingAsync(
        Guid companyId,
        Guid userId,
        decimal amount,
        string currency,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var dayStart = new DateTimeOffset(now.UtcDateTime.Date, TimeSpan.Zero);
        var dayEnd = dayStart.AddDays(1);
        var sentToday = await dbContext.PeerTransfers.CountAsync(
            transfer => transfer.CompanyInstallationId == companyId &&
                        transfer.SenderUserId == userId &&
                        transfer.Status != "failed" &&
                        transfer.CreatedAt >= dayStart &&
                        transfer.CreatedAt < dayEnd,
            cancellationToken);
        var lastSentAt = await dbContext.PeerTransfers
            .Where(transfer => transfer.CompanyInstallationId == companyId &&
                               transfer.SenderUserId == userId &&
                               transfer.Status != "failed")
            .OrderByDescending(transfer => transfer.CreatedAt)
            .Select(transfer => (DateTimeOffset?)transfer.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);
        return PeerTransferRules.Evaluate(now, sentToday, lastSentAt, amount, currency);
    }

    // ─── Send ───────────────────────────────────────────────────────────────

    public async Task<ApplicationResult<PeerTransferDto>> SendAsync(
        Guid companyId,
        Guid senderId,
        PeerSendRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!Guid.TryParse(request.RecipientUserId, out var recipientId))
        {
            return Fail<PeerTransferDto>("peer.send.recipient_invalid", "Choose who to send money to.", StatusCodes.Status400BadRequest);
        }

        var confirmation = await VerifyConfirmationAsync(companyId, senderId, request.ConfirmationMethod, request.Password, cancellationToken);
        if (confirmation is not null)
        {
            return ApplicationResult<PeerTransferDto>.Failure(confirmation);
        }

        var result = await ExecuteTransferAsync(companyId, senderId, recipientId, request.Amount, request.Currency, request.Note, null, cancellationToken);
        return result.IsSuccess
            ? ApplicationResult<PeerTransferDto>.Success(ToTransferDto(result.Value!, senderId))
            : ApplicationResult<PeerTransferDto>.Failure(result.Error!);
    }

    private async Task<ApplicationResult<PeerTransfer>> ExecuteTransferAsync(
        Guid companyId,
        Guid senderId,
        Guid recipientId,
        decimal requestedAmount,
        string? requestedCurrency,
        string? note,
        Guid? paymentRequestId,
        CancellationToken cancellationToken)
    {
        var currency = PeerTransferRules.NormalizeCurrency(requestedCurrency);
        if (currency is null)
        {
            return Fail<PeerTransfer>("peer.send.currency_unsupported", "Only USD, USDC and USDT can be sent to other members.", StatusCodes.Status400BadRequest);
        }

        var amount = PeerTransferRules.RoundAmount(requestedAmount, currency);
        if (amount < PeerTransferRules.MinAmount || amount > PeerTransferRules.MaxAmount)
        {
            return Fail<PeerTransfer>("peer.send.amount_invalid", "Enter an amount between 0.01 and 1,000,000.", StatusCodes.Status400BadRequest);
        }

        if (senderId == recipientId)
        {
            return Fail<PeerTransfer>("peer.send.self", "You cannot send money to yourself.", StatusCodes.Status400BadRequest);
        }

        var trimmedNote = string.IsNullOrWhiteSpace(note) ? null : note.Trim();
        if (trimmedNote is { Length: > PeerTransferRules.NoteMaxLength })
        {
            return Fail<PeerTransfer>("peer.send.note_too_long", "Keep the note under 250 characters.", StatusCodes.Status400BadRequest);
        }

        var sender = await dbContext.Users.FirstOrDefaultAsync(user => user.Id == senderId && user.CompanyInstallationId == companyId, cancellationToken);
        if (sender is null || sender.LockedAt is not null)
        {
            return Fail<PeerTransfer>("peer.send.sender_unavailable", "Your account cannot send money right now.", StatusCodes.Status403Forbidden);
        }

        var recipient = await ActiveUsers(companyId).FirstOrDefaultAsync(user => user.Id == recipientId, cancellationToken);
        if (recipient is null)
        {
            return Fail<PeerTransfer>("peer.send.recipient_not_found", "That member was not found.", StatusCodes.Status404NotFound);
        }

        var senderProviderId = await ProviderUserIdAsync(companyId, senderId, cancellationToken);
        var recipientProviderId = await ProviderUserIdAsync(companyId, recipientId, cancellationToken);
        if (senderProviderId is null)
        {
            return Fail<PeerTransfer>("peer.send.sender_not_ready", "Finish setting up your account before sending money.", StatusCodes.Status409Conflict);
        }

        if (recipientProviderId is null)
        {
            return Fail<PeerTransfer>("peer.send.recipient_not_ready", "That member has not finished setting up their account yet.", StatusCodes.Status409Conflict);
        }

        var now = DateTimeOffset.UtcNow;
        var pricing = await PricingAsync(companyId, senderId, amount, currency, now, cancellationToken);
        if (pricing.IsRateLimited)
        {
            return Fail<PeerTransfer>(
                "peer.send.rate_limited",
                $"Please wait {pricing.RateLimitSecondsRemaining} seconds before sending another transfer.",
                StatusCodes.Status429TooManyRequests);
        }

        if (pricing.SendsRemainingToday <= 0)
        {
            return Fail<PeerTransfer>("peer.send.daily_limit", "You have reached today's limit for transfers to other members.", StatusCodes.Status429TooManyRequests);
        }

        var (senderFirst, senderLast) = PeerTransferRules.SplitName(sender.DisplayName, sender.Email);
        var (recipientFirst, recipientLast) = PeerTransferRules.SplitName(recipient.DisplayName, recipient.Email);
        var transfer = new PeerTransfer
        {
            CompanyInstallationId = companyId,
            SenderUserId = senderId,
            RecipientUserId = recipientId,
            Amount = amount,
            Currency = currency,
            Note = trimmedNote,
            FeeAmount = pricing.FeeAmount,
            Status = "pending",
            ExternalReferenceId = $"p2p_{Guid.CreateVersion7():N}",
            PaymentRequestId = paymentRequestId,
            CreatedAt = now,
            UpdatedAt = now
        };
        dbContext.PeerTransfers.Add(transfer);
        await dbContext.SaveChangesAsync(cancellationToken);

        var debit = await ProviderTransferAsync(
            "user-to-master",
            senderProviderId,
            amount + pricing.FeeAmount,
            currency,
            Describe($"Sent to {Trim(recipientFirst, recipientLast)}", trimmedNote),
            transfer.ExternalReferenceId,
            "peer.send.debit_failed",
            "We could not take the money from your account.",
            cancellationToken);
        if (!debit.Succeeded)
        {
            transfer.Status = "failed";
            transfer.ErrorCode = debit.Error!.Code;
            transfer.ErrorMessage = Truncate(debit.Error.Message, 500);
            await dbContext.SaveChangesAsync(cancellationToken);
            return ApplicationResult<PeerTransfer>.Failure(debit.Error);
        }

        transfer.DebitTransferId = debit.TransferId;
        await dbContext.SaveChangesAsync(cancellationToken);

        var credit = await ProviderTransferAsync(
            "master-to-user",
            recipientProviderId,
            amount,
            currency,
            Describe($"From {Trim(senderFirst, senderLast)}", trimmedNote),
            transfer.ExternalReferenceId,
            "peer.send.credit_failed",
            "The money left your account but could not be delivered.",
            cancellationToken);
        if (!credit.Succeeded)
        {
            logger.LogError(
                "Peer transfer {TransferId} credit failed after debit {DebitId}: {Code} {Message}",
                transfer.Id, transfer.DebitTransferId, credit.Error!.Code, credit.Error.Message);
            var refund = await ProviderTransferAsync(
                "master-to-user",
                senderProviderId,
                amount + pricing.FeeAmount,
                currency,
                $"Refund of failed transfer to {Trim(recipientFirst, recipientLast)}",
                $"{transfer.ExternalReferenceId}_refund",
                "peer.send.refund_failed",
                "Refund failed.",
                cancellationToken);
            transfer.Status = refund.Succeeded ? "refunded" : "needs_attention";
            transfer.RefundTransferId = refund.TransferId;
            transfer.ErrorCode = credit.Error.Code;
            transfer.ErrorMessage = Truncate(credit.Error.Message, 500);
            await dbContext.SaveChangesAsync(cancellationToken);
            return Fail<PeerTransfer>(
                credit.Error.Code,
                refund.Succeeded
                    ? "The recipient could not be credited, so the money was returned to your account."
                    : "The recipient could not be credited. Our support team has been notified and will restore your balance.",
                StatusCodes.Status502BadGateway,
                credit.Error.Detail);
        }

        transfer.CreditTransferId = credit.TransferId;
        transfer.Status = "completed";
        transfer.CompletedAt = DateTimeOffset.UtcNow;
        await pushOutbox.EnqueueAsync(
            companyId,
            recipientId,
            $"peer-transfer:{transfer.Id}",
            "peer_transfer.received",
            new UserPushMessage(
                "Money received",
                $"{Trim(senderFirst, senderLast)} sent you {FormatMoney(amount, currency)}" + (trimmedNote is null ? "." : $" · {trimmedNote}"),
                PeerRoute,
                new Dictionary<string, string> { ["transferId"] = transfer.Id.ToString() }),
            transfer.CompletedAt.Value,
            cancellationToken);
        await dbContext.SaveChangesAsync(cancellationToken);
        return ApplicationResult<PeerTransfer>.Success(transfer);
    }

    private sealed record ProviderTransferOutcome(bool Succeeded, string? TransferId, ApplicationError? Error);

    private async Task<ProviderTransferOutcome> ProviderTransferAsync(
        string leg,
        string providerUserId,
        decimal amount,
        string currency,
        string description,
        string externalReferenceId,
        string failureCode,
        string failureMessage,
        CancellationToken cancellationToken)
    {
        var body = new
        {
            UserId = int.TryParse(providerUserId, out var numeric) ? numeric : (object)providerUserId,
            Amount = PeerTransferRules.FormatAmount(amount, currency),
            Currency = currency,
            Description = Truncate(description, 250),
            ExternalReferenceId = externalReferenceId
        };
        var result = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object>
            {
                Method = HttpMethod.Post,
                UpstreamPath = $"/api/v2/transfers/{leg}",
                Request = body,
                FailureCode = failureCode,
                FailureMessage = failureMessage
            },
            cancellationToken);
        if (!result.IsSuccess)
        {
            var error = result.Error!;
            var providerMessage = ProviderMessage(error.Detail);
            return new ProviderTransferOutcome(
                false,
                null,
                new ApplicationError(error.Code, providerMessage ?? error.Message, MapStatus(error.StatusCode), error.Detail));
        }

        var payload = result.Value;
        var status = ReadString(payload, "status", "Status") ?? string.Empty;
        var transferId = ReadString(payload, "id", "Id", "transferId", "TransferId");
        if (!string.Equals(status, "COMPLETED", StringComparison.OrdinalIgnoreCase))
        {
            var message = ReadString(payload, "message", "Message") ?? failureMessage;
            var code = ReadString(payload, "errorCode", "ErrorCode") ?? failureCode;
            return new ProviderTransferOutcome(false, transferId, new ApplicationError(code, message, StatusCodes.Status422UnprocessableEntity, payload?.ToString()));
        }

        return new ProviderTransferOutcome(true, transferId, null);
    }

    // ─── Requests ───────────────────────────────────────────────────────────

    public async Task<ApplicationResult<PeerPaymentRequestDto>> RequestMoneyAsync(
        Guid companyId,
        Guid requesterId,
        PeerRequestMoneyDto request,
        CancellationToken cancellationToken)
    {
        if (!Guid.TryParse(request.FromUserId, out var payerId))
        {
            return Fail<PeerPaymentRequestDto>("peer.request.payer_invalid", "Choose who to request money from.", StatusCodes.Status400BadRequest);
        }

        if (payerId == requesterId)
        {
            return Fail<PeerPaymentRequestDto>("peer.request.self", "You cannot request money from yourself.", StatusCodes.Status400BadRequest);
        }

        var currency = PeerTransferRules.NormalizeCurrency(request.Currency);
        if (currency is null)
        {
            return Fail<PeerPaymentRequestDto>("peer.request.currency_unsupported", "Only USD, USDC and USDT can be requested.", StatusCodes.Status400BadRequest);
        }

        var amount = PeerTransferRules.RoundAmount(request.Amount, currency);
        if (amount < PeerTransferRules.MinAmount || amount > PeerTransferRules.MaxAmount)
        {
            return Fail<PeerPaymentRequestDto>("peer.request.amount_invalid", "Enter an amount between 0.01 and 1,000,000.", StatusCodes.Status400BadRequest);
        }

        var requester = await dbContext.Users.FirstOrDefaultAsync(user => user.Id == requesterId && user.CompanyInstallationId == companyId, cancellationToken);
        if (requester is null || requester.LockedAt is not null)
        {
            return Fail<PeerPaymentRequestDto>("peer.request.requester_unavailable", "Your account cannot request money right now.", StatusCodes.Status403Forbidden);
        }

        var payer = await ActiveUsers(companyId).FirstOrDefaultAsync(user => user.Id == payerId, cancellationToken);
        if (payer is null)
        {
            return Fail<PeerPaymentRequestDto>("peer.request.payer_not_found", "That member was not found.", StatusCodes.Status404NotFound);
        }

        var now = DateTimeOffset.UtcNow;
        var dayStart = new DateTimeOffset(now.UtcDateTime.Date, TimeSpan.Zero);
        var requestsToday = await dbContext.PeerPaymentRequests.CountAsync(
            candidate => candidate.CompanyInstallationId == companyId &&
                         candidate.RequesterUserId == requesterId &&
                         candidate.CreatedAt >= dayStart,
            cancellationToken);
        if (requestsToday >= PeerTransferRules.MaxRequestsPerDay)
        {
            return Fail<PeerPaymentRequestDto>("peer.request.daily_limit", "You have reached today's limit for payment requests.", StatusCodes.Status429TooManyRequests);
        }

        var lastRequestAt = await dbContext.PeerPaymentRequests
            .Where(candidate => candidate.CompanyInstallationId == companyId && candidate.RequesterUserId == requesterId)
            .OrderByDescending(candidate => candidate.CreatedAt)
            .Select(candidate => (DateTimeOffset?)candidate.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);
        if (lastRequestAt.HasValue && lastRequestAt.Value.Add(PeerTransferRules.MinimumInterval) > now)
        {
            var wait = Math.Max(1, (int)Math.Ceiling((lastRequestAt.Value.Add(PeerTransferRules.MinimumInterval) - now).TotalSeconds));
            return Fail<PeerPaymentRequestDto>("peer.request.rate_limited", $"Please wait {wait} seconds before sending another request.", StatusCodes.Status429TooManyRequests);
        }

        var openTowardsPayer = await dbContext.PeerPaymentRequests.CountAsync(
            candidate => candidate.CompanyInstallationId == companyId &&
                         candidate.RequesterUserId == requesterId &&
                         candidate.PayerUserId == payerId &&
                         candidate.Status == "pending" &&
                         candidate.ExpiresAt > now,
            cancellationToken);
        if (openTowardsPayer >= PeerTransferRules.MaxOpenRequestsPerPayer)
        {
            return Fail<PeerPaymentRequestDto>("peer.request.too_many_open", "You already have open requests with this member. Wait for a reply or cancel one first.", StatusCodes.Status429TooManyRequests);
        }

        var note = string.IsNullOrWhiteSpace(request.Note) ? null : request.Note.Trim();
        var paymentRequest = new PeerPaymentRequest
        {
            CompanyInstallationId = companyId,
            RequesterUserId = requesterId,
            PayerUserId = payerId,
            Amount = amount,
            Currency = currency,
            Note = note,
            Status = "pending",
            ExpiresAt = now.Add(PeerTransferRules.RequestTimeToLive),
            CreatedAt = now,
            UpdatedAt = now
        };
        dbContext.PeerPaymentRequests.Add(paymentRequest);

        var (first, last) = PeerTransferRules.SplitName(requester.DisplayName, requester.Email);
        await pushOutbox.EnqueueAsync(
            companyId,
            payerId,
            $"peer-request:{paymentRequest.Id}",
            "peer_request.received",
            new UserPushMessage(
                "Payment request",
                $"{Trim(first, last)} requested {FormatMoney(amount, currency)}" + (note is null ? "." : $" · {note}"),
                PeerRoute,
                new Dictionary<string, string> { ["requestId"] = paymentRequest.Id.ToString() }),
            now,
            cancellationToken);
        await dbContext.SaveChangesAsync(cancellationToken);
        paymentRequest.Requester = requester;
        paymentRequest.Payer = payer;
        return ApplicationResult<PeerPaymentRequestDto>.Success(ToRequestDto(paymentRequest, requesterId));
    }

    public async Task<PeerRequestsDto> ListRequestsAsync(Guid companyId, Guid userId, CancellationToken cancellationToken)
    {
        var now = DateTimeOffset.UtcNow;
        var stale = await dbContext.PeerPaymentRequests
            .Where(request => request.CompanyInstallationId == companyId &&
                              request.Status == "pending" &&
                              request.ExpiresAt <= now &&
                              (request.PayerUserId == userId || request.RequesterUserId == userId))
            .ToListAsync(cancellationToken);
        foreach (var request in stale)
        {
            request.Status = "expired";
            request.UpdatedAt = now;
        }
        if (stale.Count > 0)
        {
            await dbContext.SaveChangesAsync(cancellationToken);
        }

        var requests = await dbContext.PeerPaymentRequests
            .AsNoTracking()
            .Include(request => request.Requester)
            .Include(request => request.Payer)
            .Where(request => request.CompanyInstallationId == companyId &&
                              (request.PayerUserId == userId || request.RequesterUserId == userId))
            .OrderByDescending(request => request.CreatedAt)
            .Take(120)
            .ToListAsync(cancellationToken);
        var mapped = requests.Select(request => ToRequestDto(request, userId)).ToList();
        return new PeerRequestsDto
        {
            Received = mapped.Where(request => request.Status == "pending" && request.Type == "received").ToList(),
            Sent = mapped.Where(request => request.Status == "pending" && request.Type == "sent").ToList(),
            History = mapped.Where(request => request.Status != "pending").Take(40).ToList()
        };
    }

    public async Task<ApplicationResult<PeerRespondResultDto>> RespondAsync(
        Guid companyId,
        Guid userId,
        Guid requestId,
        PeerRespondRequestDto request,
        CancellationToken cancellationToken)
    {
        var action = request.Action.Trim().ToLowerInvariant();
        if (action is not ("accept" or "decline"))
        {
            return Fail<PeerRespondResultDto>("peer.respond.action_invalid", "Choose to pay or decline the request.", StatusCodes.Status400BadRequest);
        }

        var paymentRequest = await dbContext.PeerPaymentRequests
            .Include(candidate => candidate.Requester)
            .Include(candidate => candidate.Payer)
            .FirstOrDefaultAsync(candidate => candidate.Id == requestId && candidate.CompanyInstallationId == companyId, cancellationToken);
        if (paymentRequest is null)
        {
            return Fail<PeerRespondResultDto>("peer.respond.not_found", "That request was not found.", StatusCodes.Status404NotFound);
        }

        if (paymentRequest.PayerUserId != userId)
        {
            return Fail<PeerRespondResultDto>("peer.respond.forbidden", "Only the person asked to pay can respond.", StatusCodes.Status403Forbidden);
        }

        var now = DateTimeOffset.UtcNow;
        if (paymentRequest.Status != "pending")
        {
            return Fail<PeerRespondResultDto>("peer.respond.closed", $"This request is already {paymentRequest.Status}.", StatusCodes.Status409Conflict);
        }

        if (paymentRequest.ExpiresAt <= now)
        {
            paymentRequest.Status = "expired";
            paymentRequest.UpdatedAt = now;
            await dbContext.SaveChangesAsync(cancellationToken);
            return Fail<PeerRespondResultDto>("peer.respond.expired", "This request has expired.", StatusCodes.Status409Conflict);
        }

        if (action == "decline")
        {
            paymentRequest.Status = "declined";
            paymentRequest.RespondedAt = now;
            paymentRequest.UpdatedAt = now;
            await NotifyRequesterAsync(paymentRequest, "declined", cancellationToken);
            await dbContext.SaveChangesAsync(cancellationToken);
            return ApplicationResult<PeerRespondResultDto>.Success(new PeerRespondResultDto { Request = ToRequestDto(paymentRequest, userId) });
        }

        var confirmation = await VerifyConfirmationAsync(companyId, userId, request.ConfirmationMethod, request.Password, cancellationToken);
        if (confirmation is not null)
        {
            return ApplicationResult<PeerRespondResultDto>.Failure(confirmation);
        }

        var transferResult = await ExecuteTransferAsync(
            companyId,
            userId,
            paymentRequest.RequesterUserId,
            paymentRequest.Amount,
            paymentRequest.Currency,
            paymentRequest.Note,
            paymentRequest.Id,
            cancellationToken);
        if (!transferResult.IsSuccess)
        {
            return ApplicationResult<PeerRespondResultDto>.Failure(transferResult.Error!);
        }

        paymentRequest.Status = "accepted";
        paymentRequest.RespondedAt = DateTimeOffset.UtcNow;
        paymentRequest.UpdatedAt = paymentRequest.RespondedAt.Value;
        paymentRequest.TransferId = transferResult.Value!.Id;
        await NotifyRequesterAsync(paymentRequest, "accepted", cancellationToken);
        await dbContext.SaveChangesAsync(cancellationToken);
        return ApplicationResult<PeerRespondResultDto>.Success(new PeerRespondResultDto
        {
            Request = ToRequestDto(paymentRequest, userId),
            Transfer = ToTransferDto(transferResult.Value, userId)
        });
    }

    public async Task<ApplicationResult<PeerPaymentRequestDto>> CancelRequestAsync(
        Guid companyId,
        Guid userId,
        Guid requestId,
        CancellationToken cancellationToken)
    {
        var paymentRequest = await dbContext.PeerPaymentRequests
            .Include(candidate => candidate.Requester)
            .Include(candidate => candidate.Payer)
            .FirstOrDefaultAsync(candidate => candidate.Id == requestId && candidate.CompanyInstallationId == companyId, cancellationToken);
        if (paymentRequest is null || paymentRequest.RequesterUserId != userId)
        {
            return Fail<PeerPaymentRequestDto>("peer.cancel.not_found", "That request was not found.", StatusCodes.Status404NotFound);
        }

        if (paymentRequest.Status != "pending")
        {
            return Fail<PeerPaymentRequestDto>("peer.cancel.closed", $"This request is already {paymentRequest.Status}.", StatusCodes.Status409Conflict);
        }

        var now = DateTimeOffset.UtcNow;
        paymentRequest.Status = "cancelled";
        paymentRequest.RespondedAt = now;
        paymentRequest.UpdatedAt = now;
        await dbContext.SaveChangesAsync(cancellationToken);
        return ApplicationResult<PeerPaymentRequestDto>.Success(ToRequestDto(paymentRequest, userId));
    }

    private async Task NotifyRequesterAsync(PeerPaymentRequest request, string outcome, CancellationToken cancellationToken)
    {
        var payer = request.Payer;
        var (first, last) = payer is null
            ? ("A member", string.Empty)
            : PeerTransferRules.SplitName(payer.DisplayName, payer.Email);
        var body = outcome == "accepted"
            ? $"{Trim(first, last)} paid your request for {FormatMoney(request.Amount, request.Currency)}."
            : $"{Trim(first, last)} declined your request for {FormatMoney(request.Amount, request.Currency)}.";
        await pushOutbox.EnqueueAsync(
            request.CompanyInstallationId,
            request.RequesterUserId,
            $"peer-request:{request.Id}:{outcome}",
            $"peer_request.{outcome}",
            new UserPushMessage(
                outcome == "accepted" ? "Request paid" : "Request declined",
                body,
                PeerRoute,
                new Dictionary<string, string> { ["requestId"] = request.Id.ToString() }),
            DateTimeOffset.UtcNow,
            cancellationToken);
    }

    // ─── Activity ───────────────────────────────────────────────────────────

    public async Task<IReadOnlyList<PeerTransferDto>> ListRecentAsync(Guid companyId, Guid userId, int limit, CancellationToken cancellationToken)
    {
        var take = Math.Clamp(limit, 1, 100);
        var transfers = await dbContext.PeerTransfers
            .AsNoTracking()
            .Include(transfer => transfer.Sender)
            .Include(transfer => transfer.Recipient)
            .Where(transfer => transfer.CompanyInstallationId == companyId &&
                               (transfer.SenderUserId == userId || transfer.RecipientUserId == userId) &&
                               (transfer.SenderUserId == userId || transfer.Status == "completed"))
            .OrderByDescending(transfer => transfer.CreatedAt)
            .Take(take)
            .ToListAsync(cancellationToken);
        return transfers.Select(transfer => ToTransferDto(transfer, userId)).ToList();
    }

    // ─── Confirmation (step-up) ─────────────────────────────────────────────

    /// <summary>
    /// The app confirms sends with the device biometric prompt; where no
    /// biometric is available it sends the account password instead, which
    /// we verify here. Entering the duress password locks the account, the
    /// same as at sign-in.
    /// </summary>
    private async Task<ApplicationError?> VerifyConfirmationAsync(
        Guid companyId,
        Guid userId,
        string? method,
        string? password,
        CancellationToken cancellationToken)
    {
        var normalizedMethod = method?.Trim().ToLowerInvariant();
        if (normalizedMethod == "biometric" && string.IsNullOrEmpty(password))
        {
            return null;
        }

        if (string.IsNullOrEmpty(password))
        {
            return new ApplicationError("peer.confirmation.required", "Confirm this transfer with your fingerprint, face or password.", StatusCodes.Status428PreconditionRequired);
        }

        var identity = await dbContext.UserIdentities
            .Include(candidate => candidate.User)
            .Where(candidate => candidate.UserId == userId && candidate.CompanyInstallationId == companyId && candidate.PasswordHash != null)
            .OrderByDescending(candidate => candidate.IsPrimary)
            .FirstOrDefaultAsync(cancellationToken);
        if (identity?.User is null)
        {
            return new ApplicationError("peer.confirmation.unavailable", "Password confirmation is not available for this account.", StatusCodes.Status409Conflict);
        }

        if (!string.IsNullOrEmpty(identity.User.DuressPasswordHash) &&
            passwordHasher.VerifyHashedPassword(identity.User, identity.User.DuressPasswordHash, password) != PasswordVerificationResult.Failed)
        {
            await LockAccountAsync(identity.User, "duress-password", cancellationToken);
            return new ApplicationError("peer.confirmation.failed", "Confirmation failed.", StatusCodes.Status403Forbidden);
        }

        var result = passwordHasher.VerifyHashedPassword(identity.User, identity.PasswordHash!, password);
        return result == PasswordVerificationResult.Failed
            ? new ApplicationError("peer.confirmation.failed", "The password is incorrect.", StatusCodes.Status403Forbidden)
            : null;
    }

    private async Task LockAccountAsync(ApplicationUser user, string reason, CancellationToken cancellationToken)
    {
        var now = DateTimeOffset.UtcNow;
        user.LockedAt = now;
        user.LockReason = reason;
        user.Status = "locked";
        user.UpdatedAt = now;
        var sessions = await dbContext.RefreshSessions
            .Where(session => session.UserId == user.Id && session.RevokedAt == null)
            .ToListAsync(cancellationToken);
        foreach (var session in sessions)
        {
            session.RevokedAt = now;
            session.RevocationReason = "account-locked";
            session.UpdatedAt = now;
        }
        await dbContext.SaveChangesAsync(cancellationToken);
    }

    // ─── Helpers ────────────────────────────────────────────────────────────

    private static readonly string[] BlockedStatuses = ["locked", "disabled", "deleted", "suspended", "blocked", "closed"];

    private IQueryable<ApplicationUser> ActiveUsers(Guid companyId) =>
        dbContext.Users.Where(user => user.CompanyInstallationId == companyId &&
                                      !BlockedStatuses.Contains(user.Status) &&
                                      user.LockedAt == null);

    /// <summary>
    /// Finds the member on the provider by email and mirrors them locally
    /// (user row plus provider mapping) so transfers can reference them.
    /// </summary>
    private async Task<ApplicationUser?> LinkProviderUserByEmailAsync(
        Guid companyId,
        string email,
        ApplicationUser? existing,
        CancellationToken cancellationToken)
    {
        var result = await proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<object?>
            {
                Method = HttpMethod.Get,
                UpstreamPath = "/api/v2/users",
                Query = new Dictionary<string, string?>
                {
                    ["query"] = email,
                    ["pageSize"] = "25",
                    ["pageNumber"] = "1"
                },
                FailureCode = "peer.lookup.provider_failed",
                FailureMessage = "We could not search members right now."
            },
            cancellationToken);
        if (!result.IsSuccess || result.Value is null)
        {
            logger.LogWarning("Provider member search failed for lookup: {Code}", result.Error?.Code);
            return null;
        }

        JsonElement? found = null;
        foreach (var candidate in EnumerateUsers(result.Value.Value))
        {
            var candidateEmail = ReadString(candidate, "email", "Email");
            if (!string.Equals(candidateEmail, email, StringComparison.OrdinalIgnoreCase)) continue;
            var status = (ReadString(candidate, "status", "Status") ?? string.Empty).ToLowerInvariant();
            if (status is "suspended" or "blocked" or "deleted") return null;
            found = candidate;
            break;
        }

        if (found is null) return null;
        var providerUserId = ReadString(found, "id", "Id", "userId", "UserId");
        if (string.IsNullOrWhiteSpace(providerUserId)) return null;

        // Never attach a provider account that already belongs to another local user.
        var mappedElsewhere = await dbContext.ProviderMappings.AnyAsync(
            mapping => mapping.CompanyInstallationId == companyId &&
                       mapping.Provider == HoppaProvider &&
                       mapping.ProviderEntityType == "user" &&
                       mapping.ProviderEntityId == providerUserId &&
                       (existing == null || mapping.InternalEntityId != existing.Id),
            cancellationToken);
        if (mappedElsewhere)
        {
            var owner = await dbContext.ProviderMappings
                .Where(mapping => mapping.CompanyInstallationId == companyId &&
                                  mapping.Provider == HoppaProvider &&
                                  mapping.ProviderEntityType == "user" &&
                                  mapping.ProviderEntityId == providerUserId)
                .Select(mapping => mapping.InternalEntityId)
                .FirstAsync(cancellationToken);
            return await ActiveUsers(companyId).FirstOrDefaultAsync(user => user.Id == owner, cancellationToken);
        }

        var now = DateTimeOffset.UtcNow;
        var firstName = ReadString(found, "firstName", "FirstName") ?? string.Empty;
        var lastName = ReadString(found, "lastName", "LastName") ?? string.Empty;
        var user = existing;
        if (user is null)
        {
            user = new ApplicationUser
            {
                CompanyInstallationId = companyId,
                Email = email,
                EmailNormalized = email.ToUpperInvariant(),
                DisplayName = string.Join(' ', new[] { firstName, lastName }.Where(part => !string.IsNullOrWhiteSpace(part))),
                PhoneNumber = ReadString(found, "phone", "Phone", "phoneNumber", "PhoneNumber"),
                Status = "active",
                Locale = "en-US",
                MetadataJson = JsonSerializer.Serialize(new { source = "peer-lookup", accountType = ReadString(found, "accountType", "AccountType") }),
                CreatedAt = now,
                UpdatedAt = now
            };
            dbContext.Users.Add(user);
        }
        else if (string.IsNullOrWhiteSpace(user.DisplayName))
        {
            user.DisplayName = string.Join(' ', new[] { firstName, lastName }.Where(part => !string.IsNullOrWhiteSpace(part)));
            user.UpdatedAt = now;
        }

        dbContext.ProviderMappings.Add(new ProviderMapping
        {
            CompanyInstallationId = companyId,
            Provider = HoppaProvider,
            ProviderEntityType = "user",
            ProviderEntityId = providerUserId,
            InternalEntityType = "user",
            InternalEntityId = user.Id,
            ExternalStatus = (ReadString(found, "status", "Status") ?? "unknown").ToLowerInvariant(),
            LastSyncedAt = now,
            SyncStateJson = found.Value.GetRawText(),
            CreatedAt = now,
            UpdatedAt = now
        });
        await dbContext.SaveChangesAsync(cancellationToken);
        return BlockedStatuses.Contains(user.Status) || user.LockedAt is not null ? null : user;
    }

    private static IEnumerable<JsonElement> EnumerateUsers(JsonElement payload)
    {
        switch (payload.ValueKind)
        {
            case JsonValueKind.Array:
                foreach (var item in payload.EnumerateArray())
                {
                    if (item.ValueKind == JsonValueKind.Object) yield return item;
                }
                break;
            case JsonValueKind.Object:
                foreach (var key in new[] { "users", "Users", "items", "Items", "data", "Data", "result", "Result" })
                {
                    if (payload.TryGetProperty(key, out var nested))
                    {
                        foreach (var item in EnumerateUsers(nested)) yield return item;
                    }
                }
                break;
        }
    }

    private async Task<bool> HasProviderAccountAsync(Guid companyId, Guid userId, CancellationToken cancellationToken) =>
        await ProviderUserIdAsync(companyId, userId, cancellationToken) is not null;

    private Task<string?> ProviderUserIdAsync(Guid companyId, Guid userId, CancellationToken cancellationToken) =>
        dbContext.ProviderMappings
            .AsNoTracking()
            .Where(mapping => mapping.CompanyInstallationId == companyId &&
                              mapping.InternalEntityType == "user" &&
                              mapping.InternalEntityId == userId &&
                              mapping.Provider == HoppaProvider &&
                              mapping.ProviderEntityType == "user")
            .Select(mapping => mapping.ProviderEntityId)
            .FirstOrDefaultAsync(cancellationToken);

    public static PeerUserDto ToUserDto(ApplicationUser user, bool isContact)
    {
        var (first, last) = PeerTransferRules.SplitName(user.DisplayName, user.Email);
        return new PeerUserDto
        {
            UserId = user.Id.ToString(),
            Nickname = user.Nickname,
            FirstName = first,
            LastName = last,
            Initials = PeerTransferRules.Initials(first, last),
            AvatarColor = PeerTransferRules.AvatarColor(user.Id),
            MaskedEmail = PeerTransferRules.MaskEmail(user.Email),
            MaskedPhone = PeerTransferRules.MaskPhone(user.PhoneNumber),
            IsContact = isContact
        };
    }

    private static PeerTransferDto ToTransferDto(PeerTransfer transfer, Guid viewerId)
    {
        var sent = transfer.SenderUserId == viewerId;
        var other = sent ? transfer.Recipient : transfer.Sender;
        return new PeerTransferDto
        {
            Id = transfer.Id.ToString(),
            Type = sent ? "sent" : "received",
            OtherUser = other is null ? new PeerUserDto { FirstName = "Member", Initials = "?" } : ToUserDto(other, isContact: false),
            Amount = transfer.Amount,
            Currency = transfer.Currency,
            Note = transfer.Note,
            Status = transfer.Status,
            Fee = sent ? transfer.FeeAmount : 0m,
            CreatedAt = transfer.CreatedAt,
            CompletedAt = transfer.CompletedAt,
            PaymentRequestId = transfer.PaymentRequestId?.ToString(),
            ErrorMessage = sent ? transfer.ErrorMessage : null
        };
    }

    private static PeerPaymentRequestDto ToRequestDto(PeerPaymentRequest request, Guid viewerId)
    {
        var sent = request.RequesterUserId == viewerId;
        var other = sent ? request.Payer : request.Requester;
        return new PeerPaymentRequestDto
        {
            Id = request.Id.ToString(),
            Type = sent ? "sent" : "received",
            OtherUser = other is null ? new PeerUserDto { FirstName = "Member", Initials = "?" } : ToUserDto(other, isContact: false),
            Amount = request.Amount,
            Currency = request.Currency,
            Note = request.Note,
            Status = request.Status,
            CreatedAt = request.CreatedAt,
            ExpiresAt = request.ExpiresAt,
            RespondedAt = request.RespondedAt,
            TransferId = request.TransferId?.ToString()
        };
    }

    private static ApplicationResult<T> Fail<T>(string code, string message, int status, string? detail = null) =>
        ApplicationResult<T>.Failure(new ApplicationError(code, message, status, detail));

    private static string Trim(string first, string last) =>
        string.Join(' ', new[] { first, last }.Where(part => !string.IsNullOrWhiteSpace(part)));

    private static string Describe(string prefix, string? note) =>
        string.IsNullOrEmpty(note) ? prefix : $"{prefix}: {note}";

    private static string FormatMoney(decimal amount, string currency) =>
        currency == "USD"
            ? "$" + amount.ToString("N2", CultureInfo.InvariantCulture)
            : $"{amount.ToString("0.##", CultureInfo.InvariantCulture)} {currency}";

    private static string? Truncate(string? value, int length) =>
        value is null || value.Length <= length ? value : value[..length];

    /// <summary>Client errors from the provider are the customer's problem (insufficient funds); everything else is ours.</summary>
    private static int MapStatus(int upstreamStatus) => upstreamStatus switch
    {
        StatusCodes.Status400BadRequest or StatusCodes.Status404NotFound or StatusCodes.Status422UnprocessableEntity => StatusCodes.Status422UnprocessableEntity,
        StatusCodes.Status403Forbidden => StatusCodes.Status403Forbidden,
        StatusCodes.Status429TooManyRequests => StatusCodes.Status429TooManyRequests,
        _ => StatusCodes.Status502BadGateway
    };

    /// <summary>The provider's own explanation ("Insufficient balance…") beats our generic text.</summary>
    private static string? ProviderMessage(string? rawBody)
    {
        if (string.IsNullOrWhiteSpace(rawBody)) return null;
        try
        {
            using var document = JsonDocument.Parse(rawBody);
            var message = ReadString(document.RootElement, "message", "Message", "error", "Error", "detail", "title");
            if (string.IsNullOrWhiteSpace(message)) return null;
            return message.Length > 300 ? message[..300] : message;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string? ReadString(JsonElement? element, params string[] names)
    {
        if (element is null || element.Value.ValueKind != JsonValueKind.Object) return null;
        foreach (var name in names)
        {
            if (element.Value.TryGetProperty(name, out var value))
            {
                return value.ValueKind switch
                {
                    JsonValueKind.String => value.GetString(),
                    JsonValueKind.Number => value.GetRawText(),
                    JsonValueKind.True => "true",
                    JsonValueKind.False => "false",
                    _ => null
                };
            }
        }
        return null;
    }
}
