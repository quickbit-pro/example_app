using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Admin;

/// <summary>What a provider ledger row means for reporting.</summary>
public static class AdminTransactionKinds
{
    public const string Deposit = "deposit";
    public const string Withdrawal = "withdrawal";
    public const string CardPurchase = "card_purchase";
    public const string CardRefund = "card_refund";
    public const string CardCash = "card_cash";
    /// <summary>A zero-amount authorisation: wallet provisioning or a merchant's card check.</summary>
    public const string CardCheck = "card_check";
    /// <summary>Money moved between the customer's wallet and card.</summary>
    public const string CardFunding = "card_funding";
    public const string CardEvent = "card_event";
    public const string Conversion = "conversion";
    /// <summary>Money moved between customers, or between a customer and the programme account.</summary>
    public const string Transfer = "transfer";
    public const string Fee = "fee";
    public const string FeeRefund = "fee_refund";
    public const string Other = "other";

    /// <summary>Kinds a customer starts; one of these in a period makes them a transacting customer.</summary>
    public static readonly IReadOnlySet<string> CustomerInitiated = new HashSet<string>
    {
        Deposit, Withdrawal, CardPurchase, CardCash, CardFunding, Conversion, Transfer
    };
}

public static class AdminTransactionDirections
{
    public const string In = "in";
    public const string Out = "out";
    public const string Internal = "internal";
    public const string None = "none";
}

public static class AdminTransactionStatuses
{
    public const string Completed = "completed";
    public const string Pending = "pending";
    public const string Failed = "failed";
    public const string Other = "other";
}

/// <summary>
/// Classifies Hoppa `/api/v2/transactions` rows. The rules mirror the mobile
/// ledger parser (banking_models.dart, group_card_fees.dart) and the assistant's
/// spending source, which were written against captured production rows:
/// Interlace card rows carry a numeric provider type, card fees arrive as their
/// own rows, P2P legs go through the programme ("master") account, and the
/// provider marks related legs with <c>isPrimary: false</c>.
/// </summary>
public static partial class AdminTransactionClassifier
{
    // Interlace card event codes, as labelled by the mobile app.
    private static readonly HashSet<int> CardRefundCodes = [0, 4, 6, 14];
    private static readonly HashSet<int> CardFundingCodes = [2, 3];
    private static readonly HashSet<int> CardFeeCodes = [7, 8, 9, 10, 15, 16];
    private static readonly HashSet<int> CardEventCodes = [11, 12];
    private const int CardCashCode = 13;
    private const int CardDeclineFeeCode = 10;
    private const int CardPaymentFeeCode = 9;

