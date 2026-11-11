using System.Text.Json;
using Microsoft.Extensions.Options;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Auth;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Company;

/// <summary>The platform infers the company from this installation's server credential; no public tenant input.</summary>
public sealed class CompanyRegistrationPolicy(IProxyHoppaRequestUseCase platform, IOptions<CompanyOptions> options)
{
    // Scoped to one incoming request, never retained across policy changes.
    private Task<RegistrationPolicySnapshot>? resolved;

    public Task<RegistrationPolicySnapshot> GetAsync(CancellationToken ct) => resolved ??= LoadAsync(ct);

    private async Task<RegistrationPolicySnapshot> LoadAsync(CancellationToken ct)
    {
        try
        {
            var response = await platform.ExecuteAsync(new ProxyHoppaRequestCommand<object>
            {
                Method = HttpMethod.Get,
                UpstreamPath = "/api/v2/users/registration-policy",
                FailureCode = "auth.signup.policy_unavailable",
                FailureMessage = "Registration settings are temporarily unavailable.",
                SuppressPayloadLogging = true
            }, ct);
            return response.IsSuccess && response.Value is { } json
                ? Parse(json, options.Value.DashboardCompanyId)
                : RegistrationPolicySnapshot.Unavailable;
        }
        catch (Exception error) when (error is HttpRequestException or JsonException or InvalidDataException ||
                                      error is OperationCanceledException && !ct.IsCancellationRequested)
        {
            return RegistrationPolicySnapshot.Unavailable;
        }
    }

    public static RegistrationPolicySnapshot Parse(JsonElement value, int? expectedCompany)
    {
        if (value.ValueKind != JsonValueKind.Object || !value.TryGetProperty("companyId", out var id))
            return RegistrationPolicySnapshot.Unavailable;
        // Legacy deployments already pin the numeric dashboard company. When no
        // pin is configured, the upstream authenticates this installation's server
        // credential and returns its inferred company; no client tenant is accepted.
        var matchesCompany = id.ValueKind == JsonValueKind.Number
            ? id.TryGetInt32(out var companyId) && companyId > 0 &&
                (expectedCompany is null || companyId == expectedCompany)
            : expectedCompany is null && id.ValueKind == JsonValueKind.String &&
                Guid.TryParse(id.GetString(), out var company) && company != Guid.Empty;
        if (!matchesCompany) return RegistrationPolicySnapshot.Unavailable;
        bool? Flag(string name) => value.TryGetProperty(name, out var flag) && flag.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? flag.GetBoolean() : null;
        var allows = Flag("allowsSelfRegistration"); var wallet = Flag("requireExternalWallet");
        var needsCode = Flag("needsReferralCode"); var optional = Flag("referralCodeOptional");
        var program = Flag("referralProgramEnabled");
        if (allows is null || wallet is null || needsCode is null || optional is null || program is null ||
            !value.TryGetProperty("blockedCountries", out var countries) || countries.ValueKind != JsonValueKind.Array)
            return RegistrationPolicySnapshot.Unavailable;
        var blocked = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var country in countries.EnumerateArray())
        {
            if (country.ValueKind != JsonValueKind.String) return RegistrationPolicySnapshot.Unavailable;
            var code = country.GetString()?.Trim().ToUpperInvariant();
            if (!RegistrationPolicySnapshot.IsCountry(code)) return RegistrationPolicySnapshot.Unavailable;
            blocked.Add(code!);
        }
        return new(true, allows.Value, wallet.Value, needsCode.Value, optional.Value, program.Value, blocked.Order().ToArray());
    }
}

public sealed record RegistrationPolicySnapshot(bool Available, bool AllowsSelfRegistration, bool RequireExternalWallet,
    bool NeedsReferralCode, bool ReferralCodeOptional, bool ReferralProgramEnabled, IReadOnlyList<string> BlockedCountries)
{
    public static RegistrationPolicySnapshot Unavailable { get; } = new(false, false, false, false, false, false, []);
    public bool ReferralRequired => NeedsReferralCode && !ReferralCodeOptional;
    public bool ReferralsEnabled => NeedsReferralCode || ReferralProgramEnabled;
    public static bool IsCountry(string? code) => code is { Length: 2 } && code.All(c => c is >= 'A' and <= 'Z');

    public ApplicationError? Validate(SignupRequestDto request)
    {
        if (!Available) return new("auth.signup.policy_unavailable", "Registration settings are temporarily unavailable. Please try again later.", 503);
        if (!AllowsSelfRegistration) return new("auth.signup.registration_disabled", "Self-registration is not enabled for this company.", 403);
        if (RequireExternalWallet && string.IsNullOrWhiteSpace(request.ExternalWalletAddress))
            return new("auth.signup.external_wallet_required", "An external wallet address is required for registration.", 400);
        if (request.ExternalWalletAddress?.Trim().Length > 512)
            return new("auth.signup.external_wallet_invalid", "The external wallet address is too long.", 400);
        var country = request.CountryCode?.Trim().ToUpperInvariant();
        if (BlockedCountries.Count > 0 && string.IsNullOrEmpty(country))
            return new("auth.signup.country_required", "Select your country of residence.", 400);
        if (!string.IsNullOrEmpty(country) && !IsCountry(country))
            return new("auth.signup.country_invalid", "Select a valid two-letter country code.", 400);
        if (country is not null && BlockedCountries.Contains(country, StringComparer.OrdinalIgnoreCase))
            return new("auth.signup.country_blocked", "Registration is not available in your country of residence.", 403);
        if (ReferralRequired && string.IsNullOrWhiteSpace(request.ReferralCode))
            return new("auth.referral.required", "A valid referral code is required to create an account.", 400);
        return null;
    }
}
