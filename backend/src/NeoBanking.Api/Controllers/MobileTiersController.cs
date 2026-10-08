using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Cards;
using NeoBanking.Api.Tiers;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Tiers;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/tiers")]
public sealed class MobileTiersController : HoppaProxyControllerBase
{
    private static readonly string[] SelectedTierKeys =
        ["SelectedTierId", "selectedTierId", "TierId", "tierId", "PackageId", "packageId"];

    private readonly NeoBankingDbContext _dbContext;

    public MobileTiersController(NeoBankingDbContext dbContext, IProxyHoppaRequestUseCase proxyHoppa)
        : base(proxyHoppa)
    {
        _dbContext = dbContext;
    }

    /// <summary>
    /// The tiers this customer may choose, plus the one they are on. The provider
    /// lists every tier of the company, so hidden, inactive and other-account-type
    /// tiers are removed here (<see cref="CustomerTierCatalog"/>).
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<JsonElement?>> ListTiers(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var catalogTask = LoadCatalogAsync("mobile.tiers.list.failed", "We could not list tiers.", cancellationToken);
        var customerTask = LoadCustomerAsync(userId, cancellationToken);
        await Task.WhenAll(catalogTask, customerTask);

        var catalog = await catalogTask;
        if (!catalog.IsSuccess || catalog.Value is not JsonElement tiers)
        {
            return ToActionResult(catalog);
        }

        var customer = await customerTask;
        return Ok(CustomerTierCatalog.Filter(tiers, customer.AccountType, customer.CurrentTierId));
    }

