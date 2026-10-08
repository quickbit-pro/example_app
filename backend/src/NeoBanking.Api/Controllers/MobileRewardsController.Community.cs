using System.Text.Json;
using Microsoft.AspNetCore.Mvc;

namespace NeoBanking.Api.Controllers;

public sealed partial class MobileRewardsController
{
    [HttpGet("referrals/community")]
    public Task<ActionResult<JsonElement?>> Community([FromQuery] Guid? programId, CancellationToken ct) =>
        SendReferralAsync(HttpMethod.Get, "community", null, ct, Query(("programId", programId)));
    [HttpGet("referrals/community/earnings")]
    public Task<ActionResult<JsonElement?>> CommunityEarnings([FromQuery] Guid? programId, [FromQuery] int page = 1, [FromQuery] int pageSize = 25, CancellationToken ct = default) =>
        SendReferralAsync(HttpMethod.Get, "community/earnings", null, ct, PagedQuery(programId, page, pageSize));
}
