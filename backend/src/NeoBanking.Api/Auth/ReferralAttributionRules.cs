namespace NeoBanking.Api.Auth;

/// <summary>
/// Registration-time referral rules shared by the mobile sign-up flow. The platform refuses an
/// attribution that the new user did not accept, so the decision is taken here before the call.
/// </summary>
public static class ReferralAttributionRules
{
    public const string ManualCodeSource = "MANUAL_CODE";
    public const string LinkSource = "LINK";
    public const string EmailInvitationSource = "EMAIL_INVITATION";
    public const string CampaignLinkSource = "CAMPAIGN_LINK";

    /// <summary>Reason code returned when a referral code was supplied but not accepted.</summary>
    public const string NotAcceptedReason = "auth.referral.not_accepted";

    public static string NormalizeSource(string? value)
    {
        return value?.Trim().ToUpperInvariant() switch
        {
            LinkSource => LinkSource,
            CampaignLinkSource => CampaignLinkSource,
            EmailInvitationSource => EmailInvitationSource,
            _ => ManualCodeSource
        };
    }

    /// <summary>A source label is not evidence of an invitation or consent. Verified invitation acceptance is handled by the authoritative engine.</summary>
    public static bool IsAccepted(bool? referralAccepted, string? source) => referralAccepted == true;
}