    public static AdminTransaction? Classify(JsonElement row)
    {
        if (row.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var id = Text(row, "id", "transactionId");
        if (string.IsNullOrWhiteSpace(id))
        {
            return null;
        }

        var metadata = Property(row, "metadata");
        var rawType = Text(row, "type", "transactionType") ?? string.Empty;
        var typeKey = Key(rawType);
        var cardCode = CardCode(typeKey, metadata);
        var description = Clip(Collapse(Text(row, "description", "memo", "name")), 300) ?? string.Empty;
        var client = Text(row, "clientTransactionId") ?? Text(metadata, "clientTransactionId");
        var signed = Decimal(row, "amount", "transactionAmount", "value") ?? 0m;
        var currency = Currency(Text(row, "currency", "currencyCode")) ?? "USD";
        var feeAmount = Decimal(row, "feeAmount") ?? Decimal(metadata, "feeAmount");
        var feeCurrency = Currency(Text(row, "feeCurrency") ?? Text(metadata, "feeCurrency"));
        var rawStatus = Text(row, "status", "state") ?? string.Empty;
        var cardReference = Text(row, "cardId") ?? Text(metadata, "cardId");

        var kind = KindOf(typeKey, cardCode, description, client, cardReference);
        var amount = Math.Abs(signed);
        if (kind == AdminTransactionKinds.CardPurchase && amount == 0m)
        {
            kind = AdminTransactionKinds.CardCheck;
        }

        // Hoppa books June 2026 decline fees with amount 0 and the charge in feeAmount.
        if (kind is AdminTransactionKinds.Fee && amount == 0m && feeAmount is > 0m)
        {
            amount = feeAmount.Value;
            currency = feeCurrency ?? currency;
        }

        return new AdminTransaction
        {
            ProviderTransactionId = Clip(id, 100)!,
            OccurredAt = Date(row, "transactionDate", "occurredAt", "completedAt", "createdAt", "date", "timestamp")
                ?? Date(metadata, "transactionDate", "createdAt") ?? DateTimeOffset.UnixEpoch,
            RawType = Clip(rawType, 64)!,
            RawStatus = Clip(rawStatus, 40)!,
            Status = StatusOf(rawStatus),
            StatusReason = Clip(Collapse(
                Text(row, "declineReason", "statusReason", "failureReason", "reason", "responseMessage", "declineCode", "responseCode", "errorMessage") ??
                Text(metadata, "declineReason", "statusReason", "failureReason", "reason", "responseMessage", "declineCode", "responseCode", "errorMessage")), 160),
            Kind = kind,
            FeeType = kind is AdminTransactionKinds.Fee or AdminTransactionKinds.FeeRefund
                ? FeeTypeOf(typeKey, cardCode ?? EventCode(metadata, description), client, description)
                : null,
            Direction = DirectionOf(kind, typeKey, signed, row, metadata),
            Amount = amount,
            Currency = currency,
            Description = description,
            Merchant = kind is AdminTransactionKinds.CardPurchase or AdminTransactionKinds.CardRefund or
                AdminTransactionKinds.CardCash or AdminTransactionKinds.CardCheck
                ? Clip(Collapse(Text(row, "merchantName", "merchant")) ?? MerchantFromDescriptor(description), 120)
                : null,
            MerchantCategory = Clip(Text(row, "merchantCategory", "category"), 80),
            CardReference = Clip(cardReference, 100),
            WalletReference = Clip(Text(row, "walletId") ?? Text(metadata, "walletId"), 100),
            BudgetReference = Clip(Text(row, "budgetId") ?? Text(metadata, "budgetId"), 100),
            AccountReference = Clip(Text(row, "accountId") ?? Text(metadata, "accountId"), 100),
            ExternalReference = Clip(Text(row, "externalTransactionId"), 160),
            RelatedReference = Clip(Text(row, "relatedCardTransactionId") ?? Text(metadata, "relatedCardTransactionId"), 160),
            ClientReference = Clip(client, 160),
            FeeAmount = feeAmount,
            FeeCurrency = feeCurrency,
            IsPrimary = !(Property(row, "isPrimary").ValueKind == JsonValueKind.False)
        };
    }

    /// <summary>
    /// Flags provider rows that repeat a movement another row already reports,
    /// so totals count it once. Only explicit references and identical fee
    /// descriptions are used; amounts or dates alone never fold rows.
    /// </summary>
    public static void MarkDuplicates(IReadOnlyCollection<AdminTransaction> rows)
    {
        foreach (var row in rows)
        {
            row.IsDuplicate = false;
        }

        // Hoppa records a payment request settlement twice: the internal payment
        // (client id N) and "fees: Direct payment for request N" for the same amount.
        var payments = rows
            .Where(row => Key(row.RawType) == "internalpayment" && !string.IsNullOrWhiteSpace(row.ClientReference))
            .GroupBy(row => row.ClientReference!, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);
        foreach (var row in rows.Where(row => Key(row.RawType) == "fees"))
        {
            var request = RequestPattern().Match(row.Description);
            if (request.Success &&
                payments.TryGetValue(request.Groups[1].Value, out var payment) &&
                SameMoney(payment, row))
            {
                row.IsDuplicate = true;
            }
        }

        // The monthly card fee arrives as the card fee and again as "fees: Monthly card fee ..."
        // with the same card and period; the fee ledger copy is the duplicate.
        var cardFees = rows
            .Where(row => row.Kind == AdminTransactionKinds.Fee && !row.Description.StartsWith("fees:", StringComparison.OrdinalIgnoreCase))
            .Select(row => (Row: row, Period: MonthlyFeePeriod(row.Description)))
            .Where(item => item.Period is not null)
            .ToList();
        foreach (var copy in rows.Where(row =>
                     row.Kind == AdminTransactionKinds.Fee &&
                     row.Description.StartsWith("fees:", StringComparison.OrdinalIgnoreCase)))
        {
            var period = MonthlyFeePeriod(copy.Description);
            if (period is not null && cardFees.Any(item =>
                    item.Period == period && SameMoney(item.Row, copy) && item.Row.Status == copy.Status))
            {
                copy.IsDuplicate = true;
            }
        }
    }

    private static string KindOf(string typeKey, int? cardCode, string description, string? client, string? cardReference)
    {
        if (typeKey.Contains("feereversal") || typeKey.Contains("feerefund") || typeKey.Contains("feereturn") ||
            FeeReversalPattern().IsMatch(description))
        {
            return AdminTransactionKinds.FeeRefund;
        }

        // A settled payment request, not a fee (see MarkDuplicates).
        if (typeKey == "fees" && RequestPattern().IsMatch(description))
        {
            return AdminTransactionKinds.Transfer;
        }

        if (typeKey.Contains("fee") || typeKey.Contains("subscription") ||
            (cardCode is { } feeCode && CardFeeCodes.Contains(feeCode)) || IsLinkedFeeClient(client))
        {
            return AdminTransactionKinds.Fee;
        }

        if (cardCode is { } code)
        {
            if (CardRefundCodes.Contains(code)) return AdminTransactionKinds.CardRefund;
            if (CardFundingCodes.Contains(code)) return AdminTransactionKinds.CardFunding;
            if (CardEventCodes.Contains(code)) return AdminTransactionKinds.CardEvent;
            return code == CardCashCode ? AdminTransactionKinds.CardCash : AdminTransactionKinds.CardPurchase;
        }

        if (typeKey is "cardtopup" or "autocardtopup" or "cardload" or "cardloading" or "cardfunding" or
            "cardunload" or "unload" or "walletcredit" or "walletdebit")
        {
            return AdminTransactionKinds.CardFunding;
        }

        if (typeKey.StartsWith("atm") || typeKey is "cardwithdrawal" or "cardatmwithdrawal" or "cashwithdrawal")
        {
            return AdminTransactionKinds.CardCash;
        }

        if (typeKey.Contains("refund") || typeKey.Contains("reversal") || typeKey.Contains("chargeback") ||
            typeKey.Contains("cashback"))
        {
            return typeKey.StartsWith("card") || !string.IsNullOrWhiteSpace(cardReference)
                ? AdminTransactionKinds.CardRefund
                : AdminTransactionKinds.Other;
        }

        if (typeKey is "cardpayment" or "cardpurchase" or "purchase" or "cardtransaction" or "cardauthorization" or
                "cardauthorisation" or "cardsettlement" or "authorization" or "authorisation" or "settlement" or "card" ||
            typeKey.StartsWith("pos"))
        {
            return AdminTransactionKinds.CardPurchase;
        }

        if (typeKey.Contains("exchange") || typeKey.Contains("conversion") || typeKey.Contains("quantum") ||
            typeKey.Contains("swap") || typeKey is "fx" or "fxtrade")
        {
            return AdminTransactionKinds.Conversion;
        }

        // transfer_in/transfer_out stay transfers: Equals books FX conversion legs with them.
        if (typeKey.Contains("deposit") || typeKey == "topup")
        {
            return AdminTransactionKinds.Deposit;
        }

        if (typeKey.Contains("withdraw") || typeKey == "payout")
        {
            return AdminTransactionKinds.Withdrawal;
        }

        if (typeKey.Contains("transfer") || typeKey.Contains("p2p") || typeKey.Contains("peer") ||
            typeKey is "internalpayment" or "payment" or "send" or "receive" or "sent" or "received")
        {
            return AdminTransactionKinds.Transfer;
        }

        // Card rows whose type was lost still carry the Interlace descriptor.
        return DescriptorPattern().IsMatch(description) && !string.IsNullOrWhiteSpace(cardReference)
            ? AdminTransactionKinds.CardPurchase
            : AdminTransactionKinds.Other;
    }

    private static string DirectionOf(string kind, string typeKey, decimal signed, JsonElement row, JsonElement metadata) =>
        kind switch
        {
            AdminTransactionKinds.Deposit or AdminTransactionKinds.CardRefund or AdminTransactionKinds.FeeRefund
                => AdminTransactionDirections.In,
            AdminTransactionKinds.Withdrawal or AdminTransactionKinds.CardPurchase or AdminTransactionKinds.CardCash or
                AdminTransactionKinds.Fee => AdminTransactionDirections.Out,
            AdminTransactionKinds.CardFunding or AdminTransactionKinds.Conversion => AdminTransactionDirections.Internal,
            AdminTransactionKinds.CardCheck or AdminTransactionKinds.CardEvent => AdminTransactionDirections.None,
            _ => ExplicitDirection(row) ?? ExplicitDirection(metadata) ??
                (signed < 0m ? AdminTransactionDirections.Out : null) ??
                NameDirection(typeKey) ??
                (signed > 0m ? AdminTransactionDirections.In : AdminTransactionDirections.None)
        };

    private static string? ExplicitDirection(JsonElement element)
    {
        var value = Key(Text(element, "direction", "creditDebitIndicator", "debitCredit", "flow") ?? string.Empty);
        return value switch
        {
            "credit" or "credited" or "incoming" or "inbound" or "crdt" or "in" => AdminTransactionDirections.In,
            "debit" or "debited" or "outgoing" or "outbound" or "dbit" or "out" => AdminTransactionDirections.Out,
            _ => null
        };
    }

    private static string? NameDirection(string typeKey)
    {
        // Programme-account legs: "to master" leaves the customer, "from master" arrives.
        if (typeKey.Contains("frommaster") || typeKey.Contains("mastertouser") || typeKey.Contains("receive") ||
            typeKey.Contains("transferin") || typeKey.Contains("incoming"))
        {
            return AdminTransactionDirections.In;
        }

        return typeKey.Contains("tomaster") || typeKey.Contains("usertomaster") || typeKey.Contains("send") ||
               typeKey.Contains("sent") || typeKey.Contains("transferout") || typeKey.Contains("outgoing") ||
               typeKey.Contains("payment")
            ? AdminTransactionDirections.Out
            : null;
    }

    public static string StatusOf(string? rawStatus) => Key(rawStatus ?? string.Empty) switch
    {
        "closed" or "complete" or "completed" or "success" or "succeeded" or "successful" or "settled" or
            "posted" or "cleared" or "booked" or "processed" or "paid" or "done" => AdminTransactionStatuses.Completed,
        "pending" or "created" or "processing" or "authorized" or "authorised" or "inprogress" or "submitted" or
            "initiated" or "queued" or "onhold" or "hold" or "new" or "waiting" => AdminTransactionStatuses.Pending,
        "fail" or "failed" or "declined" or "rejected" or "cancelled" or "canceled" or "reverted" or "error" or
            "expired" or "voided" or "void" or "reversed" or "returned" => AdminTransactionStatuses.Failed,
        _ => AdminTransactionStatuses.Other
    };

    private static string FeeTypeOf(string typeKey, int? cardCode, string? client, string description)
    {
        var clientKey = client?.ToLowerInvariant() ?? string.Empty;
        var text = Key(description);
        if (typeKey.Contains("declin") || cardCode == CardDeclineFeeCode || clientKey.EndsWith("_fee_declination") ||
            text.Contains("decline"))
            return "decline";
        if (typeKey is "cardpaymentfee" or "consumptionfee" || cardCode == CardPaymentFeeCode ||
            clientKey.EndsWith("_fee_consumption") || text.StartsWith("feeconsumption"))
            return "card_payment";
        if (text.Contains("topup") || typeKey.Contains("topup")) return "top_up";
        if (text.Contains("issuance") || typeKey.Contains("issuance")) return "card_issuance";
        if (text.Contains("monthly") || typeKey.Contains("subscription") || text.Contains("maintenance")) return "monthly";
        if (text.Contains("exchange") || text.Contains("conversion") || typeKey.Contains("exchange")) return "exchange";
        if (text.Contains("withdraw") || typeKey.Contains("withdraw")) return "withdrawal";
        if (text.Contains("transfer") || typeKey.Contains("transfer")) return "transfer";
        return cardCode is not null ? "card" : "other";
    }

    private static int? CardCode(string typeKey, JsonElement metadata)
    {
        if (int.TryParse(typeKey, NumberStyles.None, CultureInfo.InvariantCulture, out var code))
        {
            return code;
        }

        // Named card rows keep the Interlace event code in metadata.type.
        return typeKey is "cardpayment" or "cardtransaction" or "card" &&
               int.TryParse(Text(metadata, "type"), NumberStyles.None, CultureInfo.InvariantCulture, out var nested)
            ? nested
            : null;
    }

    /// <summary>Fee rows name their Interlace code in metadata.type or a "Type10:" descriptor.</summary>
    private static int? EventCode(JsonElement metadata, string description)
    {
        if (int.TryParse(Text(metadata, "type"), NumberStyles.None, CultureInfo.InvariantCulture, out var code))
        {
            return code;
        }

        var match = DescriptorCodePattern().Match(description);
        return match.Success && int.TryParse(match.Groups[1].Value, NumberStyles.None, CultureInfo.InvariantCulture, out code)
            ? code
            : null;
    }

    private static bool IsLinkedFeeClient(string? client) =>
        client is not null &&
        (client.EndsWith("_Fee_Consumption", StringComparison.OrdinalIgnoreCase) ||
         client.EndsWith("_Fee_Declination", StringComparison.OrdinalIgnoreCase));

    /// <summary>"Type1: OPENAI                 SAN FRANCISCOCAUS" → "OPENAI".</summary>
    private static string? MerchantFromDescriptor(string description)
    {
        var match = DescriptorPattern().Match(description);
        var descriptor = match.Success ? match.Groups[1].Value : null;
        if (string.IsNullOrWhiteSpace(descriptor))
        {
            return null;
        }

        var name = WideGapPattern().Split(descriptor.Trim())[0].Trim();
        return name.Length == 0 ? null : name;
    }

    private static string? MonthlyFeePeriod(string description)
    {
        var match = MonthlyFeePattern().Match(description);
        return match.Success ? $"{match.Groups[1].Value}|{match.Groups[2].Value}|{match.Groups[3].Value}" : null;
    }

    private static bool SameMoney(AdminTransaction left, AdminTransaction right) =>
        left.Amount == right.Amount && string.Equals(left.Currency, right.Currency, StringComparison.OrdinalIgnoreCase);

    internal static string Key(string value) =>
        new(value.Where(char.IsLetterOrDigit).Select(char.ToLowerInvariant).ToArray());

    private static JsonElement Property(JsonElement element, string name)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return default;
        }

