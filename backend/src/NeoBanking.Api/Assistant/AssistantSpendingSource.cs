using System.Globalization;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Assistant;

public sealed record AssistantSpendingCategoryDto(string Category, decimal Purchases, decimal Refunds, int Count);
public sealed record AssistantSpendingCurrencyDto(string Currency, decimal Purchases, decimal Refunds, decimal Net,
    int PurchaseCount, int RefundCount, IReadOnlyList<AssistantSpendingCategoryDto> Categories);
public sealed record AssistantSpendingSummaryDto(string From, string To, IReadOnlyList<AssistantSpendingCurrencyDto> Currencies,
    IReadOnlyList<AssistantActivityTransactionDto>? Transactions = null, IReadOnlyList<AssistantActivityCurrencyDto>? Activity = null);
public sealed record AssistantActivityTransactionDto(string Date, string Type, string Status, string Currency, decimal Amount,
    string Category, bool Internal, bool Primary, decimal? ReportedFee, string? FeeCurrency);
public sealed record AssistantActivityCurrencyDto(string Currency, decimal Incoming, decimal Outgoing, decimal Net, int Completed,
    int Pending, int Failed, int OtherStatus, int Internal, int Related, int Count);
public sealed class AssistantSpendingException : Exception;
public interface IAssistantSpendingSource
{
    Task<AssistantSpendingSummaryDto> LoadAsync(Guid companyId, Guid userId, string period, CancellationToken ct);
}

