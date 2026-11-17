using System.Reflection;
using NeoBanking.Application.DTOs.Cards;
using NeoBanking.Application.DTOs.Tiers;
using NeoBanking.Infrastructure.Hoppa;

namespace NeoBanking.Api;

public static class LegacyPlatformContract
{
    public const string Family = "legacy-int-v1";

    public static void Verify()
    {
        RequireInteger(typeof(CardTopUpRequestDto), "CardId");
        RequireInteger(typeof(CardTopUpUpstreamRequestDto), "CardId");
        RequireInteger(typeof(CardUnloadRequestDto), "CardId");
        RequireInteger(typeof(CardUnloadUpstreamRequestDto), "CardId");
        RequireInteger(typeof(CreateCardRequestDto), "CardTypeId");
        RequireInteger(typeof(ChangeUserTierRequestDto), "TierId");
        RequireInteger(typeof(SetUserTierRequestDto), "TierId");
        RequireInteger(typeof(ReferralAuditDelegationOptions), "CompanyId");
    }

    private static void RequireInteger(Type type, string property)
    {
        var value = type.GetProperty(property)?.PropertyType;
        if (value != typeof(int) && value != typeof(int?))
            throw new InvalidOperationException($"Legacy contract violation: {type.Name}.{property} must use an integer platform ID.");
    }

    public static object Describe() => new
    {
        platformContract = Family,
        revision = typeof(LegacyPlatformContract).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion,
        platformIds = "integer"
    };
}
