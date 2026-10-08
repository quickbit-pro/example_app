using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Cards;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using NeoBanking.Api.Cards;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/cards")]
public sealed class MobileCardsController : ApiControllerBase
{
    private readonly IProxyHoppaRequestUseCase _proxyHoppa;
    private readonly NeoBankingDbContext _dbContext;

    public MobileCardsController(
        IProxyHoppaRequestUseCase proxyHoppa,
        NeoBankingDbContext dbContext)
    {
        _proxyHoppa = proxyHoppa;
        _dbContext = dbContext;
    }

    [HttpGet]
    public async Task<ActionResult<JsonElement?>> ListCards(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendCardRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "cards",
            null,
            "mobile.cards.list.failed",
            "We could not list cards.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("discount-codes/validate")]
    public async Task<ActionResult<JsonElement?>> ValidateDiscountCode(
        [FromBody] CardDiscountCodeRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
            return MissingIdentity<JsonElement?>();

        if (!int.TryParse(userId, out var numericUserId) || numericUserId <= 0 ||
            string.IsNullOrWhiteSpace(request.Code) || request.Code.Trim().Length > 100)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.cards.discount.invalid_request", "Enter a valid discount code.",
                StatusCodes.Status400BadRequest)));
        }

        return ToActionResult(await SendCardRequestAsync(
            userId, HttpMethod.Post, "discount-codes/validate",
            new { UserId = numericUserId, Code = request.Code.Trim().ToUpperInvariant() },
            "mobile.cards.discount.failed", "We could not validate this discount code.",
            cancellationToken));
    }

    public sealed class CardDiscountCodeRequest
    {
        public string? Code { get; init; }
    }

    [HttpPost]
    public async Task<ActionResult<JsonElement?>> CreateCard(
        [FromBody] CreateCardRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var enrichedRequest = await EnrichCreateCardRequestAsync(request, userId, cancellationToken);
        if (!enrichedRequest.IsSuccess)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(enrichedRequest.Error!));
        }

        await RecordCardOrderAgreementsAsync(request.LegalAgreements, cancellationToken);

        var order = await SendCardRequestAsync(
            userId,
            HttpMethod.Post,
            "cards",
            CreateCardUpstreamRequestDto.From(enrichedRequest.Value!, userId),
            "mobile.cards.create.failed",
            "We could not create card.",
            cancellationToken);
        if (!order.IsSuccess)
        {
            order = ApplicationResult<JsonElement?>.Failure(CardOrderFailures.Translate(order.Error!));
        }

        return ToActionResult(order);
    }

    [HttpGet("{cardId}")]
    public async Task<ActionResult<JsonElement?>> GetCard(string cardId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendCardRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"cards/{Segment(cardId)}",
            null,
            "mobile.cards.get.failed",
            "We could not load card.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("{cardId}/activate")]
    public async Task<ActionResult<JsonElement?>> ActivateCard(
        string cardId,
        [FromBody] UpdateCardStatusRequestDto request,
        CancellationToken cancellationToken)
    {
        return await CardLifecycleAction(cardId, "activate", "activate", cancellationToken);
    }

    [HttpPost("{cardId}/freeze")]
    public async Task<ActionResult<JsonElement?>> FreezeCard(
        string cardId,
        [FromBody] UpdateCardStatusRequestDto request,
        CancellationToken cancellationToken)
    {
        return await CardLifecycleAction(cardId, "freeze", "freeze", cancellationToken);
    }

    [HttpPost("{cardId}/unfreeze")]
    public async Task<ActionResult<JsonElement?>> UnfreezeCard(
        string cardId,
        [FromBody] UpdateCardStatusRequestDto request,
        CancellationToken cancellationToken)
    {
        return await CardLifecycleAction(cardId, "enable", "enable", cancellationToken);
    }

    [HttpPost("{cardId}/enable")]
    public async Task<ActionResult<JsonElement?>> EnableCard(
        string cardId,
        [FromBody] UpdateCardStatusRequestDto request,
        CancellationToken cancellationToken)
    {
        return await CardLifecycleAction(cardId, "enable", "enable", cancellationToken);
    }

    [HttpPost("{cardId}/cancel")]
    public async Task<ActionResult<JsonElement?>> CancelCard(
        string cardId,
        [FromBody] UpdateCardStatusRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = cardId;
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "mobile.cards.cancel.unsupported",
            "This action is not available yet.");
    }

    [HttpDelete("{cardId}")]
    public async Task<ActionResult<JsonElement?>> DeleteCard(string cardId, CancellationToken cancellationToken)
    {
        _ = cardId;
        _ = cancellationToken;

        return NotImplementedProblem(
            "mobile.cards.delete.unsupported",
            "This action is not available yet.");
    }

    [HttpPost("{cardId}/replace")]
    public async Task<ActionResult<JsonElement?>> ReplaceCard(
        string cardId,
        [FromBody] ReplaceCardRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = cardId;
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "mobile.cards.replace.unsupported",
            "This action is not available yet.");
    }

    /// <summary>Current limits (as last set through the app) and the tier ceilings for this card.</summary>
    [HttpGet("{cardId}/limits")]
    public async Task<ActionResult<CardLimitsResponseDto>> GetLimits(string cardId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<CardLimitsResponseDto>();
        }

        var context = await LoadCardLimitContextAsync(userId, cardId, cancellationToken);
        if (!context.IsSuccess)
        {
            return ToActionResult(ApplicationResult<CardLimitsResponseDto>.Failure(context.Error!));
        }

        return Ok(await BuildLimitsResponseAsync(cardId, context.Value!, cancellationToken));
    }

    [HttpPatch("{cardId}/limits")]
    public async Task<ActionResult<CardLimitsResponseDto>> UpdateLimits(
        string cardId,
        [FromBody] UpdateCardLimitsRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<CardLimitsResponseDto>();
        }

        if (request.Daily is null && request.Weekly is null && request.Monthly is null)
        {
            return ToActionResult(ApplicationResult<CardLimitsResponseDto>.Failure(new ApplicationError(
                "mobile.cards.limits.empty",
                "Enter at least one limit.",
                StatusCodes.Status400BadRequest)));
        }

        var context = await LoadCardLimitContextAsync(userId, cardId, cancellationToken);
        if (!context.IsSuccess)
        {
            return ToActionResult(ApplicationResult<CardLimitsResponseDto>.Failure(context.Error!));
        }

        var caps = context.Value!.Caps;
        var validation = CardLimitPolicy.ValidationError(request.Daily, request.Weekly, request.Monthly, caps);
        if (validation is not null)
        {
            return ToActionResult(ApplicationResult<CardLimitsResponseDto>.Failure(new ApplicationError(
                "mobile.cards.limits.exceeds_tier",
                validation,
                StatusCodes.Status422UnprocessableEntity)));
        }

        // One provider call per period: the provider reports a single
        // success flag for all of them, so separate calls tell the customer
        // which limit the issuer refused and keep the ones it accepted.
        var upstreamRequest = UpdateCardLimitsUpstreamRequestDto.From(request);
        var accepted = new List<(string Period, decimal Value)>();
        var refused = new List<string>();
        string? refusalDetail = null;
        foreach (var (period, value) in new[]
                 {
                     ("daily", upstreamRequest.Daily),
                     ("weekly", upstreamRequest.Weekly),
                     ("monthly", upstreamRequest.Monthly),
                 })
        {
            if (value is null) continue;
            var upstream = await SendCardRequestAsync(
                userId,
                HttpMethod.Put,
                $"cards/{Segment(cardId)}/limits",
                new UpdateCardLimitsUpstreamRequestDto
                {
                    Daily = period == "daily" ? value : null,
                    Weekly = period == "weekly" ? value : null,
                    Monthly = period == "monthly" ? value : null
                },
                "mobile.cards.limits.update.failed",
                "We could not update card limits.",
                cancellationToken,
                UserIdQuery(userId));
            if (!upstream.IsSuccess)
            {
                refused.Add(period);
                refusalDetail ??= upstream.Error!.Detail ?? upstream.Error.Message;
                continue;
            }

            if (upstream.Value is JsonElement { ValueKind: JsonValueKind.Object } body &&
                body.TryGetProperty("success", out var success) &&
                success.ValueKind == JsonValueKind.False)
            {
                refused.Add(period);
                refusalDetail ??= body.GetRawText();
                continue;
            }

            accepted.Add((period, value.Value));
        }

        var stored = await ReadStoredLimitsAsync(cardId, cancellationToken);
        if (accepted.Count > 0)
        {
            decimal? Pick(string period, decimal? previous) =>
                accepted.FirstOrDefault(entry => entry.Period == period) is { Period: not null } hit ? hit.Value : previous;
            await SaveStoredLimitsAsync(
                cardId,
                new StoredCardLimits(
                    Pick("daily", stored?.Daily),
                    Pick("weekly", stored?.Weekly),
                    Pick("monthly", stored?.Monthly),
                    string.IsNullOrWhiteSpace(request.Currency) ? stored?.Currency ?? context.Value.Currency : request.Currency.Trim().ToUpperInvariant(),
                    DateTimeOffset.UtcNow),
                cancellationToken);
        }

        if (refused.Count > 0)
        {
            var periods = string.Join(" and ", refused);
            var suffix = accepted.Count > 0
                ? $" The {string.Join(" and ", accepted.Select(entry => entry.Period))} limit was saved."
                : string.Empty;
            return ToActionResult(ApplicationResult<CardLimitsResponseDto>.Failure(new ApplicationError(
                "mobile.cards.limits.update.failed",
                $"The card issuer did not accept the {periods} limit.{suffix}",
                StatusCodes.Status422UnprocessableEntity,
                refusalDetail)));
        }

        return Ok(await BuildLimitsResponseAsync(cardId, context.Value, cancellationToken));
    }

    private sealed record CardLimitContext(CardLimitCaps Caps, string Currency, string? TierName);

    /// <summary>
    /// Reads the card to learn its card-type tier and tier, then the ceilings:
    /// the card type's own limits first, the tier's limits otherwise.
    /// </summary>
    private async Task<ApplicationResult<CardLimitContext>> LoadCardLimitContextAsync(
        string userId,
        string cardId,
        CancellationToken cancellationToken)
    {
        var cardResult = await SendCardRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"cards/{Segment(cardId)}",
            null,
            "mobile.cards.get.failed",
            "We could not load card.",
            cancellationToken,
            UserIdQuery(userId));
        if (!cardResult.IsSuccess)
        {
            return ApplicationResult<CardLimitContext>.Failure(cardResult.Error!);
        }

        var card = UnwrapObject(cardResult.Value);
        var currency = ReadString(card, "currency", "Currency") ?? "USD";
        var cardTypeTierId = ReadInt(card, "cardTypeTierId", "CardTypeTierId");
        var cardTypeId = ReadInt(card, "cardTypeId", "CardTypeId");
        var tierId = ReadInt(card, "tierId", "TierId");

        // The card-tier endpoint takes the parent tier id and returns every
        // card-type tier of that tier; the card's own row is picked from it.
        JsonElement? cardTierPayload = null;
        if (tierId is > 0)
        {
            var cardTier = await SendCardRequestAsync<object?>(
                userId,
                HttpMethod.Get,
                $"tiers/card-tier/{tierId.Value}",
                null,
                "mobile.tiers.card_tier.failed",
                "We could not load the card tier.",
                cancellationToken);
            if (cardTier.IsSuccess)
            {
                cardTierPayload = CardLimitPolicy.FindCardTypeTier(cardTier.Value, cardTypeTierId, cardTypeId);
            }
        }

        JsonElement? tierPayload = null;
        string? tierName = null;
        if (tierId is > 0)
        {
            var tiers = await SendCardRequestAsync<object?>(
                userId,
                HttpMethod.Get,
                "tiers",
                null,
                "mobile.tiers.list.failed",
                "We could not load tiers.",
                cancellationToken,
                UserIdQuery(userId));
            if (tiers.IsSuccess)
            {
                tierPayload = CardLimitPolicy.FindTier(tiers.Value, tierId.Value);
                tierName = tierPayload is null ? null : ReadString(tierPayload.Value, "name", "Name", "tierName", "TierName", "displayName", "DisplayName");
            }
        }

        return ApplicationResult<CardLimitContext>.Success(new CardLimitContext(
            CardLimitPolicy.ResolveCaps(cardTierPayload, tierPayload),
            currency,
            tierName));
    }

    private async Task<CardLimitsResponseDto> BuildLimitsResponseAsync(string cardId, CardLimitContext context, CancellationToken cancellationToken)
    {
        var stored = await ReadStoredLimitsAsync(cardId, cancellationToken);
        return new CardLimitsResponseDto
        {
            Currency = stored?.Currency ?? context.Currency,
            Current = stored is null
                ? null
                : new CardLimitValuesDto { Daily = stored.Daily, Weekly = stored.Weekly, Monthly = stored.Monthly, UpdatedAt = stored.UpdatedAt },
            Caps = new CardLimitValuesDto { Daily = context.Caps.Daily, Weekly = context.Caps.Weekly, Monthly = context.Caps.Monthly },
            CapSource = context.Caps.Source,
            TierName = context.TierName,
            CanUpdate = true
        };
    }

    private async Task<StoredCardLimits?> ReadStoredLimitsAsync(string cardId, CancellationToken cancellationToken)
    {
        var user = await GetCurrentLocalUserAsync(cancellationToken);
        if (user is null) return null;
        try
        {
            using var document = JsonDocument.Parse(string.IsNullOrWhiteSpace(user.MetadataJson) ? "{}" : user.MetadataJson);
            if (!document.RootElement.TryGetProperty("cardLimits", out var all) || all.ValueKind != JsonValueKind.Object ||
                !all.TryGetProperty(CardLimitPolicy.StorageKey(cardId), out var entry) || entry.ValueKind != JsonValueKind.Object)
            {
                return null;
            }

            return new StoredCardLimits(
                ReadDecimal(entry, "daily"),
                ReadDecimal(entry, "weekly"),
                ReadDecimal(entry, "monthly"),
                ReadString(entry, "currency") ?? "USD",
                entry.TryGetProperty("updatedAt", out var updated) && updated.TryGetDateTimeOffset(out var at) ? at : DateTimeOffset.MinValue);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private async Task SaveStoredLimitsAsync(string cardId, StoredCardLimits limits, CancellationToken cancellationToken)
    {
        // Tracked load: the shared lookup uses AsNoTracking and a change on
        // that copy would never reach the database.
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var parsedUserId)) return;
        var user = await _dbContext.Users.SingleOrDefaultAsync(candidate => candidate.Id == parsedUserId, cancellationToken);
        if (user is null) return;
        Dictionary<string, object?> metadata;
        try
        {
            metadata = JsonSerializer.Deserialize<Dictionary<string, object?>>(string.IsNullOrWhiteSpace(user.MetadataJson) ? "{}" : user.MetadataJson) ?? new();
        }
        catch (JsonException)
        {
            metadata = new();
        }

        var all = new Dictionary<string, object?>();
        if (metadata.TryGetValue("cardLimits", out var existing) && existing is JsonElement { ValueKind: JsonValueKind.Object } element)
        {
            foreach (var property in element.EnumerateObject())
            {
                all[property.Name] = property.Value;
            }
        }

        all[CardLimitPolicy.StorageKey(cardId)] = new
        {
            daily = limits.Daily,
            weekly = limits.Weekly,
            monthly = limits.Monthly,
            currency = limits.Currency,
            updatedAt = limits.UpdatedAt
        };
        metadata["cardLimits"] = all;
        user.MetadataJson = JsonSerializer.Serialize(metadata);
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await _dbContext.SaveChangesAsync(cancellationToken);
    }

    private static JsonElement UnwrapObject(JsonElement? payload)
    {
        if (payload is null || payload.Value.ValueKind != JsonValueKind.Object) return default;
        var current = payload.Value;
        foreach (var key in new[] { "data", "Data", "result", "Result", "card", "Card" })
        {
            if (current.TryGetProperty(key, out var nested) && nested.ValueKind == JsonValueKind.Object) current = nested;
        }

        return current;
    }

    private static string? ReadString(JsonElement element, params string[] keys)
    {
        if (element.ValueKind != JsonValueKind.Object) return null;
        foreach (var key in keys)
        {
            if (element.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String)
            {
                var text = value.GetString()?.Trim();
                if (!string.IsNullOrEmpty(text)) return text;
            }
        }

        return null;
    }

    private static int? ReadInt(JsonElement element, params string[] keys)
    {
        if (element.ValueKind != JsonValueKind.Object) return null;
        foreach (var key in keys)
        {
            if (!element.TryGetProperty(key, out var value)) continue;
            if (value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var number)) return number;
            if (value.ValueKind == JsonValueKind.String && int.TryParse(value.GetString(), out var parsed)) return parsed;
        }

        return null;
    }

    private static decimal? ReadDecimal(JsonElement element, string key)
    {
        if (!element.TryGetProperty(key, out var value)) return null;
        return value.ValueKind == JsonValueKind.Number && value.TryGetDecimal(out var number) ? number : null;
    }

    [HttpPatch("{cardId}/pin")]
    public async Task<ActionResult<JsonElement?>> UpdatePin(
        string cardId,
        [FromBody] UpdateCardPinRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        // A tokenised PIN (PinToken) was chosen through the provider's widget and
        // is validated there; a plain PIN must satisfy the bank rules here.
        if (string.IsNullOrEmpty(request.PinToken))
        {
            var pinError = CardPinPolicy.Validate(request.Pin);
            if (pinError is not null)
            {
                return ToActionResult(ApplicationResult<JsonElement?>.Failure(pinError));
            }
        }

        return ToActionResult(await SendCardRequestAsync(
            userId,
            HttpMethod.Put,
            $"cards/{Segment(cardId)}/pin",
            UpdateCardPinUpstreamRequestDto.From(request),
            "mobile.cards.pin.update.failed",
            "We could not update card PIN.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpGet("quantum-topup/estimate")]
    public async Task<ActionResult<JsonElement?>> EstimateQuantumTopUp(
        [FromQuery] decimal? amount,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendCardRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "cards/quantum-topup/estimate",
            null,
            "mobile.cards.topup.estimate.failed",
            "We could not estimate card top-up.",
            cancellationToken,
            Query(("userId", userId), ("amount", amount))));
    }

    /// <summary>Smallest load the card issuer accepts.</summary>
    public const decimal CardTopUpMinimum = 10m;

    private static ApplicationError TopUpBelowMinimum() => new(
        "mobile.cards.topup.below_minimum",
        "The minimum card load is 10.00 USD.",
        StatusCodes.Status400BadRequest);

    [HttpPost("topup")]
    public async Task<ActionResult<JsonElement?>> TopUpCard(
        [FromBody] CardTopUpRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        if (request.Value < CardTopUpMinimum)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(TopUpBelowMinimum()));
        }

        return ToActionResult(await SendCardRequestAsync(
            userId,
            HttpMethod.Post,
            "cards/topup",
            CardTopUpUpstreamRequestDto.From(request),
            "mobile.cards.topup.failed",
            "We could not top up card.",
            cancellationToken));
    }

    [HttpPost("{cardId}/load")]
    public async Task<ActionResult<JsonElement?>> LoadCard(
        string cardId,
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var upstream = CardTopUpUpstreamRequestDto.From(request, cardId);
        if (upstream.Value < CardTopUpMinimum)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(TopUpBelowMinimum()));
        }

        return ToActionResult(await SendCardRequestAsync(
            userId,
            HttpMethod.Post,
            "cards/topup",
            upstream,
            "mobile.cards.topup.failed",
            "We could not top up card.",
            cancellationToken));
    }

    [HttpPost("unload")]
    public async Task<ActionResult<JsonElement?>> UnloadCard(
        [FromBody] CardUnloadRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendCardRequestAsync(
            userId,
            HttpMethod.Post,
            "cards/unload-card",
            CardUnloadUpstreamRequestDto.From(request),
            "mobile.cards.unload.failed",
            "We could not unload card.",
            cancellationToken));
    }

    [HttpPost("{cardId}/unload")]
    public async Task<ActionResult<JsonElement?>> UnloadCardById(
        string cardId,
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendCardRequestAsync(
            userId,
            HttpMethod.Post,
            "cards/unload-card",
            CardUnloadUpstreamRequestDto.From(request, cardId),
            "mobile.cards.unload.failed",
            "We could not unload card.",
            cancellationToken));
    }

    [HttpGet("{cardId}/widget")]
    public async Task<ActionResult<JsonElement?>> GetWidget(string cardId, CancellationToken cancellationToken)
    {
        return await GetWidgetData(cardId, cancellationToken);
    }

    [HttpGet("{cardId}/widget/secret-data")]
    [HttpGet("{cardId}/secret-data")]
    public async Task<ActionResult<JsonElement?>> GetSecretData(string cardId, CancellationToken cancellationToken)
    {
        return await GetWidgetData(cardId, cancellationToken);
    }

    [HttpGet("{cardId}/transactions")]
    public async Task<ActionResult<JsonElement?>> ListCardTransactions(
        string cardId,
        [FromQuery] int? limit,
        [FromQuery] int? page,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendCardRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"cards/{Segment(cardId)}/transactions",
            null,
            "mobile.cards.transactions.list.failed",
            "We could not list card transactions.",
            cancellationToken,
            Query(("userId", userId), ("limit", limit), ("page", page))));
    }

    [HttpGet("{cardId}/controls")]
    public async Task<ActionResult<JsonElement?>> GetControls(
        string cardId,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var result = await SendCardRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"cards/{Segment(cardId)}",
            null,
            "mobile.cards.controls.failed",
            "We could not load card control capabilities.",
            cancellationToken,
            UserIdQuery(userId));
        if (!result.IsSuccess)
        {
            return ToActionResult(result);
        }

        return Ok(JsonSerializer.SerializeToElement(CardControlCapabilitiesMapper.Map(result.Value) with
        {
            AutoFreezeEnabled = HoppaCardAutoFreeze.ReadEnabled(result.Value) ?? false,
            AutoFreezeActiveUntil = HoppaCardAutoFreeze.ReadActiveUntil(result.Value)
        }));
    }

    /// <summary>
    /// Turns the issuer's auto lock ("Auto freeze") on or off for a card.
    /// Hoppa does the freezing itself, ten minutes after the card is
    /// unfrozen; this only forwards the switch, so a card the caller does not
    /// own is refused by the issuer like every other card route.
    /// </summary>
    [HttpPatch("{cardId}/auto-freeze")]
    public async Task<ActionResult<CardAutoFreezeResponseDto>> UpdateAutoFreeze(
        string cardId,
        [FromBody] UpdateCardAutoFreezeRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<CardAutoFreezeResponseDto>();
        }

        if (request.Enabled is null)
        {
            return ToActionResult(ApplicationResult<CardAutoFreezeResponseDto>.Failure(new ApplicationError(
                "mobile.cards.auto_freeze.empty",
                "Choose whether auto freeze should be on or off.",
                StatusCodes.Status400BadRequest)));
        }

        var enabled = request.Enabled.Value;
        var upstream = await SendCardRequestAsync(
            userId,
            HttpMethod.Put,
            HoppaCardAutoFreeze.SettingPath(Segment(cardId)),
            new UpdateCardAutoFreezeUpstreamRequestDto { Enabled = enabled },
            "mobile.cards.auto_freeze.update.failed",
            "We could not update auto freeze for this card.",
            cancellationToken,
            UserIdQuery(userId));
        if (!upstream.IsSuccess)
        {
            return ToActionResult(ApplicationResult<CardAutoFreezeResponseDto>.Failure(upstream.Error!));
        }

        // The issuer's answer is the truth; the request is only the fallback
        // for a reply that omits the flag.
        var nowEnabled = HoppaCardAutoFreeze.ReadEnabled(upstream.Value) ?? enabled;
        return Ok(new CardAutoFreezeResponseDto
        {
            Enabled = nowEnabled,
            ActiveUntil = HoppaCardAutoFreeze.ReadActiveUntil(upstream.Value),
            Message = nowEnabled
                ? "Auto freeze is on. This card freezes itself again 10 minutes after you unfreeze it."
                : "Auto freeze is off."
        });
    }

    [HttpGet("holders")]
    public async Task<ActionResult<JsonElement?>> ListCardHolders(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendCardRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "cards/cardHolders",
            null,
            "mobile.cards.holders.list.failed",
            "We could not list card holders.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    private async Task<ActionResult<JsonElement?>> GetWidgetData(string cardId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendCardRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"cards/{Segment(cardId)}/widget",
            null,
            "mobile.cards.widget.failed",
            "We could not load card widget data.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    private async Task<ActionResult<JsonElement?>> CardLifecycleAction(
        string cardId,
        string action,
        string failureVerb,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendCardRequestAsync(
            userId,
            HttpMethod.Post,
            $"cards/{Segment(cardId)}/{action}",
            (object?)null,
            $"mobile.cards.{action}.failed",
            $"We could not {failureVerb} card.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    private Task<NeoBanking.Application.Common.ApplicationResult<JsonElement?>> SendCardRequestAsync<TRequest>(
        string userId,
        HttpMethod method,
        string relativePath,
        TRequest? request,
        string failureCode,
        string failureMessage,
        CancellationToken cancellationToken,
        IReadOnlyDictionary<string, string?>? query = null)
    {
        return _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<TRequest>
            {
                Method = method,
                UpstreamPath = $"/api/v2/{relativePath}",
                Query = query ?? new Dictionary<string, string?>(),
                Request = request,
                FailureCode = failureCode,
                FailureMessage = failureMessage
            },
            cancellationToken);
    }

    private static IReadOnlyDictionary<string, string?> UserIdQuery(string userId)
    {
        return new Dictionary<string, string?> { ["userId"] = userId };
    }

    /// <summary>
    /// Bare national numbers stored by older sign-ups carry no country; they
    /// were always sent with this dial code, which is kept for compatibility.
    /// </summary>
    private const string LegacyFallbackDialCode = "1";

    /// <summary>
    /// The card issuer rejects an order without a phone number and the order
    /// screen does not ask for one, so it comes from the local profile. An
    /// account connected from an existing Hoppa profile may have no local
    /// phone yet; then the Hoppa profile is asked and the number is stored
    /// for the next order. Without any number, or with one libphonenumber
    /// rejects, the order is refused here with a message the customer can
    /// act on, instead of the issuer's 400.
    /// </summary>
    private async Task<ApplicationResult<CreateCardRequestDto>> EnrichCreateCardRequestAsync(
        CreateCardRequestDto request,
        string hoppaUserId,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(request.Phone) && !string.IsNullOrWhiteSpace(request.PhoneCode))
        {
            return ApplicationResult<CreateCardRequestDto>.Success(request);
        }

        var candidate = request.Phone;
        var parsedPhone = PhoneNumberParser.Split(request.Phone, request.PhoneCode);
        if (parsedPhone is null)
        {
            var user = await GetCurrentLocalUserAsync(cancellationToken, track: true);
            candidate = user?.PhoneNumber;
            parsedPhone = PhoneNumberParser.Split(candidate, LegacyFallbackDialCode);
            if (parsedPhone is null && string.IsNullOrWhiteSpace(candidate))
            {
                candidate = await FetchHoppaProfilePhoneAsync(hoppaUserId, cancellationToken);
                parsedPhone = PhoneNumberParser.Split(candidate, LegacyFallbackDialCode);
                if (parsedPhone is not null && user is not null)
                {
                    await PersistPhoneNumberAsync(user, candidate!, cancellationToken);
                }
            }
        }

        if (parsedPhone is null)
        {
            return ApplicationResult<CreateCardRequestDto>.Failure(string.IsNullOrWhiteSpace(candidate)
                ? new ApplicationError(
                    "mobile.cards.create.phone_required",
                    "A phone number is required to order a card, but none is saved on your account. Contact support to add one.",
                    StatusCodes.Status422UnprocessableEntity)
                : new ApplicationError(
                    "mobile.cards.create.phone_invalid",
                    "The phone number saved on your account is not a valid number. Contact support to correct it before ordering a card.",
                    StatusCodes.Status422UnprocessableEntity));
        }

        return ApplicationResult<CreateCardRequestDto>.Success(CopyCreateCardRequest(
            request,
            phone: parsedPhone.Value.Phone,
            phoneCode: parsedPhone.Value.PhoneCode));
    }

    private async Task<string?> FetchHoppaProfilePhoneAsync(string hoppaUserId, CancellationToken cancellationToken)
    {
        var profile = await SendCardRequestAsync<object?>(
            hoppaUserId,
            HttpMethod.Get,
            $"users/{Segment(hoppaUserId)}",
            null,
            "mobile.profile.get.failed",
            "We could not load your profile.",
            cancellationToken);
        if (!profile.IsSuccess)
        {
            return null;
        }

        var phone = ReadString(UnwrapObject(profile.Value), "phone", "Phone", "phoneNumber", "PhoneNumber")?.Trim();
        return string.IsNullOrWhiteSpace(phone) ? null : phone;
    }

    private async Task PersistPhoneNumberAsync(ApplicationUser user, string phone, CancellationToken cancellationToken)
    {
        try
        {
            user.PhoneNumber = phone;
            user.UpdatedAt = DateTimeOffset.UtcNow;
            await _dbContext.SaveChangesAsync(cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            // Remembering the number is a convenience; the order still goes out with it.
        }
    }

    /// <summary>
    /// Keeps the consent record with the user so support can show which
    /// documents were accepted for each card order. Never blocks the order.
    /// </summary>
    private async Task RecordCardOrderAgreementsAsync(
        Dictionary<string, object?>? agreements,
        CancellationToken cancellationToken)
    {
        if (agreements is null || agreements.Count == 0)
        {
            return;
        }
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var parsedUserId))
        {
            return;
        }

        try
        {
            var user = await _dbContext.Users.SingleOrDefaultAsync(u => u.Id == parsedUserId, cancellationToken);
            if (user is null)
            {
                return;
            }

            Dictionary<string, object?> metadata;
            try
            {
                metadata = JsonSerializer.Deserialize<Dictionary<string, object?>>(user.MetadataJson) ?? new();
            }
            catch (JsonException)
            {
                metadata = new();
            }

            var history = new List<object?>();
            if (metadata.TryGetValue("cardOrderLegalAgreements", out var existing) &&
                existing is JsonElement { ValueKind: JsonValueKind.Array } array)
            {
                history.AddRange(array.EnumerateArray().Select(item => (object?)item));
            }
            history.Add(agreements);
            metadata["cardOrderLegalAgreements"] = history;
            user.MetadataJson = JsonSerializer.Serialize(metadata);
            user.UpdatedAt = DateTimeOffset.UtcNow;
            await _dbContext.SaveChangesAsync(cancellationToken);
        }
        catch (Exception)
        {
            // Consent bookkeeping must not fail the card order itself.
        }
    }

    private async Task<ApplicationUser?> GetCurrentLocalUserAsync(CancellationToken cancellationToken, bool track = false)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var parsedUserId))
        {
            return null;
        }

        IQueryable<ApplicationUser> users = _dbContext.Users;
        if (!track)
        {
            users = users.AsNoTracking();
        }

        return await users.SingleOrDefaultAsync(user => user.Id == parsedUserId, cancellationToken);
    }

    private static CreateCardRequestDto CopyCreateCardRequest(
        CreateCardRequestDto request,
        string? phone,
        string? phoneCode)
    {
        return new CreateCardRequestDto
        {
            ProductCode = request.ProductCode,
            CardTypeId = request.CardTypeId,
            ExternalCardId = request.ExternalCardId,
            Nickname = request.Nickname,
            Currency = request.Currency,
            CardName = request.CardName,
            BudgetId = request.BudgetId,
            BillingAddress = request.BillingAddress,
            DeliveryAddress = request.DeliveryAddress,
            Phone = phone,
            PhoneCode = phoneCode,
            DesignId = request.DesignId,
            PhysicalCardDesignId = request.PhysicalCardDesignId,
            DiscountCode = request.DiscountCode
        };
    }

}
