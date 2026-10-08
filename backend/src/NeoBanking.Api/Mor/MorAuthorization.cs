using Microsoft.AspNetCore.Authorization;

namespace NeoBanking.Api.Mor;

public sealed record MorRoleRequirement(string Role) : IAuthorizationRequirement;
public sealed class MorRoleHandler(MorIdentityResolver identities) : AuthorizationHandler<MorRoleRequirement>
{
    protected override async Task HandleRequirementAsync(AuthorizationHandlerContext context, MorRoleRequirement requirement)
    {
        var ct = (context.Resource as HttpContext)?.RequestAborted ?? default;
        var identity = await identities.Resolve(context.User, ct);
        if (identity.IsSuccess && identity.Value!.Role == requirement.Role) context.Succeed(requirement);
    }
}
