namespace NeoBanking.Application.Security;

public static class AuthorizationPolicyNames
{
    public const string AuthenticatedUser = "authenticated_user";
    public const string User = "role_user";
    public const string MorAdmin = "mor_admin";
    public const string MorUser = "mor_user";
    public const string Admin = "role_admin";
}
