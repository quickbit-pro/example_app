using System.Globalization;
using System.Text.Json;

namespace NeoBanking.Api.Notifications;

public static class HoppaUserNotificationMapper
{
    public static UserPushMessage? Map(string eventType, JsonElement data)
    {
        var status = Normalize(GetString(data, "status") ?? EventStatus(eventType));
        var amount = FormatAmount(data);
        var incoming = IsIncoming(data);
        var reference = GetString(data, "transactionId") ??
            GetString(data, "externalTransactionId") ??
            GetString(data, "paymentId") ??
            GetString(data, "orderId");

        var message = eventType switch
        {
            "kyc.information_request" => new UserPushMessage(
                "Information required",
                "We need some additional information to continue your account verification.",
                "/onboarding/banking",
                Data("kyc", reference)),
            "kyc.interlace_submission_failed" => new UserPushMessage(
                "Crypto card verification needs attention",
                "We could not submit your verification. Open the app to review the next step.",
                "/kyc/status",
                Data("kyc", reference)),
            "user.kyc.updated" or "kyc.verified" or "kyc.update" => KycStatusMessage(status, reference),
            "legal_entity.status" => BusinessStatusMessage(status, reference),
            "cardholder.approved" => new UserPushMessage(
                "Crypto cards are ready",
                "Your crypto card account has been approved.",
                "/cards",
                Data("kyc", reference)),
            "cardholder.status" => CardholderStatusMessage(status, reference),

            "payment.completed" when incoming => Movement(
                "Money received", amount is null ? "An incoming payment has arrived." : $"{amount} was credited to your account.", "/activity", reference),
            "payment.completed" => Movement(
                "Payment completed", amount is null ? "Your payment was completed." : $"Your payment of {amount} was completed.", "/activity", reference),
            "payment.returned" => Movement(
                "Payment returned", amount is null ? "A payment was returned to your account." : $"{amount} was returned to your account.", "/activity", reference),
            "payout.payment" when IsTerminal(status) => Movement(
                "Transfer completed", amount is null ? "Your outgoing transfer was completed." : $"Your transfer of {amount} was completed.", "/activity", reference),
            "business_account.transaction" when incoming => Movement(
                "Money received", amount is null ? "Your business account received a transaction." : $"{amount} was credited to your business account.", "/activity", reference),
            "business_account.transaction" => Movement(
                "Transaction completed", amount is null ? "Your business account transaction was completed." : $"{amount} was debited from your business account.", "/activity", reference),

            "order.completed" => Movement(
                "Exchange completed", amount is null ? "Your exchange was completed." : $"Your exchange for {amount} was completed.", "/wallets/exchange", reference),
            "order.cancelled" => Movement(
                "Exchange cancelled", "Your exchange could not be completed. No further action will be taken.", "/wallets/exchange", reference),
            "paymentbatch.completed" or "paymentbatchorder.completed" => Movement(
                "Transfer completed", "Your outgoing transfer was completed.", "/activity", reference),
            "paymentbatch.validation_error" or "paymentbatch.cancelled" or "paymentbatchorder.cancelled" => Movement(
                "Transfer needs attention", "Your outgoing transfer could not be completed. Open the app for details.", "/activity", reference),

            "wallet.topped_up" => Movement(
                "Wallet credited", amount is null ? "Funds were added to your wallet." : $"{amount} was added to your wallet.", "/wallets/assets", reference),
            "wallet.withdrawal" when IsTerminal(status) => Movement(
                "Withdrawal completed", amount is null ? "Your wallet withdrawal was completed." : $"Your withdrawal of {amount} was completed.", "/activity", reference),
            "wallet.refund" => Movement(
                "Wallet refund received", amount is null ? "A refund was credited to your wallet." : $"{amount} was credited back to your wallet.", "/activity", reference),
            "budget.credited" => Movement(
                "Budget credited", amount is null ? "Funds were added to your budget." : $"{amount} was added to your budget.", "/accounts", reference),
            "budget.debited" => Movement(
                "Budget payment completed", amount is null ? "A payment was completed from your budget." : $"{amount} was paid from your budget.", "/activity", reference),
            "budget.credit_pending" => Movement(
                "Budget credit pending", "A credit to your budget is being processed.", "/accounts", reference),

            "card.transaction" when incoming => Movement(
                "Card refund received", amount is null ? "A refund was credited to your card." : $"{amount} was credited to your card.", "/activity", reference),
            "card.transaction" => Movement(
                "Card transaction", amount is null ? "A card transaction was completed." : $"A card transaction of {amount} was completed.", "/activity", reference),
            "card.topup" => Movement(
                "Card funded", amount is null ? "Funds were added to your card." : $"{amount} was added to your card.", "/cards", reference),
            "card.unload" => Movement(
                "Card funds moved", amount is null ? "Funds were moved from your card." : $"{amount} was moved from your card.", "/cards", reference),
            "card.shipped" => new UserPushMessage(
                "Your card is on the way", "Your physical card has been shipped.", "/cards", Data("card", reference)),
            "card.3ds.otp" or "card.3ds_auth_request" => new UserPushMessage(
                "Confirm your card payment", "Open the app to review your card payment verification.", "/cards", Data("card_security", reference)),
            _ => null
        };

        if (message is null)
        {
            return null;
        }

        var merged = new Dictionary<string, string>(message.Data)
        {
            ["eventType"] = eventType,
            ["route"] = message.Route
        };
        return message with { Data = merged };
    }

