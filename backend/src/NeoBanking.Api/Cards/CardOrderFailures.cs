using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Http;
using NeoBanking.Application.Common;

namespace NeoBanking.Api.Cards;

/// <summary>
/// Turns the issuer's card-order refusals into errors the app can act on.
/// Hoppa answers an order it cannot charge with HTTP 400 and a body such as
/// <c>{"errorCode":"PAYMENT_REQUIRED","errorMessage":"Insufficient funds.
/// Required amount: 5.00 USD. Please top up your account.","totalCost":5.00,
/// "currency":"USD"}</c>; the generic proxy error would hide that behind
/// "We could not create card.".
/// </summary>
public static class CardOrderFailures
{
    public const string InsufficientFundsCode = "mobile.cards.create.insufficient_funds";

    private static readonly Regex RequiredAmountPattern = new(
        @"Required amount:\s*(?<amount>\d[\d,]*(?:\.\d+)?)\s*(?<currency>[A-Z]{3})",
        RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    private static readonly string[] InsufficientFundsCodes =
    [
        "PAYMENT_REQUIRED",
        "INSUFFICIENT_BALANCE",
        "INSUFFICIENT_FUNDS"
    ];

    public static ApplicationError Translate(ApplicationError error)
    {
        if (!TryReadProviderError(error.Detail, out var providerCode, out var providerMessage, out var totalCost, out var currency))
        {
            return error;
        }

        var insufficient =
            (providerCode is not null && InsufficientFundsCodes.Contains(providerCode, StringComparer.OrdinalIgnoreCase)) ||
            (providerMessage is not null && providerMessage.Contains("insufficient", StringComparison.OrdinalIgnoreCase));
        if (!insufficient)
        {
            return error;
        }

        var amount = FormatRequiredAmount(providerMessage, totalCost, currency);
        var message = amount is null
            ? "Your balance does not cover the card fee. Top up your balance or unload a card, then order again."
            : $"Your balance does not cover the card fee of {amount}. Top up your balance or unload a card, then order again.";

        return new ApplicationError(
            InsufficientFundsCode,
            message,
            StatusCodes.Status422UnprocessableEntity,
            providerMessage ?? error.Detail);
    }

    private static string? FormatRequiredAmount(string? providerMessage, decimal? totalCost, string? currency)
    {
        if (providerMessage is not null)
        {
            var match = RequiredAmountPattern.Match(providerMessage);
            if (match.Success)
            {
                return $"{match.Groups["amount"].Value} {match.Groups["currency"].Value.ToUpperInvariant()}";
            }
        }

        if (totalCost is > 0 && !string.IsNullOrWhiteSpace(currency))
        {
            return $"{totalCost.Value.ToString("0.00", CultureInfo.InvariantCulture)} {currency.Trim().ToUpperInvariant()}";
        }

        return null;
    }

    private static bool TryReadProviderError(
        string? detail,
        out string? code,
        out string? message,
        out decimal? totalCost,
        out string? currency)
    {
        code = null;
        message = null;
        totalCost = null;
        currency = null;
        if (string.IsNullOrWhiteSpace(detail))
        {
            return false;
        }

        try
        {
            using var document = JsonDocument.Parse(detail);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            var root = document.RootElement;
            code = ReadString(root, "errorCode", "ErrorCode", "code", "Code");
            message = ReadString(root, "errorMessage", "ErrorMessage", "message", "Message", "title", "Title");
            currency = ReadString(root, "currency", "Currency");
            if (root.TryGetProperty("totalCost", out var cost) || root.TryGetProperty("TotalCost", out cost))
            {
                if (cost.ValueKind == JsonValueKind.Number && cost.TryGetDecimal(out var parsed))
                {
                    totalCost = parsed;
                }
                else if (cost.ValueKind == JsonValueKind.String &&
                         decimal.TryParse(cost.GetString(), NumberStyles.Number, CultureInfo.InvariantCulture, out parsed))
                {
                    totalCost = parsed;
                }
            }

            return code is not null || message is not null;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static string? ReadString(JsonElement element, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (element.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String)
            {
                var text = value.GetString()?.Trim();
                if (!string.IsNullOrWhiteSpace(text))
                {
                    return text;
                }
            }
        }

        return null;
    }
}
