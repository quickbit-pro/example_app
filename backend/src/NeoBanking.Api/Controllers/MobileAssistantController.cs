using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Assistant;
using NeoBanking.Application.Security;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/assistant")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class MobileAssistantController(AssistantService assistant) : ApiControllerBase
{
    [HttpGet("usage")]
    public async Task<ActionResult<AssistantUsageDto>> Usage(CancellationToken cancellationToken)
    {
        if (!Identity(out var companyId, out var userId)) return MissingIdentity<AssistantUsageDto>();
        return ToActionResult(await assistant.GetUsageAsync(companyId, userId, cancellationToken));
    }

    [HttpPost("chat")]
    [Consumes("application/json")]
    [RequestSizeLimit(96 * 1024)]
    public async Task<ActionResult<AssistantChatDto>> Chat([FromBody] AssistantChatRequest request, CancellationToken cancellationToken)
    {
        if (!Identity(out var companyId, out var userId)) return MissingIdentity<AssistantChatDto>();
        var result = await assistant.ChatAsync(companyId, userId, request, cancellationToken);
        if (result.Error?.StatusCode == StatusCodes.Status429TooManyRequests)
        {
            var now = DateTimeOffset.UtcNow;
            var seconds = result.Error.Code is "assistant.daily_limit" or "assistant.global_limit"
                ? Math.Max(1, (int)Math.Ceiling((new DateTimeOffset(now.UtcDateTime.Date, TimeSpan.Zero).AddDays(1) - now).TotalSeconds))
                : 60;
            Response.Headers.RetryAfter = seconds.ToString(System.Globalization.CultureInfo.InvariantCulture);
        }
        return ToActionResult(result);
    }

    private bool Identity(out Guid companyId, out Guid userId)
    {
        userId = Guid.Empty;
        return TryGetCompanyInstallationId(out companyId) && companyId != Guid.Empty &&
            TryGetLocalUserId(out var localId) && Guid.TryParse(localId, out userId) && userId != Guid.Empty;
    }
}
