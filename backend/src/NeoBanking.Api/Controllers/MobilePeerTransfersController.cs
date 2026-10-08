using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Peer;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Peer;
using NeoBanking.Application.Security;

namespace NeoBanking.Api.Controllers;

/// <summary>
/// Send money to and request money from other members of the same
/// installation. Writes are throttled per user so a compromised session
/// cannot spray transfers or requests; lookups are throttled to stop
/// enumeration of who is a member.
/// </summary>
[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/peer-transfers")]
public sealed class MobilePeerTransfersController(PeerTransferService service) : ApiControllerBase
{
    [HttpPost("lookup")]
    [EnableRateLimiting(RateLimitPolicies.PeerLookup)]
    public async Task<ActionResult<PeerUserDto>> Lookup([FromBody] PeerLookupRequestDto request, CancellationToken cancellationToken)
    {
        if (!TryGetScope(out var companyId, out var userId))
        {
            return MissingIdentity<PeerUserDto>();
        }

        return ToActionResult(await service.LookupAsync(companyId, userId, request, cancellationToken));
    }

    [HttpGet("fee-info")]
    public async Task<ActionResult<PeerFeeInfoDto>> FeeInfo(
        [FromQuery] decimal? amount,
        [FromQuery] string? currency,
        CancellationToken cancellationToken)
    {
        if (!TryGetScope(out var companyId, out var userId))
        {
            return MissingIdentity<PeerFeeInfoDto>();
        }

        return Ok(await service.GetFeeInfoAsync(companyId, userId, amount, currency, cancellationToken));
    }

    [HttpPost("send")]
    [EnableRateLimiting(RateLimitPolicies.PeerSensitive)]
    public async Task<ActionResult<PeerTransferDto>> Send([FromBody] PeerSendRequestDto request, CancellationToken cancellationToken)
    {
        if (!TryGetScope(out var companyId, out var userId))
        {
            return MissingIdentity<PeerTransferDto>();
        }

        if (!TryGetCurrentUserId(out _))
        {
            return MissingHoppaUser<PeerTransferDto>();
        }

        return ToActionResult(await service.SendAsync(companyId, userId, request, cancellationToken));
    }

    [HttpGet("recent")]
    public async Task<ActionResult<IReadOnlyList<PeerTransferDto>>> Recent([FromQuery] int limit = 20, CancellationToken cancellationToken = default)
    {
        if (!TryGetScope(out var companyId, out var userId))
        {
            return MissingIdentity<IReadOnlyList<PeerTransferDto>>();
        }

        return Ok(await service.ListRecentAsync(companyId, userId, limit, cancellationToken));
    }

    [HttpGet("requests")]
    public async Task<ActionResult<PeerRequestsDto>> Requests(CancellationToken cancellationToken)
    {
        if (!TryGetScope(out var companyId, out var userId))
        {
            return MissingIdentity<PeerRequestsDto>();
        }

        return Ok(await service.ListRequestsAsync(companyId, userId, cancellationToken));
    }

    [HttpPost("requests")]
    [EnableRateLimiting(RateLimitPolicies.PeerSensitive)]
    public async Task<ActionResult<PeerPaymentRequestDto>> RequestMoney([FromBody] PeerRequestMoneyDto request, CancellationToken cancellationToken)
    {
        if (!TryGetScope(out var companyId, out var userId))
        {
            return MissingIdentity<PeerPaymentRequestDto>();
        }

        return ToActionResult(await service.RequestMoneyAsync(companyId, userId, request, cancellationToken));
    }

    [HttpPost("requests/{requestId:guid}/respond")]
    [EnableRateLimiting(RateLimitPolicies.PeerSensitive)]
    public async Task<ActionResult<PeerRespondResultDto>> Respond(
        Guid requestId,
        [FromBody] PeerRespondRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetScope(out var companyId, out var userId))
        {
            return MissingIdentity<PeerRespondResultDto>();
        }

        return ToActionResult(await service.RespondAsync(companyId, userId, requestId, request, cancellationToken));
    }

    [HttpPost("requests/{requestId:guid}/cancel")]
    public async Task<ActionResult<PeerPaymentRequestDto>> CancelRequest(Guid requestId, CancellationToken cancellationToken)
    {
        if (!TryGetScope(out var companyId, out var userId))
        {
            return MissingIdentity<PeerPaymentRequestDto>();
        }

        return ToActionResult(await service.CancelRequestAsync(companyId, userId, requestId, cancellationToken));
    }

    [HttpGet("contacts")]
    public async Task<ActionResult<IReadOnlyList<PeerContactDto>>> Contacts(CancellationToken cancellationToken)
    {
        if (!TryGetScope(out var companyId, out var userId))
        {
            return MissingIdentity<IReadOnlyList<PeerContactDto>>();
        }

        return Ok(await service.ListContactsAsync(companyId, userId, cancellationToken));
    }

    [HttpPost("contacts")]
    public async Task<ActionResult<PeerContactDto>> AddContact([FromBody] PeerAddContactDto request, CancellationToken cancellationToken)
    {
        if (!TryGetScope(out var companyId, out var userId))
        {
            return MissingIdentity<PeerContactDto>();
        }

        return ToActionResult(await service.AddContactAsync(companyId, userId, request, cancellationToken));
    }

    [HttpDelete("contacts/{contactId:guid}")]
    public async Task<IActionResult> RemoveContact(Guid contactId, CancellationToken cancellationToken)
    {
        if (!TryGetScope(out var companyId, out var userId))
        {
            return MissingIdentity<bool>().Result!;
        }

        var result = await service.RemoveContactAsync(companyId, userId, contactId, cancellationToken);
        return result.IsSuccess ? NoContent() : ToActionResult(result).Result!;
    }

    private bool TryGetScope(out Guid companyId, out Guid userId)
    {
        userId = Guid.Empty;
        return TryGetCompanyInstallationId(out companyId) &&
               TryGetLocalUserId(out var localUserId) &&
               Guid.TryParse(localUserId, out userId);
    }
}