    [HttpGet("card-tier/{cardTierId}")]
    public async Task<ActionResult<JsonElement?>> GetCardTier(string cardTierId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out _))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendHoppaAsync<object?>(
            HttpMethod.Get,
            $"/api/v2/tiers/card-tier/{Segment(cardTierId)}",
            null,
            "mobile.tiers.card_tier.failed",
            "We could not load card tier.",
            cancellationToken));
    }

    [HttpPost("select")]
    [HttpPost("current")]
    public async Task<ActionResult<JsonElement?>> SelectTier(
        [FromBody] ChangeUserTierRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        if (request.TierId is null)
        {
            return BadRequest(new
            {
                code = "mobile.tiers.tier_id_required",
                message = "Select a tier to continue."
            });
        }

        // The provider accepts any company tier from our API key, so the same rule
        // that hides a tier from the list has to refuse it here.
        var catalogTask = LoadCatalogAsync("mobile.tiers.select.failed", "We could not select tier.", cancellationToken);
        var customerTask = LoadCustomerAsync(userId, cancellationToken);
        await Task.WhenAll(catalogTask, customerTask);

        var catalog = await catalogTask;
        if (!catalog.IsSuccess)
        {
            return ToActionResult(catalog);
        }

        var customer = await customerTask;
        var offered = catalog.Value is JsonElement tiers
            ? CardLimitPolicy.FindTier(
                CustomerTierCatalog.Filter(tiers, customer.AccountType, customer.CurrentTierId),
                request.TierId.Value)
            : null;
        if (offered is null)
        {
            return BadRequest(new
            {
                code = "mobile.tiers.not_available",
                message = "This plan is not available for your account."
            });
        }

        return ToActionResult(await SendHoppaAsync(
            HttpMethod.Post,
            $"/api/v2/users/{Segment(userId)}/tier",
            new SetUserTierRequestDto
            {
                TierId = request.TierId.Value,
                TierCycle = request.TierCycle
            },
            "mobile.tiers.select.failed",
            "We could not select tier.",
            cancellationToken));
    }

    [HttpGet("current")]
    public async Task<ActionResult<JsonElement?>> GetCurrentTier(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var userResult = await LoadHoppaUserAsync(userId, "We could not load current tier.", cancellationToken);

        if (!userResult.IsSuccess)
        {
            return ToActionResult(userResult);
        }

        if (userResult.Value is not JsonElement user)
        {
            return Ok(new { });
        }

        var payload = UnwrapPayload(user);
        if (!TryGetInt32(payload, out var selectedTierId, SelectedTierKeys))
        {
            return Ok(new { });
        }

        return Ok(new
        {
            Id = selectedTierId,
            TierId = selectedTierId,
            SelectedTierId = selectedTierId,
            UserId = TryGetInt32(payload, out var upstreamUserId, "Id", "id", "UserId", "userId") ? upstreamUserId : (int?)null,
            TierCycle = TryGetString(payload, "TierBillingCycle", "tierBillingCycle", "TierCycle", "tierCycle"),
            Status = TryGetString(payload, "Status", "status")
        });
    }

    private Task<ApplicationResult<JsonElement?>> LoadCatalogAsync(
        string failureCode,
        string failureMessage,
        CancellationToken cancellationToken) =>
        SendHoppaAsync<object?>(HttpMethod.Get, "/api/v2/tiers", null, failureCode, failureMessage, cancellationToken);

    private Task<ApplicationResult<JsonElement?>> LoadHoppaUserAsync(
        string userId,
        string failureMessage,
        CancellationToken cancellationToken) =>
        SendHoppaAsync<object?>(
            HttpMethod.Get,
            $"/api/v2/users/{Segment(userId)}",
            null,
            "mobile.tiers.current.failed",
            failureMessage,
            cancellationToken);

    /// <summary>
    /// The account type and tier that decide what the customer is offered. The live
    /// provider user wins; without it the account type stored at signup is used and
    /// no tier counts as current.
    /// </summary>
    private async Task<(string AccountType, int? CurrentTierId)> LoadCustomerAsync(
        string userId,
        CancellationToken cancellationToken)
    {
        var userResult = await LoadHoppaUserAsync(userId, "We could not load your account.", cancellationToken);
        if (userResult.IsSuccess && userResult.Value is JsonElement user)
        {
            var payload = UnwrapPayload(user);
            var accountType = TryGetString(payload, "AccountType", "accountType");
            int? currentTierId = TryGetInt32(payload, out var selectedTierId, SelectedTierKeys) ? selectedTierId : null;
            if (!string.IsNullOrWhiteSpace(accountType))
            {
                return (CustomerTierCatalog.NormalizeAccountType(accountType), currentTierId);
            }

            return (await GetLocalAccountTypeAsync(cancellationToken), currentTierId);
        }

        return (await GetLocalAccountTypeAsync(cancellationToken), null);
    }

    private async Task<string> GetLocalAccountTypeAsync(CancellationToken cancellationToken)
    {
        if (!TryGetLocalUserId(out var localUserId) || !Guid.TryParse(localUserId, out var parsedUserId))
        {
            return "personal";
        }

        var metadataJson = await _dbContext.Users
            .AsNoTracking()
            .Where(user => user.Id == parsedUserId)
            .Select(user => user.MetadataJson)
            .SingleOrDefaultAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(metadataJson))
        {
            return "personal";
        }

        try
        {
            using var document = JsonDocument.Parse(metadataJson);
            return document.RootElement.ValueKind == JsonValueKind.Object &&
                   document.RootElement.TryGetProperty("accountType", out var value) &&
                   value.ValueKind == JsonValueKind.String
                ? CustomerTierCatalog.NormalizeAccountType(value.GetString())
                : "personal";
        }
        catch (JsonException)
        {
            return "personal";
        }
    }

    private static JsonElement UnwrapPayload(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return element;
        }

        foreach (var propertyName in new[] { "Data", "data", "User", "user" })
        {
            if (element.TryGetProperty(propertyName, out var payload) &&
                payload.ValueKind == JsonValueKind.Object)
            {
                return payload;
            }
        }

        return element;
    }

    private static bool TryGetInt32(JsonElement element, out int value, params string[] propertyNames)
    {
        value = 0;
        if (element.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        foreach (var propertyName in propertyNames)
        {
            if (!element.TryGetProperty(propertyName, out var property))
            {
                continue;
            }

            if (property.ValueKind == JsonValueKind.Number &&
                property.TryGetInt32(out value))
            {
                return true;
            }

            if (property.ValueKind == JsonValueKind.String &&
                int.TryParse(property.GetString(), out value))
            {
                return true;
            }
        }

        return false;
    }

    private static string? TryGetString(JsonElement element, params string[] propertyNames)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        foreach (var propertyName in propertyNames)
        {
            if (element.TryGetProperty(propertyName, out var property) &&
                property.ValueKind is JsonValueKind.String or JsonValueKind.Number)
            {
                return property.ToString();
            }
        }

        return null;
    }
}
