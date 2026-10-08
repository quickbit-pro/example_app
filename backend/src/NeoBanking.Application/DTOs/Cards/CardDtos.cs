using System.Text.Json;

namespace NeoBanking.Application.DTOs.Cards;

public sealed class CardSummaryDto
{
    public string? CardId { get; init; }

    public string? Last4 { get; init; }

    public string? Brand { get; init; }

    public string? Status { get; init; }
}

public sealed class CreateCardRequestDto
{
    public string? ProductCode { get; init; }

    public int? CardTypeId { get; init; }

    public string? ExternalCardId { get; init; }

    public string? Nickname { get; init; }

    public string? Currency { get; init; }

    public string? CardName { get; init; }

    public string? BudgetId { get; init; }

    public AddressDto? BillingAddress { get; init; }

    public AddressDto? DeliveryAddress { get; init; }

    public string? Phone { get; init; }

    public string? PhoneCode { get; init; }

    public string? DesignId { get; init; }

    public string? PhysicalCardDesignId { get; init; }

    public string? DiscountCode { get; init; }

    /// <summary>Legal agreements the customer accepted when placing this order.</summary>
    public Dictionary<string, object?>? LegalAgreements { get; init; }
}

public sealed class CreateCardResponseDto
{
    public string? CardId { get; init; }

    public string? Status { get; init; }
}

public sealed class UpdateCardStatusRequestDto
{
    public string? Reason { get; init; }
}

public sealed class UpdateCardAutoFreezeRequestDto
{
    public bool? Enabled { get; init; }
}

/// <summary>The issuer's auto-freeze switch for one card, after this backend forwarded a change.</summary>
public sealed class CardAutoFreezeResponseDto
{
    public bool Enabled { get; init; }

    /// <summary>When the current unfreeze window ends; null while frozen or off.</summary>
    public DateTimeOffset? ActiveUntil { get; init; }

    public string Message { get; init; } = string.Empty;
}

/// <summary>Body forwarded to the issuer's auto-freeze setting.</summary>
public sealed class UpdateCardAutoFreezeUpstreamRequestDto
{
    public bool Enabled { get; init; }
}

public sealed class ReplaceCardRequestDto
{
    public string? Reason { get; init; }

    public string? ShippingAddressId { get; init; }
}

public sealed class UpdateCardLimitsRequestDto
{
    public decimal? Daily { get; init; }

    public decimal? Weekly { get; init; }

    public decimal? Monthly { get; init; }

    public decimal? DailyPurchaseLimit { get; init; }

    public decimal? DailyAtmLimit { get; init; }

    public string? Currency { get; init; }
}

public sealed class UpdateCardPinRequestDto
{
    public string? Pin { get; init; }

    public string? PinToken { get; init; }
}

public sealed class CardTopUpRequestDto
{
    public int? CardId { get; init; }

    public string? Token { get; init; }

    public decimal Value { get; init; }
}

public sealed class CardUnloadRequestDto
{
    public int? CardId { get; init; }

    public string? Currency { get; init; }

    public decimal Value { get; init; }
}

public sealed class CardTopUpUpstreamRequestDto
{
    public int? CardId { get; init; }

    public string? Token { get; init; }

    public decimal Value { get; init; }

    public static CardTopUpUpstreamRequestDto From(CardTopUpRequestDto request)
    {
        return new CardTopUpUpstreamRequestDto
        {
            CardId = request.CardId,
            Token = request.Token,
            Value = request.Value
        };
    }

    public static CardTopUpUpstreamRequestDto From(JsonElement request, string cardId)
    {
        return new CardTopUpUpstreamRequestDto
        {
            CardId = CardDtoJsonHelpers.TryGetInt32(request, "CardId") ?? CardDtoJsonHelpers.TryGetInt32(request, "cardId") ?? CardDtoJsonHelpers.ParseCardId(cardId),
            Token = CardDtoJsonHelpers.TryGetString(request, "Token") ?? CardDtoJsonHelpers.TryGetString(request, "token"),
            Value = CardDtoJsonHelpers.TryGetDecimal(request, "Value") ?? CardDtoJsonHelpers.TryGetDecimal(request, "value") ?? CardDtoJsonHelpers.TryGetDecimal(request, "Amount") ?? CardDtoJsonHelpers.TryGetDecimal(request, "amount") ?? 0
        };
    }
}

