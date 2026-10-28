using System.Text.Json;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;

namespace NeoBanking.Api.Company;

/// <summary>Resolve one server-selected active/default dashboard entry, shared by display and consent.</summary>
public sealed class DashboardLegalSettings(HttpClient client, IOptions<CompanyOptions> options,
    IMemoryCache cache, ILogger<DashboardLegalSettings> logger)
{
    private Task<BrandingOptions>? resolved;
    public Task<BrandingOptions> GetAsync(CancellationToken ct) => resolved ??= LoadAsync(ct);

    private async Task<BrandingOptions> LoadAsync(CancellationToken ct)
    {
        var company = options.Value;
        if (string.IsNullOrWhiteSpace(company.DashboardBrandingUrl)) return company.Branding;
        var key = $"dashboard-legal:{company.DashboardBrandingUrl}:{company.DashboardCompanyId}:{company.DashboardBrandingDomain}";
        if (cache.TryGetValue<BrandingOptions>(key, out var cached)) return cached!;
        try
        {
            if (!Uri.TryCreate(company.DashboardBrandingUrl, UriKind.Absolute, out var uri) ||
                uri.Scheme != "https" || !string.IsNullOrEmpty(uri.UserInfo))
                throw new InvalidDataException("Dashboard settings URL must use HTTPS.");
            var json = await client.GetFromJsonAsync<JsonElement>(uri, ct);
            var branding = Parse(json, company);
            cache.Set(key, branding, TimeSpan.FromMinutes(1));
            return branding;
        }
        catch (Exception error) when (error is HttpRequestException or JsonException or InvalidDataException or OperationCanceledException)
        {
            logger.LogWarning("Dashboard legal settings unavailable; Equals acceptance remains blocked.");
            // Never silently accept an old locally configured document after a dashboard failure.
            return new BrandingOptions();
        }
    }

    public static BrandingOptions Parse(JsonElement json, CompanyOptions company)
    {
        if (json.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Invalid dashboard settings.");
        string? Text(string name) => json.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()?.Trim() : null;
        if (!json.TryGetProperty("companyId", out var id) || id.ValueKind != JsonValueKind.Number || !id.TryGetInt32(out var companyId) ||
            companyId != company.DashboardCompanyId || Text("domain") != company.DashboardBrandingDomain ||
            Text("variantName") != "default" || !json.TryGetProperty("isActive", out var active) || active.ValueKind != JsonValueKind.True)
            throw new InvalidDataException("Dashboard entry does not match the active default tenant.");
        return new BrandingOptions
        {
            LogoUrl = company.Branding.LogoUrl, PrimaryColor = company.Branding.PrimaryColor,
            SupportEmail = Text("supportEmail"), TermsUrl = Text("termsUrl"), PrivacyUrl = Text("privacyUrl"),
            ESignUrl = Text("eSignUrl"), ECommunicationNoticeUrl = Text("eCommunicationNoticeUrl"),
            GeneralTermsUrl = Text("interlaceGeneralTermsUrl"), GeneralTermsUsUrl = Text("interlaceGeneralTermsUrl2"),
            AdditionalAcknowledgementsUrl = Text("additionalAcknowledgementsUrl"),
            EqualsGeneralTermsUrl = Text("equalsGeneralTermsUrl"), EqualsTermsVersion = Text("equalsTermsVersion"),
            EqualsTermsEffectiveDate = Text("equalsTermsEffectiveDate"),
            EqualsRegulatoryDisclaimerEu = Text("equalsRegulatoryDisclaimerEu"),
            EqualsRegulatoryDisclaimerUk = Text("equalsRegulatoryDisclaimerUk"),
            EqualsRegulatoryRegionDefault = Text("equalsRegulatoryRegionDefault") ?? "EU"
        };
    }
}
