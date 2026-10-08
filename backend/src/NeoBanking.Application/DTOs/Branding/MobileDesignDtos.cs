namespace NeoBanking.Application.DTOs.Branding;

public sealed class MobileDesignDto
{
    public int SchemaVersion { get; init; } = 1;

    public string AppName { get; init; } = string.Empty;

    public string PrimaryColor { get; init; } = "7C5CFF";

    public string AccentColor { get; init; } = "B6FF6E";

    public string LoginBackgroundColor { get; init; } = string.Empty;

    public string ThemeMode { get; init; } = "dark";

    public string FontFamily { get; init; } = string.Empty;

    public string LogoAsset { get; init; } = string.Empty;

    public string SupportEmail { get; init; } = string.Empty;

    public string SupportPhone { get; init; } = string.Empty;

    public string LegalEntity { get; init; } = string.Empty;

    public DateTimeOffset? UpdatedAt { get; init; }
}

public sealed class UpdateMobileDesignRequestDto
{
    public string? AppName { get; init; }

    public string? PrimaryColor { get; init; }

    public string? AccentColor { get; init; }

    public string? LoginBackgroundColor { get; init; }

    public string? ThemeMode { get; init; }

    public string? FontFamily { get; init; }

    public string? LogoAsset { get; init; }

    public string? SupportEmail { get; init; }

    public string? SupportPhone { get; init; }

    public string? LegalEntity { get; init; }
}