/// <summary>No client/provider-selected identity, shared cache, raw descriptions or identifiers leave this boundary.</summary>
public sealed class AssistantSpendingSource(NeoBankingDbContext db, IProxyHoppaRequestUseCase proxy, TimeProvider clock)
    : IAssistantSpendingSource
{
    public static bool ValidPeriod(string? period) => period is "this_month" or "last_month" or "last_90_days";

    public async Task<AssistantSpendingSummaryDto> LoadAsync(Guid companyId, Guid userId, string period, CancellationToken ct)
    {
        if (!ValidPeriod(period) || companyId == Guid.Empty || userId == Guid.Empty ||
            !await db.Users.AsNoTracking().AnyAsync(u => u.Id == userId && u.CompanyInstallationId == companyId && u.LockedAt == null, ct))
            throw new AssistantSpendingException();
        // Resolve the active local account's mapping afresh. Never trust a supplied provider user ID, including stale JWT mappings.
        var mappings = await db.ProviderMappings.AsNoTracking().Where(m => m.CompanyInstallationId == companyId &&
            m.InternalEntityId == userId && m.InternalEntityType == "user" && m.Provider == "hoppa" && m.ProviderEntityType == "user")
            .Select(m => m.ProviderEntityId).Take(2).ToListAsync(ct);
        if (mappings.Count != 1 || !int.TryParse(mappings[0], NumberStyles.None, CultureInfo.InvariantCulture, out var providerId) || providerId <= 0)
            throw new AssistantSpendingException();
        var provider = providerId.ToString(CultureInfo.InvariantCulture);
        if (await db.ProviderMappings.AsNoTracking().AnyAsync(m => m.Provider == "hoppa" && m.ProviderEntityType == "user" &&
            m.ProviderEntityId == provider && (m.CompanyInstallationId != companyId || m.InternalEntityId != userId), ct))
            throw new AssistantSpendingException();

        var now = clock.GetUtcNow();
        var month = new DateTimeOffset(now.Year, now.Month, 1, 0, 0, 0, TimeSpan.Zero);
        var start = period == "this_month" ? month : period == "last_month" ? month.AddMonths(-1) : new DateTimeOffset(now.UtcDateTime.Date, TimeSpan.Zero).AddDays(-89);
        var end = period == "last_month" ? month : now;
        var cards = await GetAsync("/api/v2/cards", new() { ["userId"] = provider }, ct);
        var cardRows = Get(cards, "cards");
        if (cardRows.ValueKind != JsonValueKind.Array || cardRows.GetArrayLength() > 100 ||
            !Int(Get(cards, "total"), out var cardCount) || cardCount != cardRows.GetArrayLength()) throw new AssistantSpendingException();
        var ownedCards = new HashSet<int>();
        foreach (var card in cardRows.EnumerateArray())
        {
            if (!Int(Get(card, "userId"), out var owner) || owner != providerId ||
                !Int(Get(card, "id"), out var id) || id <= 0 || !ownedCards.Add(id)) throw new AssistantSpendingException();
        }
        var entries = new List<Entry>();
        var activity = new List<AssistantActivityTransactionDto>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var externalIds = new HashSet<string>(StringComparer.Ordinal);
        int? total = null;
        for (var page = 1; page <= 20; page++)
        {
            var root = await GetAsync("/api/v2/transactions", new() {
                ["userId"] = provider, ["page"] = page.ToString(CultureInfo.InvariantCulture), ["pageSize"] = "100",
                ["startDate"] = start.ToString("O"), ["endDate"] = end.AddTicks(-1).ToString("O"),
                ["sortBy"] = "date", ["sortOrder"] = "asc" }, ct);
            CheckOwner(root, providerId);
            var rows = Get(root, "data");
            var pagination = Get(root, "pagination");
            if (rows.ValueKind != JsonValueKind.Array || rows.GetArrayLength() > 100 ||
                !Int(Get(pagination, "total"), out var expected) || expected is < 0 or > 2000 ||
                (total is not null && total != expected)) throw new AssistantSpendingException();
            total = expected;
            foreach (var row in rows.EnumerateArray())
            {
                CheckOwner(row, providerId);
                var id = Text(row, "id");
                if (id.Length is 0 or > 100 || !seen.Add(id)) throw new AssistantSpendingException();
                if (!DateTimeOffset.TryParse(Text(row, "transactionDate"), CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal, out var date) || date < start || date >= end) throw new AssistantSpendingException();
                // The upstream authenticated endpoint enforces company + userId and queries by owner.
                // Verify any additional ownership fields; never accept a client/model-selected identifier.
                var cardId = Get(row, "cardId");
                if (cardId.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined) &&
                    (!Int(cardId, out var card) || !ownedCards.Contains(card))) throw new AssistantSpendingException();
                var primaryValue = Get(row, "isPrimary").ValueKind;
                if (primaryValue is not (JsonValueKind.True or JsonValueKind.False or JsonValueKind.Undefined)) throw new AssistantSpendingException();
                var primary = primaryValue != JsonValueKind.False;
                var status = Status(Text(row, "status"));
                var rawType = Key(Text(row, "type"));
                var type = ActivityType(rawType);
                var refund = type == "Refund";
                var currency = Currency(Text(row, "currency"));
                var amount = Amount(Get(row, "amount"));
                var metadata = Get(row, "metadata");
                var direction = Direction(row, metadata);
                if (direction == "outgoing" || (direction != "incoming" && Outgoing(rawType))) amount = -Math.Abs(amount);
                var internalMovement = InternalMovement(rawType, metadata);
                var category = Category(Text(row, "category"), Text(row, "merchantCategory"));
                decimal? fee = Get(row, "feeAmount").ValueKind is JsonValueKind.Null or JsonValueKind.Undefined
                    ? null : Math.Abs(Amount(Get(row, "feeAmount")));
                var feeCurrency = fee is null ? null : Currency(Text(row, "feeCurrency") is { Length: > 0 } fc ? fc : currency);
                var external = Text(row, "externalTransactionId");
                if (external.Length > 0 && !externalIds.Add($"{cardId}:{external}:{rawType}")) throw new AssistantSpendingException();
                activity.Add(new(date.ToUniversalTime().ToString("yyyy-MM-dd"), type, status, currency, amount,
                    category, internalMovement, primary, fee, feeCurrency));
                // Preserve the previous card summary contract for older app versions.
                if (cardId.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined) && primary && status == "Completed" &&
                    (refund || type == "Card payment")) entries.Add(new(currency, category, Math.Abs(amount), refund));
            }
            if (seen.Count == total) break;
            if (rows.GetArrayLength() == 0 || seen.Count > total || page == 20) throw new AssistantSpendingException();
        }
        var currencies = entries.GroupBy(e => e.Currency).OrderBy(g => g.Key).Select(g => new AssistantSpendingCurrencyDto(
            g.Key, g.Where(e => !e.Refund).Sum(e => e.Amount), g.Where(e => e.Refund).Sum(e => e.Amount),
            g.Sum(e => e.Refund ? -e.Amount : e.Amount), g.Count(e => !e.Refund), g.Count(e => e.Refund),
            g.GroupBy(e => e.Category).OrderByDescending(c => c.Sum(e => e.Refund ? -e.Amount : e.Amount))
                .Select(c => new AssistantSpendingCategoryDto(c.Key, c.Where(e => !e.Refund).Sum(e => e.Amount),
                    c.Where(e => e.Refund).Sum(e => e.Amount), c.Count())).ToArray())).ToArray();
        if (currencies.Length > 10) throw new AssistantSpendingException();
        // Fail closed if the account was locked or its mapping changed while fetching pages.
        if (!await db.Users.AsNoTracking().AnyAsync(u => u.Id == userId && u.CompanyInstallationId == companyId && u.LockedAt == null, ct) ||
            !await db.ProviderMappings.AsNoTracking().AnyAsync(m => m.CompanyInstallationId == companyId && m.InternalEntityId == userId &&
                m.Provider == "hoppa" && m.InternalEntityType == "user" && m.ProviderEntityType == "user" && m.ProviderEntityId == provider, ct))
            throw new AssistantSpendingException();
        var totals = activity.GroupBy(t => t.Currency).OrderBy(g => g.Key).Select(g => {
            var completed = g.Where(t => t.Primary && !t.Internal && t.Status == "Completed").ToArray();
            var incoming = completed.Where(t => t.Amount > 0).Sum(t => t.Amount);
            var outgoing = -completed.Where(t => t.Amount < 0).Sum(t => t.Amount);
            return new AssistantActivityCurrencyDto(g.Key, incoming, outgoing, incoming - outgoing, completed.Length,
                g.Count(t => t.Status == "Pending"), g.Count(t => t.Status == "Failed"), g.Count(t => t.Status == "Other"),
                g.Count(t => t.Internal), g.Count(t => !t.Primary), g.Count());
        }).ToArray();
        if (totals.Length > 20) throw new AssistantSpendingException();
        return new(start.ToString("yyyy-MM-dd"), (period == "last_month" ? end.AddTicks(-1) : end).ToString("yyyy-MM-dd"), currencies,
            activity, totals);
    }

    private static string Currency(string value)
    {
        var code = value.ToUpperInvariant();
        if (code.Length is < 2 or > 12 || !code.All(char.IsAsciiLetterOrDigit)) throw new AssistantSpendingException();
        return code;
    }
    private static decimal Amount(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Number || !value.TryGetDecimal(out var amount) ||
            amount is < -1000000000m or > 1000000000m) throw new AssistantSpendingException();
        return amount;
    }
    private static string Status(string value) => Key(value) switch {
        "completed" or "settled" or "success" or "successful" or "cleared" or "closed" => "Completed",
        "pending" or "created" or "processing" or "authorized" or "authorised" => "Pending",
        "failed" or "fail" or "declined" or "rejected" or "cancelled" or "canceled" or "reverted" => "Failed",
        _ => "Other" };
    private static string ActivityType(string value) => value switch {
        "cardpayment" or "cardpurchase" or "purchase" => "Card payment",
        "cardrefund" or "refund" or "reversal" => "Refund",
        "deposit" or "cryptodeposit" or "fiatdeposit" or "topup" or "credit" => "Deposit",
        "withdrawal" or "withdraw" or "cryptowithdrawal" or "fiatwithdrawal" or "atmwithdrawal" => "Withdrawal",
        "cardtopup" or "autocardtopup" or "cardload" or "cardloading" => "Card funding",
        "cardunload" or "unload" => "Card unload",
        "exchange" or "conversion" or "currencyconversion" or "currencyexchange" or "fx" or "fxtrade" or "fxconversion" or
        "fxexchange" or "cryptoexchange" or "cryptotoquantum" or "cryptotoquantumtransfer" or "quantumtocryptoexchange" => "Exchange",
        "transfer" or "banktransfer" or "p2psend" or "p2preceive" or "peersend" or "peerreceive" or "transfertomaster" or
        "transferfrommaster" or "usertomastertransfer" or "mastertousertransfer" or "transferout" or "transferin" or
        "payment" or "payout" or "send" or "receive" or "incoming" or "outgoing" or "balancetransfer" => "Transfer",
        "fee" or "cardfee" or "transactionfee" or "exchangefee" or "transferfee" or "withdrawalfee" or "servicefee" or "subscriptionfee" => "Fee",
        _ => "Other activity" };
    private static bool Outgoing(string type) => ActivityType(type) is "Card payment" or "Withdrawal" or "Fee" or "Card unload" ||
        type is "p2psend" or "peersend" or "transfertomaster" or "usertomastertransfer" or "transferout" or "payment" or "payout" or "send" or "outgoing" or "1" or "3" or "5" or "7" or "8" or "9" or "10" or "13" or "15" or "16";
    private static string Direction(JsonElement row, JsonElement metadata)
    {
        foreach (var value in new[] { Text(row, "direction"), Text(metadata, "direction"), Text(metadata, "creditDebitIndicator") })
        {
            if (Key(value) is "credit" or "credited" or "incoming" or "inbound" or "crdt") return "incoming";
            if (Key(value) is "debit" or "debited" or "outgoing" or "outbound" or "dbit") return "outgoing";
        }
        return "";
    }
    private static bool InternalMovement(string type, JsonElement metadata)
    {
        if (ActivityType(type) == "Fee" || type is "p2psend" or "p2preceive" or "peersend" or "peerreceive" or
            "transfertomaster" or "transferfrommaster" or "usertomastertransfer" or "mastertousertransfer") return false;
        return ActivityType(type) is "Exchange" or "Card funding" or "Card unload" || type == "balancetransfer" || InternalMetadata(metadata, 0);
    }
    private static bool InternalMetadata(JsonElement node, int depth)
    {
        if (depth > 8) return false;
        if (node.ValueKind == JsonValueKind.Object)
        {
            if (Key(Text(node, "provider")) == "equalsmoney" && Key(Text(node, "source")) == "exchange") return true;
            foreach (var field in node.EnumerateObject())
            {
                if (Key(field.Name) is "isinternaltransfer" or "isowntransfer" && field.Value.ValueKind == JsonValueKind.True) return true;
                if (Key(field.Name) is "operation" or "operationtype" or "transfertype" && field.Value.ValueKind == JsonValueKind.String &&
                    (ActivityType(Key(field.Value.GetString()!)) is "Exchange" or "Card funding" or "Card unload" ||
                     Key(field.Value.GetString()!) is "internaltransfer" or "ownaccounttransfer" or "owntransfer" or "budgettransfer" or "cardfunding" or "quantumtocrypto" or "usdtocrypto")) return true;
                if (InternalMetadata(field.Value, depth + 1)) return true;
            }
        }
        else if (node.ValueKind == JsonValueKind.Array) return node.EnumerateArray().Any(n => InternalMetadata(n, depth + 1));
        return false;
    }

    private async Task<JsonElement> GetAsync(string path, Dictionary<string, string?> query, CancellationToken ct)
    {
        var response = await proxy.ExecuteAsync(new ProxyHoppaRequestCommand<object?> {
            Method = HttpMethod.Get, UpstreamPath = path, Query = query, SuppressPayloadLogging = true,
            FailureCode = "assistant.spending_unavailable", FailureMessage = "Spending analysis is unavailable." }, ct);
        if (!response.IsSuccess || response.Value is not { ValueKind: JsonValueKind.Object } root) throw new AssistantSpendingException();
        return root;
    }
    private static void CheckOwner(JsonElement row, int expected)
    {
        var owner = Get(row, "userId");
        if (owner.ValueKind != JsonValueKind.Undefined && (!Int(owner, out var id) || id != expected)) throw new AssistantSpendingException();
    }
    private static bool Int(JsonElement value, out int result) => int.TryParse(value.ToString(), NumberStyles.None, CultureInfo.InvariantCulture, out result);
    private static JsonElement Get(JsonElement row, string key) => row.ValueKind == JsonValueKind.Object
        ? row.EnumerateObject().FirstOrDefault(p => p.Name.Equals(key, StringComparison.OrdinalIgnoreCase)).Value : default;
    private static string Text(JsonElement row, string key) => Get(row, key).ValueKind is JsonValueKind.String or JsonValueKind.Number ? Get(row, key).ToString() : "";
    private static string Key(string value) => value.ToLowerInvariant().Replace("_", "").Replace("-", "").Replace(" ", "");
    private static string Category(string category, string merchantCategory) => Key(category.Length > 0 ? category : merchantCategory) switch {
        "groceries" or "grocery" or "supermarket" or "5411" => "Groceries",
        "dining" or "restaurants" or "restaurant" or "food" or "5812" or "5814" => "Food and dining",
        "travel" or "hotels" or "hotel" or "airlines" or "lodging" or "7011" => "Travel",
        "transport" or "transportation" or "fuel" or "taxi" or "4111" or "4121" or "5541" => "Transport",
        "shopping" or "retail" or "clothing" => "Shopping",
        "bills" or "utilities" or "subscription" or "subscriptions" or "4900" => "Bills and subscriptions",
        _ => "Other" };
    private sealed record Entry(string Currency, string Category, decimal Amount, bool Refund);
}