public sealed class CardUnloadUpstreamRequestDto
{
    public int? CardId { get; init; }

    public string? Currency { get; init; }

    public decimal Value { get; init; }

    public static CardUnloadUpstreamRequestDto From(CardUnloadRequestDto request)
    {
        return new CardUnloadUpstreamRequestDto
        {
            CardId = request.CardId,
            Currency = request.Currency,
            Value = request.Value
        };
    }

    public static CardUnloadUpstreamRequestDto From(JsonElement request, string cardId)
    {
        return new CardUnloadUpstreamRequestDto
        {
            CardId = CardDtoJsonHelpers.TryGetInt32(request, "CardId") ?? CardDtoJsonHelpers.TryGetInt32(request, "cardId") ?? CardDtoJsonHelpers.ParseCardId(cardId),
            Currency = CardDtoJsonHelpers.TryGetString(request, "Currency") ?? CardDtoJsonHelpers.TryGetString(request, "currency"),
            Value = CardDtoJsonHelpers.TryGetDecimal(request, "Value") ?? CardDtoJsonHelpers.TryGetDecimal(request, "value") ?? CardDtoJsonHelpers.TryGetDecimal(request, "Amount") ?? CardDtoJsonHelpers.TryGetDecimal(request, "amount") ?? 0
        };
    }
}

public sealed class AddressDto
{
    public string? Line1 { get; init; }

    public string? Line2 { get; init; }

    public string? City { get; init; }

    public string? State { get; init; }

    public string? PostalCode { get; init; }

    public string? Country { get; init; }
}

public sealed class CreateCardUpstreamRequestDto
{
    public object? UserId { get; init; }

    public int? CardTypeId { get; init; }

    public string? ExternalCardId { get; init; }

    public string? Nickname { get; init; }

    public string? Currency { get; init; }

    public string? CardName { get; init; }

    public string? BudgetId { get; init; }

    public AddressDto? BillingAddress { get; init; }

    public AddressDto? DeliveryAddress { get; init; }

    public string? Phone { get; init; }

    public string? PhoneCode { get; init; }

    public string? DesignId { get; init; }

    public string? PhysicalCardDesignId { get; init; }

    public string? DiscountCode { get; init; }

    public static CreateCardUpstreamRequestDto From(CreateCardRequestDto request, string userId)
    {
        var phoneCode = NormalizePhoneCode(request.PhoneCode);

        return new CreateCardUpstreamRequestDto
        {
            UserId = int.TryParse(userId, out var numericUserId) ? numericUserId : (object)userId,
            CardTypeId = request.CardTypeId,
            ExternalCardId = string.IsNullOrWhiteSpace(request.ExternalCardId)
                ? NewExternalCardId(userId, request.CardTypeId)
                : request.ExternalCardId,
            Nickname = request.Nickname,
            Currency = request.Currency,
            CardName = request.CardName,
            BudgetId = request.BudgetId,
            BillingAddress = request.BillingAddress,
            DeliveryAddress = request.DeliveryAddress,
            Phone = FormatPhoneForUpstream(request.Phone, phoneCode),
            PhoneCode = phoneCode ?? request.PhoneCode,
            DesignId = request.DesignId,
            PhysicalCardDesignId = request.PhysicalCardDesignId,
            DiscountCode = request.DiscountCode
        };
    }

    private static string NewExternalCardId(string userId, int? cardTypeId)
    {
        var sanitizedUserId = string.Join(
            string.Empty,
            userId.Where(char.IsLetterOrDigit));
        if (string.IsNullOrWhiteSpace(sanitizedUserId))
        {
            sanitizedUserId = "user";
        }

        var typeSegment = cardTypeId is null ? "card" : $"type-{cardTypeId.Value}";
        return $"mobile-{sanitizedUserId}-{typeSegment}-{Guid.NewGuid():N}";
    }

