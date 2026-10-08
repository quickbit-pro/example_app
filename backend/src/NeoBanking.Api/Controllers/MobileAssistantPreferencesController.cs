using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Assistant;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/assistant/preferences")]
public sealed class MobileAssistantPreferencesController(IProxyHoppaRequestUseCase proxyHoppa) : ApiControllerBase
{
    [HttpGet]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<ActionResult<AssistantPreferencesDto>> Get(CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId) || companyId == Guid.Empty ||
            !TryGetLocalUserId(out var localId) || !Guid.TryParse(localId, out var userId) || userId == Guid.Empty)
            return MissingIdentity<AssistantPreferencesDto>();
        if (!TryGetCurrentUserId(out var hoppaUserId) || !int.TryParse(hoppaUserId, out var numericId) || numericId <= 0)
            return MissingHoppaUser<AssistantPreferencesDto>();

        // The client cannot choose the identity or upstream URL. This endpoint never calls an AI provider.
        var profile = await proxyHoppa.ExecuteAsync(new ProxyHoppaRequestCommand<object?>
        {
            Method = HttpMethod.Get,
            UpstreamPath = $"/api/v2/users/{Segment(hoppaUserId)}",
            FailureCode = "assistant.preferences.unavailable",
            FailureMessage = "Saved preferences are unavailable."
        }, cancellationToken);

        // Preferences are optional. Do not relay upstream bodies/errors (which can contain personal data).
        return Ok(profile.IsSuccess && profile.Value is { } payload
            ? AssistantPreferences.FromUserProfile(payload)
            : new AssistantPreferencesDto());
    }
}
