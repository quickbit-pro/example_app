using System.Security.Claims;
using System.Text.Json;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Mor;

public sealed record MorIdentity(int UserId, string Role, string Name, string Email);

// Request-scoped: role and company membership come from Hoppa, never browser roles
// or an installation-wide key alone. Local users must have a verified Hoppa mapping.
public sealed class MorIdentityResolver(IProxyHoppaRequestUseCase proxy)
{
    public const string AdminRole = "white_label_admin_mor";
    public const string UserRole = "user_simple";
    private Task<ApplicationResult<MorIdentity>>? pending;
    public Task<ApplicationResult<MorIdentity>> Resolve(ClaimsPrincipal user, CancellationToken ct)
        => pending ??= ResolveCore(user, ct);

    private async Task<ApplicationResult<MorIdentity>> ResolveCore(ClaimsPrincipal user, CancellationToken ct)
    {
        if (user.Identity?.IsAuthenticated != true ||
            !int.TryParse(user.FindFirstValue("hoppa_user_id"), out var id) || id <= 0)
            return Denied("Sign in with an account linked to a MOR user.");
        var result = await proxy.ExecuteAsync(new ProxyHoppaRequestCommand<object?> {
            Method = HttpMethod.Get, UpstreamPath = "/api/v2/mor/public/transactions",
            Query = new Dictionary<string,string?> { ["page"] = "1", ["pageSize"] = "1" },
            FailureCode = "mor.identity.failed", FailureMessage = "Unable to verify MOR membership."
        }, ct);
        if (!result.IsSuccess) return ApplicationResult<MorIdentity>.Failure(result.Error!);
        if (Field(result.Value, "users") is not { ValueKind: JsonValueKind.Array } users)
            return ApplicationResult<MorIdentity>.Failure(new("mor.identity.invalid", "Invalid MOR membership response.", 502));
        foreach (var row in users.EnumerateArray())
        {
            if (Field(row, "userId") is not { ValueKind: JsonValueKind.Number } rowId || !rowId.TryGetInt32(out var number) || number != id) continue;
            var role = Field(row, "role")?.GetString();
            if (role is not (AdminRole or UserRole)) break;
            return ApplicationResult<MorIdentity>.Success(new(id, role, Field(row,"name")?.GetString() ?? "", Field(row,"email")?.GetString() ?? ""));
        }
        return Denied("This account does not have a MOR admin or cardholder role in this company.");
    }
    private static ApplicationResult<MorIdentity> Denied(string message) => ApplicationResult<MorIdentity>.Failure(new("mor.access.denied", message, 403));
    public static JsonElement? Field(JsonElement? value, string key) => value is { ValueKind: JsonValueKind.Object } obj
        ? obj.EnumerateObject().Where(p => p.Name.Equals(key, StringComparison.OrdinalIgnoreCase)).Select(p => (JsonElement?)p.Value).FirstOrDefault() : null;
}
