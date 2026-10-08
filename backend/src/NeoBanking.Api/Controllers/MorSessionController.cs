using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Mor;
using NeoBanking.Application.Security;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.AuthenticatedUser)]
[Route("api/v1/mor/session")]
public sealed class MorSessionController(MorIdentityResolver identities) : ApiControllerBase
{
    [HttpGet]
    public async Task<ActionResult<MorIdentity>> Session(CancellationToken ct)
    {
        Response.Headers.CacheControl = "no-store";
        return ToActionResult(await identities.Resolve(User, ct));
    }
}
