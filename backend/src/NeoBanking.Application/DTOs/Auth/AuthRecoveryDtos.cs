namespace NeoBanking.Application.DTOs.Auth;

public sealed class ForgotPasswordRequestDto
{
    public string? Email { get; init; }
}

public sealed class ResetPasswordRequestDto
{
    public string? Email { get; init; }

    public string? Code { get; init; }

    public string? NewPassword { get; init; }
}

public sealed class VerifyEmailRequestDto
{
    public string? Email { get; init; }

    public string? Code { get; init; }
}

public sealed class ResendVerificationRequestDto
{
    public string? Email { get; init; }
}

public sealed class VerificationCodeIssuedResponseDto
{
    public string Message { get; init; } = string.Empty;

    public int ExpiresInMinutes { get; init; }

    public int RetryAfterSeconds { get; init; }

    public string RequestId { get; init; } = string.Empty;
}
