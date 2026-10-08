using System.Globalization;
using System.Text.Json;
using NeoBanking.Application.UseCases.Hoppa;
namespace NeoBanking.Api.Statements;
public sealed class StatementExportException(string message) : Exception(message);
public sealed record StatementTransaction(string Id, DateTimeOffset Date, string Merchant, string Type, string Status,
    decimal Amount, string Currency, string Source, string Description, string ExternalId = "", string RelatedId = "");
public interface IStatementTransactionSource
{
    Task<IReadOnlyList<StatementTransaction>> LoadAsync(string providerUser, int year, int month, CancellationToken ct);
}
public sealed class StatementTransactionSource(IProxyHoppaRequestUseCase proxy) : IStatementTransactionSource
{
    public async Task<IReadOnlyList<StatementTransaction>> LoadAsync(string providerUser, int year, int month, CancellationToken ct)
    {
        var start = new DateTimeOffset(year, month, 1, 0, 0, 0, TimeSpan.Zero); var end = start.AddMonths(1);
        var rows = new List<StatementTransaction>(); var seen = new HashSet<string>(); int? total = null;
        for (var page = 1; page <= 40; page++)
        {
            var response = await proxy.ExecuteAsync(new ProxyHoppaRequestCommand<object> {
                UpstreamPath = "/api/v2/transactions", Query = new Dictionary<string, string?> {
                    ["userId"] = providerUser, ["page"] = page.ToString(), ["pageSize"] = "500",
                    ["startDate"] = start.ToString("O"), ["endDate"] = end.AddTicks(-1).ToString("O"),
                    ["sortBy"] = "date", ["sortOrder"] = "asc" },
                FailureMessage = "Could not load the complete month. Please try again." }, ct);
            if (!response.IsSuccess || response.Value is not { ValueKind: JsonValueKind.Object } root)
                throw new StatementExportException("Could not load the complete month. Please try again.");
            var data = Get(root, "data"); var pagination = Get(root, "pagination");
            if (data.ValueKind != JsonValueKind.Array || !Get(pagination, "total").TryGetInt32(out var expected) || expected < 0 || expected > 20000)
                throw new StatementExportException("The monthly transaction list could not be verified. Please try again.");
            if (total is not null && total != expected) throw new StatementExportException("Transactions changed during export. Please create the export again.");
            total = expected;
            foreach (var item in data.EnumerateArray())
            {
                var id = Text(item, "id");
                if (string.IsNullOrWhiteSpace(id) || !seen.Add(id)) throw new StatementExportException("Transactions changed during export. Please create the export again.");
                if (!DateTimeOffset.TryParse(Text(item, "transactionDate"), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date) || date < start || date >= end)
                    throw new StatementExportException("A transaction date could not be verified for this month.");
                if (!Get(item, "amount").TryGetDecimal(out var amount)) throw new StatementExportException("A transaction amount could not be verified.");
                var merchant = Text(item, "merchantName"); var description = Text(item, "description");
                rows.Add(new(id, date.ToUniversalTime(), string.IsNullOrWhiteSpace(merchant) ? description : merchant,
                    Text(item, "type"), Text(item, "status"), SignedAmount(item, amount), Text(item, "currency"), Text(item, "source"), description, Text(item, "externalTransactionId"), Text(item, "relatedCardTransactionId")));
            }
            if (rows.Count == total) return rows.OrderBy(x => x.Date).ThenBy(x => x.Id, StringComparer.Ordinal).ToArray();
            if (data.GetArrayLength() == 0 || rows.Count > total) break;
        }
        throw new StatementExportException("The complete month could not be loaded. No partial statement was created.");
    }
    private static decimal SignedAmount(JsonElement item, decimal amount)
    {
        if (amount <= 0) return amount;
        var type = new string(Text(item, "type").ToLowerInvariant().Where(c => !char.IsWhiteSpace(c) && c != '_' && c != '-').ToArray());
        var metadata = Get(item, "metadata");
        var direction = Text(item, "direction"); if (direction.Length == 0) direction = Text(metadata, "direction"); direction = direction.ToLowerInvariant();
        if (new[] {"credit", "credited", "incoming", "inbound"}.Contains(direction)) return amount;
        if (new[] {"debit", "debited", "outgoing", "outbound", "withdrawal", "payment"}.Contains(direction)) return -amount;
        if (int.TryParse(type, out var numeric)) return new[] {3,7,8,9,10,13,15,16}.Contains(numeric) ? -amount : amount;
        if (type.Contains("unload")) return -amount;
        if (new[] {"reversal","refund","topup","deposit","load","credit","frommaster","mastertouser"}.Any(type.Contains)) return amount;
        return new[] {"withdraw","payment","purchase","fee","payout","send","transferout","tomaster","usertomaster","outgoing","debit"}.Any(type.Contains) ? -amount : amount;
    }
    private static JsonElement Get(JsonElement item, string key) => item.ValueKind == JsonValueKind.Object
        ? item.EnumerateObject().FirstOrDefault(p => p.Name.Equals(key, StringComparison.OrdinalIgnoreCase)).Value : default;
    private static string Text(JsonElement item, string key) => Get(item, key).ValueKind is JsonValueKind.String or JsonValueKind.Number ? Get(item, key).ToString() : "";
}
