#nullable enable

namespace NeoBanking.Infrastructure.Persistence.Seeders;

public sealed class AdminSeedOptions
{
    public const string SectionName = "SeedAdmin";

    public string Email { get; init; } = string.Empty;

    public string Password { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;
}