        foreach (var property in element.EnumerateObject())
        {
            if (property.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
            {
                return property.Value;
            }
        }

        return default;
    }

    /// <summary>First non-empty string or number among the keys, on this object only.</summary>
    private static string? Text(JsonElement element, params string[] keys)
    {
        foreach (var key in keys)
        {
            var value = Property(element, key);
            if (value.ValueKind is JsonValueKind.String or JsonValueKind.Number)
            {
                var text = value.ToString().Trim();
                if (text.Length > 0)
                {
                    return text;
                }
            }
        }

        return null;
    }

    private static decimal? Decimal(JsonElement element, params string[] keys)
    {
        foreach (var key in keys)
        {
            var value = Property(element, key);
            if (value.ValueKind == JsonValueKind.Number && value.TryGetDecimal(out var number))
            {
                return number;
            }

            if (value.ValueKind == JsonValueKind.String &&
                decimal.TryParse(value.GetString(), NumberStyles.Number, CultureInfo.InvariantCulture, out number))
            {
                return number;
            }
        }

        return null;
    }

    private static DateTimeOffset? Date(JsonElement element, params string[] keys)
    {
        var text = Text(element, keys);
        return DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var value)
            ? value.ToUniversalTime()
            : null;
    }

    private static string? Currency(string? value)
    {
        var code = value?.Trim().ToUpperInvariant();
        return code is { Length: >= 2 and <= 12 } && code.All(char.IsAsciiLetterOrDigit) ? code : null;
    }

    private static string? Collapse(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static string? Clip(string? value, int length) =>
        value is null ? null : value.Length <= length ? value : value[..length];

    [GeneratedRegex(@"^\s*Type\s*\d+\s*:\s*(.*)$", RegexOptions.IgnoreCase)]
    private static partial Regex DescriptorPattern();

    [GeneratedRegex(@"^\s*Type\s*(\d+)\s*:", RegexOptions.IgnoreCase)]
    private static partial Regex DescriptorCodePattern();

    [GeneratedRegex(@"\s{2,}")]
    private static partial Regex WideGapPattern();

    [GeneratedRegex(@"request\s+([A-Za-z0-9-]+)\s*$", RegexOptions.IgnoreCase)]
    private static partial Regex RequestPattern();

    [GeneratedRegex(@"^\s*fee\s+(reversal|refund)", RegexOptions.IgnoreCase)]
    private static partial Regex FeeReversalPattern();

    [GeneratedRegex(@"monthly card fee for card ending (\d+)\s*\((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)", RegexOptions.IgnoreCase)]
    private static partial Regex MonthlyFeePattern();
}
