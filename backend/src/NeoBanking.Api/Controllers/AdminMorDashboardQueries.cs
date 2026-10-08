using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Mor;

namespace NeoBanking.Api.Controllers;

public sealed partial class AdminMorController
{
    // These are sample-backend projections. Hoppa does not need corresponding
    // context/overview/users endpoints; all reads retain API-key company scope.
    [HttpGet("context")]
    public async Task<ActionResult<JsonElement?>> Context(CancellationToken ct)
    {
        var merchant = await Read("transactions", ct, Query(("page", 1), ("pageSize", 1)));
        if (!merchant.IsSuccess && merchant.Error!.StatusCode != 403) return ToActionResult(merchant);
        var whitelabel = false;
        if (!merchant.IsSuccess)
        {
            var companies = await Read("companies", ct);
            if (!companies.IsSuccess && companies.Error!.StatusCode != 403) return ToActionResult(companies);
            if (companies.IsSuccess && companies.Value?.ValueKind != JsonValueKind.Array) return InvalidUpstream();
            whitelabel = companies.IsSuccess;
        }
        else if (Property(merchant.Value, "users")?.ValueKind != JsonValueKind.Array) return InvalidUpstream();
        return OkJson(new { company = InstallationCompany(), merchant = merchant.IsSuccess, whitelabel,
            capabilities = new { cardOrdering = true, cardCancellation = true, quantumFunding = true } });
    }

    [HttpGet("overview")]
    public async Task<ActionResult<JsonElement?>> Overview(CancellationToken ct)
    {
        var cards = await Read("cards", ct);
        if (!cards.IsSuccess) return ToActionResult(cards);
        var users = await Read("transactions", ct, Query(("page", 1), ("pageSize", 1)));
        if (!users.IsSuccess) return ToActionResult(users);
        var wallets = await Read("wallets", ct);
        if (!wallets.IsSuccess) return ToActionResult(wallets);
        var kyb = await Read("onboarding-status", ct, Query(("refresh", false)));
        if (!kyb.IsSuccess && kyb.Error!.StatusCode != 404) return ToActionResult(kyb);
        var userRows = Property(users.Value, "users");
        var balances = Property(wallets.Value, "balances");
        if (cards.Value?.ValueKind != JsonValueKind.Array || userRows?.ValueKind != JsonValueKind.Array
            || balances?.ValueKind != JsonValueKind.Object) return InvalidUpstream();
        var allCards = cards.Value.Value.EnumerateArray().ToArray();
        var assigned = allCards.Count(c => Property(c, "assignedUserId") is { ValueKind: JsonValueKind.Number } id && id.GetInt32() > 0);
        return OkJson(new {
            company = InstallationCompany(),
            kyb = kyb.IsSuccess ? kyb.Value : null,
            counts = new { users = SimpleUsers(userRows.Value).Length, cards = allCards.Length, assignedCards = assigned, unassignedCards = allCards.Length - assigned },
            balances,
        });
    }

    [HttpGet("users")]
    public async Task<ActionResult<JsonElement?>> Users(CancellationToken ct)
    {
        var result = await Read("transactions", ct, Query(("page", 1), ("pageSize", 1)));
        if (!result.IsSuccess) return ToActionResult(result);
        var users = Property(result.Value, "users");
        return users?.ValueKind == JsonValueKind.Array ? OkJson(SimpleUsers(users.Value)) : InvalidUpstream();
    }

    private async Task<ActionResult<JsonElement?>> QuantumFunding(HttpMethod method, decimal amount,
        MorQuantumTransferRequest? body, CancellationToken ct)
    {
        // Validate merchant access first, and derive the owner from company-scoped
        // metadata. Never forward a browser-supplied userId to the general API.
        var result = await Read("transactions", ct, Query(("page", 1), ("pageSize", 1)));
        if (!result.IsSuccess) return ToActionResult(result);
        var users = Property(result.Value, "users");
        if (users?.ValueKind != JsonValueKind.Array) return InvalidUpstream();
        var adminId = users.Value.EnumerateArray()
            .Where(u => string.Equals(Property(u, "role")?.GetString(), "white_label_admin_mor", StringComparison.OrdinalIgnoreCase))
            .Select(u => Property(u, "userId") is { ValueKind: JsonValueKind.Number } id && id.TryGetInt32(out var value) ? value : 0)
            .Where(id => id > 0).OrderBy(id => id).FirstOrDefault();
        if (adminId == 0) return ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
            "admin.mor.admin_missing", "No merchant administrator is available for wallet funding.", 409)));
        var path = method == HttpMethod.Get
            ? "/api/v2/cards/quantum-topup/estimate"
            : "/api/v2/transfers/crypto-to-quantum-transfer";
        return ToActionResult(await SendHoppaAsync(method, path, body,
            "admin.mor.funding.failed", "Unable to complete merchant wallet funding.", ct,
            method == HttpMethod.Get ? Query(("userId", adminId), ("amount", amount)) : Query(("userId", adminId))));
    }

    private object InstallationCompany() => new {
        id = companyContextAccessor.Current.InstallationId,
        name = companyContextAccessor.Current.CompanyName,
        displayNameSource = "installation",
    };

    private static object[] SimpleUsers(JsonElement users) => users.EnumerateArray()
        .Where(u => string.Equals(Property(u, "role")?.GetString(), "user_simple", StringComparison.OrdinalIgnoreCase))
        .Select(u => (object)new { userId = Property(u, "userId"), name = Property(u, "name"), email = Property(u, "email") })
        .ToArray();

    private Task<ApplicationResult<JsonElement?>> Read(string resource, CancellationToken ct, IReadOnlyDictionary<string, string?>? query = null)
        => SendHoppaAsync<object?>(HttpMethod.Get, $"/api/v2/mor/public/{resource}", null,
            "admin.mor.failed", "Unable to load MOR data.", ct, query);

    private static JsonElement? Property(JsonElement? element, string name)
    {
        if (element?.ValueKind != JsonValueKind.Object) return null;
        foreach (var property in element.Value.EnumerateObject())
            if (string.Equals(property.Name, name, StringComparison.OrdinalIgnoreCase)) return property.Value;
        return null;
    }
    private ActionResult<JsonElement?> OkJson(object value) => Ok(JsonSerializer.SerializeToElement(value));
    private ActionResult<JsonElement?> InvalidUpstream() => ToActionResult(ApplicationResult<JsonElement?>.Failure(
        new ApplicationError("admin.mor.invalid_response", "Hoppa returned an unexpected MOR response.", 502)));
}
