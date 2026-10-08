namespace NeoBanking.Domain.Security;

public static class ApplicationRoles
{
    public const string User = "User";
    public const string Admin = "Admin";

    public static readonly string[] All = [User, Admin];
}
