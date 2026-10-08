using NeoBanking.Application.Common;

namespace NeoBanking.Api.Auth;

public static class PasswordPolicy
{
    public const int MinimumLength = 12;

    public static ApplicationError? Validate(string? password)
    {
        if (string.IsNullOrEmpty(password) ||
            password.Length < MinimumLength ||
            !password.Any(char.IsUpper) ||
            !password.Any(char.IsLower) ||
            !password.Any(char.IsDigit))
        {
            return new ApplicationError(
                "auth.password.weak",
                "Use at least 12 characters with uppercase, lowercase, and a number.",
                StatusCodes.Status400BadRequest);
        }

        return null;
    }
}
