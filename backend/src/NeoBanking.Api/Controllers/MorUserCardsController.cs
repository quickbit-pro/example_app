using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using NeoBanking.Api.Mor;
using NeoBanking.Api.Auth;
using NeoBanking.Application.DTOs.Mor;
using NeoBanking.Application.Security;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.MorUser)]
[Route("api/v1/mor/user/cards")]
public sealed class MorUserCardsController(IProxyHoppaRequestUseCase proxy, IConfiguration configuration,
    IMorCardRevealVerifier revealVerifier) : HoppaProxyControllerBase(proxy)
{
    [HttpGet]
    public async Task<ActionResult<JsonElement?>> Cards(CancellationToken ct)
    {
        if (!TryGetCurrentUserId(out var userId)) return MissingIdentity<JsonElement?>();
        var result = await AssignedCards(userId, ct);
        if (!result.IsSuccess) return ToActionResult(result);
        var cards = MorIdentityResolver.Field(result.Value, "cards");
        if (cards is not { ValueKind: JsonValueKind.Array }) return InvalidCards();
        return Ok(JsonSerializer.SerializeToElement(new { cards, capabilities = new {
            transactions = configuration.GetValue("Mor:UserTransactionsEnabled", true),
            loadRequests = configuration.GetValue("Mor:UserLoadRequestsEnabled", true)
        } }));
    }

    [HttpPost("{cardId:int:min(1)}/freeze")]
    public Task<ActionResult<JsonElement?>> Freeze(int cardId, CancellationToken ct) => CardOperation(cardId, "freeze", ct);
    [HttpPost("{cardId:int:min(1)}/unfreeze")]
    public Task<ActionResult<JsonElement?>> Unfreeze(int cardId, CancellationToken ct) => CardOperation(cardId, "enable", ct);

    [HttpGet("{cardId:int:min(1)}/transactions")]
    public async Task<ActionResult<JsonElement?>> Transactions(int cardId, [FromQuery,Range(1,100)] int limit = 25,
        [FromQuery,Range(0,1000000)] int offset = 0, CancellationToken ct = default)
    {
        var access = await CheckAssignment(cardId, ct);
        if (!access.IsSuccess) return ToActionResult(access);
        if (!configuration.GetValue("Mor:UserTransactionsEnabled", true)) return Unavailable("Card transaction history is not enabled for this connection.");
        return await ScopedRequest(cardId, HttpMethod.Get, "transactions", null, ct, Query(("limit",limit),("offset",offset)));
    }

    [HttpPost("{cardId:int:min(1)}/load-requests")]
    public async Task<ActionResult<JsonElement?>> RequestLoad(int cardId, [FromBody] MorLoadRequest body, CancellationToken ct)
    {
        var access = await CheckAssignment(cardId, ct);
        if (!access.IsSuccess) return ToActionResult(access);
        if (!configuration.GetValue("Mor:UserLoadRequestsEnabled", true)) return Unavailable("Card load requests are not enabled for this connection.");
        return await ScopedRequest(cardId, HttpMethod.Post, "load-requests", body, ct);
    }

    [HttpPost("{cardId:int:min(1)}/widget")]
    [EnableRateLimiting(RateLimitPolicies.Auth)]
    public async Task<ActionResult<JsonElement?>> Widget(int cardId, [FromBody] MorRevealRequest body, CancellationToken ct)
    {
        Response.Headers.CacheControl = "no-store, no-cache, max-age=0";
        Response.Headers["Referrer-Policy"] = "no-referrer";
        var access = await CheckAssignment(cardId, ct);
        if (!access.IsSuccess) return ToActionResult(access);
        var error = await revealVerifier.Verify(User, body.CurrentPassword, body.Code, ct);
        if (error is not null) return ToActionResult(ApplicationResult<JsonElement?>.Failure(error));
        TryGetCurrentUserId(out var userId);
        return ToActionResult(await SendHoppaAsync<object?>(HttpMethod.Get, $"/api/v2/cards/{cardId}/widget", null,
            "mor.user.widget.failed", "Unable to reveal card details.", ct, Query(("userId",userId))));
    }

    private async Task<ActionResult<JsonElement?>> CardOperation(int cardId, string operation, CancellationToken ct)
    {
        var access = await CheckAssignment(cardId, ct);
        if (!access.IsSuccess) return ToActionResult(access);
        TryGetCurrentUserId(out var userId);
        return ToActionResult(await SendHoppaAsync<object?>(HttpMethod.Post, $"/api/v2/cards/{cardId}/{operation}", null,
            "mor.user.card.failed", "Unable to update this card.", ct, Query(("userId",userId))));
    }
    private async Task<ActionResult<JsonElement?>> ScopedRequest(int cardId, HttpMethod method, string operation, object? body, CancellationToken ct, IReadOnlyDictionary<string,string?>? query = null)
    {
        TryGetCurrentUserId(out var userId);
        return ToActionResult(await SendHoppaAsync(method, $"/api/v2/mor/public/users/{Segment(userId)}/cards/{cardId}/{operation}", body,
            "mor.user.card.failed", "Unable to complete the card request.", ct, query));
    }
    private Task<ApplicationResult<JsonElement?>> AssignedCards(string userId, CancellationToken ct) => SendHoppaAsync<object?>(HttpMethod.Get,
        $"/api/v2/mor/public/users/{Segment(userId)}/cards", null, "mor.user.cards.failed", "Unable to load your assigned cards.", ct);
    private async Task<ApplicationResult<JsonElement?>> CheckAssignment(int cardId, CancellationToken ct)
    {
        if (!TryGetCurrentUserId(out var userId)) return ApplicationResult<JsonElement?>.Failure(new("mor.identity.missing", "Sign in again.",401));
        var result = await AssignedCards(userId, ct);
        if (!result.IsSuccess) return result;
        if (MorIdentityResolver.Field(result.Value,"cards") is not {ValueKind:JsonValueKind.Array} cards)
            return ApplicationResult<JsonElement?>.Failure(new("mor.cards.invalid", "Invalid card response.",502));
        foreach (var card in cards.EnumerateArray())
            if (MorIdentityResolver.Field(card,"id") is {ValueKind:JsonValueKind.Number} id && id.TryGetInt32(out var value) && value == cardId &&
                MorIdentityResolver.Field(card,"assignedUserId") is {ValueKind:JsonValueKind.Number} assigned && assigned.TryGetInt32(out var assignedId) && assignedId.ToString() == userId)
                return ApplicationResult<JsonElement?>.Success(card);
        return ApplicationResult<JsonElement?>.Failure(new("mor.card.not_assigned", "This card is not assigned to you.",404));
    }
    private ActionResult<JsonElement?> InvalidCards() => ToActionResult(ApplicationResult<JsonElement?>.Failure(new("mor.cards.invalid","Invalid card response.",502)));
    private ActionResult<JsonElement?> Unavailable(string message) => ToActionResult(ApplicationResult<JsonElement?>.Failure(new("mor.feature.unavailable",message,501)));
}
