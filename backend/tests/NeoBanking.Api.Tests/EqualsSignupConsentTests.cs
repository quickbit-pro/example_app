using System.Text.Json;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Company;
using Xunit;

namespace NeoBanking.Api.Tests;

public class EqualsSignupConsentTests
{
    private static readonly BrandingOptions Branding = new() {
        EqualsGeneralTermsUrl = "https://example.test/equals-v12.pdf", EqualsRegulatoryRegionDefault = "EU"
    };
    private static Dictionary<string, object?> Consent() => new() {
        ["equalsTerms"] = true, ["equalsPrivacy"] = true, ["equalsTermsAccessed"] = true,
        ["documents"] = new { equalsGeneralTermsUrl = Branding.EqualsGeneralTermsUrl,
            equalsPrivacyUrl = EqualsSignupConsent.PrivacyUrl("EU") }
    };
    [Fact]
    public void CurrentSeparateConsentAccepted() => Assert.Null(EqualsSignupConsent.Validate(Consent(), true, Branding));
    [Theory]
    [InlineData("equalsTerms")]
    [InlineData("equalsPrivacy")]
    [InlineData("equalsTermsAccessed")]
    public void EveryActionMustBeExplicitTrue(string key)
    {
        foreach (var value in new object?[] { null, false, "true" }) {
            var consent = Consent(); consent[key] = value;
            Assert.NotNull(EqualsSignupConsent.Validate(consent, true, Branding));
        }
    }
    [Fact]
    public void StaleDocumentsAndMissingConfigurationRejected()
    {
        var consent = Consent(); consent["documents"] = new { equalsGeneralTermsUrl = "https://example.test/old.pdf" };
        Assert.NotNull(EqualsSignupConsent.Validate(consent, true, Branding));
        Assert.NotNull(EqualsSignupConsent.Validate(Consent(), true, new BrandingOptions()));
        Assert.NotNull(EqualsSignupConsent.Validate(null, true, Branding));
        Assert.Null(EqualsSignupConsent.Validate(null, false, Branding));
    }
    [Fact]
    public void EvidenceUsesServerTimeAndSeparateRecordsWithoutMutatingRequest()
    {
        var consent = Consent(); consent["acceptedAt"] = "client-controlled";
        var now = DateTimeOffset.Parse("2026-10-26T12:00:00Z");
        var record = JsonSerializer.SerializeToElement(EqualsSignupConsent.Record(consent, true, Branding, now));
        Assert.Equal(now, record.GetProperty("acceptedAt").GetDateTimeOffset());
        Assert.Equal("client-controlled", consent["acceptedAt"]);
        var actions = record.GetProperty("equalsAcceptances");
        Assert.Equal(2, actions.GetArrayLength());
        Assert.Equal("equals_money_terms", actions[0].GetProperty("agreementType").GetString());
        Assert.Equal("equals_money_privacy", actions[1].GetProperty("agreementType").GetString());
        Assert.Equal(now, actions[1].GetProperty("acceptedAt").GetDateTimeOffset());
    }
}
