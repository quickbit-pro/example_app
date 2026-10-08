using System.Text.Json;
using Microsoft.AspNetCore.Mvc;

namespace NeoBanking.Api.Controllers;

public sealed partial class AdminReferralsController
{
    [HttpGet("programs/{programId:guid}/community/policy")]
    public Task<ActionResult<JsonElement?>> CommunityPolicy(Guid programId, CancellationToken ct) => Forward(HttpMethod.Get, $"programs/{programId:D}/community/policy", null, ct);
    [HttpPut("programs/{programId:guid}/community/policy")]
    public Task<ActionResult<JsonElement?>> UpdateCommunityPolicy(Guid programId, [FromBody] JsonElement body, CancellationToken ct) => Forward(HttpMethod.Put, $"programs/{programId:D}/community/policy", body, ct);
    [HttpGet("programs/{programId:guid}/community/members")]
    public Task<ActionResult<JsonElement?>> CommunityMembers(Guid programId, CancellationToken ct) => Forward(HttpMethod.Get, $"programs/{programId:D}/community/members", null, ct);
    [HttpPost("programs/{programId:guid}/community/members/{userId:int:min(1)}/enable")]
    public Task<ActionResult<JsonElement?>> EnableCommunity(Guid programId, int userId, [FromBody] JsonElement body, CancellationToken ct) => Forward(HttpMethod.Post, $"programs/{programId:D}/community/members/{userId}/enable", body, ct);
    [HttpPost("programs/{programId:guid}/community/members/{userId:int:min(1)}/revoke")]
    public Task<ActionResult<JsonElement?>> RevokeCommunity(Guid programId, int userId, [FromBody] JsonElement body, CancellationToken ct) => Forward(HttpMethod.Post, $"programs/{programId:D}/community/members/{userId}/revoke", body, ct);
}