    private static UserPushMessage KycStatusMessage(string status, string? reference)
    {
        return status switch
        {
            "approved" or "verified" or "completed" => new UserPushMessage(
                "Identity verified", "Your identity verification was approved.", "/kyc/status", Data("kyc", reference)),
            "rejected" or "declined" or "failed" => new UserPushMessage(
                "Verification needs attention", "Your identity verification could not be approved. Open the app for details.", "/kyc/status", Data("kyc", reference)),
            _ => new UserPushMessage(
                "Verification status updated", "Your identity verification status has changed.", "/kyc/status", Data("kyc", reference))
        };
    }

    private static UserPushMessage BusinessStatusMessage(string status, string? reference)
    {
        return status switch
        {
            "approved" or "active" or "verified" => new UserPushMessage(
                "Business account approved", "Your business verification was approved.", "/business", Data("kyb", reference)),
            "rejected" or "declined" or "failed" => new UserPushMessage(
                "Business verification needs attention", "Open the app to review your business verification.", "/business", Data("kyb", reference)),
            _ => new UserPushMessage(
                "Business verification updated", "Your business verification status has changed.", "/business", Data("kyb", reference))
        };
    }

    private static UserPushMessage? CardholderStatusMessage(string status, string? reference)
    {
        return status switch
        {
            "approved" or "active" => new UserPushMessage(
                "Crypto cards are ready", "Your crypto card account has been approved.", "/cards", Data("kyc", reference)),
            "rejected" or "declined" or "failed" => new UserPushMessage(
                "Crypto card verification needs attention", "Open the app to review your crypto card verification.", "/kyc/status", Data("kyc", reference)),
            _ => null
        };
    }

    private static UserPushMessage Movement(string title, string body, string route, string? reference)
        => new(title, body, route, Data("transaction", reference));

    private static IReadOnlyDictionary<string, string> Data(string category, string? reference)
    {
        var data = new Dictionary<string, string> { ["category"] = category };
        if (!string.IsNullOrWhiteSpace(reference))
        {
            data["reference"] = reference;
        }
        return data;
    }

    private static bool IsIncoming(JsonElement data)
    {
        var direction = Normalize(
            GetString(data, "direction") ??
            GetString(data, "creditDebitIndicator") ??
            GetString(data, "transactionType") ??
            GetString(data, "type") ?? string.Empty);
        return direction is "incoming" or "inbound" or "credit" or "credited" or "deposit" or "refund" or "received";
    }

    private static bool IsTerminal(string status)
        => status is "completed" or "complete" or "success" or "succeeded" or "approved" or "processed" or "closed";

    private static string? FormatAmount(JsonElement data)
    {
        var value = GetDecimal(data, "amount") ??
            GetDecimal(data, "totalAmount") ??
            GetDecimal(data, "transactionAmount") ??
            GetDecimal(data, "value");
        if (value is null)
        {
            return null;
        }

        var currency = (GetString(data, "currency") ?? GetString(data, "transactionCurrency"))?.Trim().ToUpperInvariant();
        var formatted = value.Value.ToString("0.########", CultureInfo.InvariantCulture);
        return string.IsNullOrWhiteSpace(currency) ? formatted : $"{formatted} {currency}";
    }

    private static decimal? GetDecimal(JsonElement data, string propertyName)
    {
        if (!TryGetProperty(data, propertyName, out var value))
        {
            return null;
        }
        if (value.ValueKind == JsonValueKind.Number && value.TryGetDecimal(out var number))
        {
            return number;
        }
        return value.ValueKind == JsonValueKind.String &&
               decimal.TryParse(value.GetString(), NumberStyles.Number, CultureInfo.InvariantCulture, out var parsed)
            ? parsed
            : null;
    }

    private static string? GetString(JsonElement data, string propertyName)
    {
        if (!TryGetProperty(data, propertyName, out var value))
        {
            return null;
        }
        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString(),
            JsonValueKind.Number => value.GetRawText(),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            _ => null
        };
    }

    private static bool TryGetProperty(JsonElement data, string propertyName, out JsonElement value)
    {
        if (data.ValueKind == JsonValueKind.Object && data.TryGetProperty(propertyName, out value))
        {
            return true;
        }
        if (data.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in data.EnumerateObject())
            {
                if (string.Equals(property.Name, propertyName, StringComparison.OrdinalIgnoreCase))
                {
                    value = property.Value;
                    return true;
                }
            }
        }
        value = default;
        return false;
    }

    private static string EventStatus(string eventType)
        => eventType.Split('.', StringSplitOptions.RemoveEmptyEntries).LastOrDefault() ?? "updated";

    private static string Normalize(string value)
        => value.Trim().Replace(' ', '_').Replace('-', '_').ToLowerInvariant();
}