    private static string? FormatPhoneForUpstream(string? phone, string? phoneCode)
    {
        if (string.IsNullOrWhiteSpace(phone))
        {
            return phone;
        }

        var trimmedPhone = phone.Trim();
        var phoneDigits = string.Concat(trimmedPhone.Where(char.IsDigit));

        if (trimmedPhone.StartsWith('+') && !string.IsNullOrWhiteSpace(phoneDigits))
        {
            return $"+{phoneDigits}";
        }

        if (trimmedPhone.StartsWith("00", StringComparison.Ordinal) && phoneDigits.Length > 2)
        {
            return $"+{phoneDigits[2..]}";
        }

        if (string.IsNullOrWhiteSpace(phoneCode))
        {
            return trimmedPhone;
        }

        if (phoneDigits.StartsWith(phoneCode, StringComparison.Ordinal) && phoneDigits.Length > phoneCode.Length)
        {
            return $"+{phoneDigits}";
        }

        return $"+{phoneCode}{phoneDigits.TrimStart('0')}";
    }

    private static string? NormalizePhoneCode(string? phoneCode)
    {
        if (string.IsNullOrWhiteSpace(phoneCode))
        {
            return null;
        }

        var digits = string.Concat(phoneCode.Where(char.IsDigit));
        if (digits.StartsWith("00", StringComparison.Ordinal))
        {
            digits = digits[2..];
        }

        return string.IsNullOrWhiteSpace(digits) ? null : digits;
    }
}

internal static class CardDtoJsonHelpers
{
    public static int? ParseCardId(string value)
    {
        return int.TryParse(value, out var numericCardId) ? numericCardId : null;
    }

    public static int? TryGetInt32(JsonElement element, string propertyName)
    {
        return element.ValueKind == JsonValueKind.Object &&
               element.TryGetProperty(propertyName, out var property) &&
               property.ValueKind == JsonValueKind.Number &&
               property.TryGetInt32(out var value)
            ? value
            : null;
    }

    public static decimal? TryGetDecimal(JsonElement element, string propertyName)
    {
        return element.ValueKind == JsonValueKind.Object &&
               element.TryGetProperty(propertyName, out var property) &&
               property.ValueKind == JsonValueKind.Number &&
               property.TryGetDecimal(out var value)
            ? value
            : null;
    }

    public static string? TryGetString(JsonElement element, string propertyName)
    {
        return element.ValueKind == JsonValueKind.Object &&
               element.TryGetProperty(propertyName, out var property) &&
               property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
    }
}

public sealed class UpdateCardLimitsUpstreamRequestDto
{
    public decimal? Daily { get; init; }

    public decimal? Weekly { get; init; }

    public decimal? Monthly { get; init; }

    public static UpdateCardLimitsUpstreamRequestDto From(UpdateCardLimitsRequestDto request)
    {
        return new UpdateCardLimitsUpstreamRequestDto
        {
            Daily = Normalize(request.Daily ?? request.DailyPurchaseLimit),
            Weekly = Normalize(request.Weekly),
            Monthly = Normalize(request.Monthly)
        };
    }

    /// <summary>
    /// The card issuer receives the value as text, so drop the scale the JSON
    /// number carried (500.0 becomes 500, 12.50 becomes 12.5).
    /// </summary>
    public static decimal? Normalize(decimal? value) =>
        value is null ? null : Math.Round(value.Value, 2) / 1.000000000000000000000000000000m;
}

public sealed class UpdateCardPinUpstreamRequestDto
{
    public string? Pin { get; init; }

    public static UpdateCardPinUpstreamRequestDto From(UpdateCardPinRequestDto request)
    {
        return new UpdateCardPinUpstreamRequestDto
        {
            Pin = request.Pin ?? request.PinToken
        };
    }
}

public sealed class CardLimitValuesDto
{
    public decimal? Daily { get; init; }

    public decimal? Weekly { get; init; }

    public decimal? Monthly { get; init; }

    public DateTimeOffset? UpdatedAt { get; init; }
}

/// <summary>Current customer-chosen limits plus the tier ceilings they may not exceed.</summary>
public sealed class CardLimitsResponseDto
{
    public string Currency { get; init; } = "USD";

    public CardLimitValuesDto? Current { get; init; }

    public CardLimitValuesDto Caps { get; init; } = new();

    /// <summary>card_type, tier or none.</summary>
    public string CapSource { get; init; } = "none";

    public string? TierName { get; init; }

    public bool CanUpdate { get; init; } = true;
}

