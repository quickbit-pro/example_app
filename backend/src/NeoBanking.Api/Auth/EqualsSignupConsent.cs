using System.Text.Json;
using NeoBanking.Api.Company;

namespace NeoBanking.Api.Auth;

/// <summary>Validate separate Equals agreements before creating either local or upstream accounts.</summary>
public static class EqualsSignupConsent
{
    public static string PrivacyUrl(string region) => region.Trim().Equals("UK", StringComparison.OrdinalIgnoreCase)
        ? "https://equalsmoney.com/privacy" : "https://equalsmoney.com/en-be/privacy";

    public static string? Validate(Dictionary<string, object?>? agreements, bool required, BrandingOptions branding)
    {
        if (!required) return null;
        if (!Uri.TryCreate(branding.EqualsGeneralTermsUrl, UriKind.Absolute, out var terms) || terms.Scheme != "https")
            return "Equals Money terms are currently unavailable. Please contact support before continuing.";
        var data = JsonSerializer.SerializeToElement(agreements);
        bool Accepted(string name) => data.ValueKind == JsonValueKind.Object &&
            data.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;
        if (!Accepted("equalsTerms") || !Accepted("equalsPrivacy") || !Accepted("equalsTermsAccessed"))
            return "Open the Equals Money Terms and Conditions and accept them and the separate Equals Privacy Policy to continue.";
        if (!data.TryGetProperty("documents", out var documents) || documents.ValueKind != JsonValueKind.Object ||
            !documents.TryGetProperty("equalsGeneralTermsUrl", out var termsUrl) || termsUrl.ValueKind != JsonValueKind.String ||
            termsUrl.GetString() != branding.EqualsGeneralTermsUrl ||
            !documents.TryGetProperty("equalsPrivacyUrl", out var privacyUrl) || privacyUrl.ValueKind != JsonValueKind.String ||
            privacyUrl.GetString() != PrivacyUrl(branding.EqualsRegulatoryRegionDefault))
            return "The Equals Money documents changed. Refresh and review the current documents before continuing.";
        if (!string.IsNullOrEmpty(branding.EqualsTermsVersion) &&
            (!data.TryGetProperty("equalsTermsVersion", out var version) || version.ValueKind != JsonValueKind.String ||
                version.GetString() != branding.EqualsTermsVersion))
            return "The Equals Money terms version changed. Refresh and review the current documents before continuing.";
        return null;
    }

    public static object Record(Dictionary<string, object?>? agreements, bool required, BrandingOptions branding, DateTimeOffset receivedAt)
    {
        var record = new Dictionary<string, object?>(agreements ?? new());
        record["acceptedAt"] = receivedAt;
        record["channel"] = "mobile";
        if (required)
        {
            // Separate affirmative actions, with server-selected URLs and server receipt time.
            record["equalsAcceptances"] = new[] {
                new { agreementType = "equals_money_terms", documentUrl = branding.EqualsGeneralTermsUrl!,
                    documentVersionReference = branding.EqualsTermsVersion ?? branding.EqualsGeneralTermsUrl!, acceptedAt = receivedAt },
                new { agreementType = "equals_money_privacy", documentUrl = PrivacyUrl(branding.EqualsRegulatoryRegionDefault),
                    documentVersionReference = PrivacyUrl(branding.EqualsRegulatoryRegionDefault), acceptedAt = receivedAt }
            };
        }
        return record;
    }
}
