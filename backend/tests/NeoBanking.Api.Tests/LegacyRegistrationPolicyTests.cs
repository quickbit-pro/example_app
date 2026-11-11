using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Auth;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class LegacyRegistrationPolicyTests
{
    [Fact]
    public void Policy_NumericTenantMustMatchConfiguredCompany()
    {
        Assert.True(CompanyRegistrationPolicy.Parse(Policy(14), 14).Available);
        Assert.True(CompanyRegistrationPolicy.Parse(Policy(14), null).Available);
        Assert.False(CompanyRegistrationPolicy.Parse(Policy(14), 1).Available);
        Assert.False(CompanyRegistrationPolicy.Parse(Policy(0), null).Available);
        Assert.False(CompanyRegistrationPolicy.Parse(Policy(-1), null).Available);
        Assert.False(CompanyRegistrationPolicy.Parse(Policy("14"), null).Available);
    }

    [Fact]
    public void Policy_GuidTenantIsSupportedOnlyWithoutConflictingNumericPin()
    {
        var policy = Policy("00000000-0000-7000-8000-000000000014");
        Assert.True(CompanyRegistrationPolicy.Parse(policy, null).Available);
        Assert.False(CompanyRegistrationPolicy.Parse(policy, 14).Available);
        Assert.False(CompanyRegistrationPolicy.Parse(Policy(Guid.Empty), null).Available);
    }

    [Theory]
    [InlineData("companyId")]
    [InlineData("allowsSelfRegistration")]
    [InlineData("requireExternalWallet")]
    [InlineData("needsReferralCode")]
    [InlineData("referralCodeOptional")]
    [InlineData("referralProgramEnabled")]
    [InlineData("blockedCountries")]
    public void Policy_MissingRequiredFieldFailsClosed(string field)
    {
        var fields = JsonSerializer.Deserialize<Dictionary<string, object?>>(Policy(14).GetRawText())!;
        fields.Remove(field);
        Assert.False(CompanyRegistrationPolicy.Parse(JsonSerializer.SerializeToElement(fields), null).Available);
    }

    [Theory]
    [InlineData("allowsSelfRegistration", "true")]
    [InlineData("blockedCountries", "US")]
    [InlineData("blockedCountries", new[] { "USA" })]
    public void Policy_MalformedValueFailsClosed(string field, object value)
    {
        var fields = JsonSerializer.Deserialize<Dictionary<string, object?>>(Policy(14).GetRawText())!;
        fields[field] = value;
        Assert.False(CompanyRegistrationPolicy.Parse(JsonSerializer.SerializeToElement(fields), null).Available);
    }

    [Theory]
    [InlineData(null, "auth.signup.country_required")]
    [InlineData(" us ", "auth.signup.country_blocked")]
    [InlineData("United Kingdom", "auth.signup.country_invalid")]
    public void Signup_ResidenceValidationUsesExplicitCountryOnly(string? country, string error)
    {
        var policy = CompanyRegistrationPolicy.Parse(Policy(14, blocked: ["US"]), 14);
        Assert.Equal(error, policy.Validate(new SignupRequestDto { CountryCode = country, Phone = "+442071234567" })?.Code);
        Assert.Null(policy.Validate(new SignupRequestDto { CountryCode = " gb " }));
    }

    [Fact]
    public async Task Config_ExposesAuthoritativePolicyAndPreservesUnrelatedFeatures()
    {
        var proxy = new Proxy { Response = Policy(14, blocked: [" us ", "US", "CA"], wallet: true, referral: true) };
        var options = Options.Create(new CompanyOptions { Name = "Songs", DashboardCompanyId = 14,
            Features = new() { ReferralsEnabled = false, VouchersEnabled = true } });
        var controller = new MobileConfigurationController(options, new CompanyRegistrationPolicy(proxy, options))
            { ControllerContext = new() { HttpContext = new DefaultHttpContext() } };
        var result = Assert.IsType<OkObjectResult>((await controller.Get()).Result);
        var body = JsonSerializer.SerializeToElement(result.Value, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        var registration = body.GetProperty("registration");
        Assert.True(registration.GetProperty("available").GetBoolean());
        Assert.True(registration.GetProperty("allowsSelfRegistration").GetBoolean());
        Assert.True(registration.GetProperty("requireExternalWallet").GetBoolean());
        Assert.True(registration.GetProperty("referralRequired").GetBoolean());
        Assert.True(registration.GetProperty("referralCodesEnabled").GetBoolean());
        Assert.Equal(new[] { "CA", "US" }, registration.GetProperty("blockedCountries").EnumerateArray().Select(x => x.GetString()));
        Assert.Equal("Songs", body.GetProperty("company").GetProperty("name").GetString());
        Assert.True(body.GetProperty("features").GetProperty("vouchersEnabled").GetBoolean());
        Assert.False(body.GetProperty("features").GetProperty("referralsEnabled").GetBoolean());
        Assert.Equal("no-store", controller.Response.Headers.CacheControl.ToString());
        Assert.Equal("/api/v2/users/registration-policy", Assert.Single(proxy.Paths));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Config_UpstreamFailureOrTenantMismatchDisablesSignup(bool mismatch)
    {
        var proxy = new Proxy { Available = mismatch, Response = Policy(99) };
        var options = Options.Create(new CompanyOptions { Name = "Existing company", DashboardCompanyId = 14 });
        var controller = new MobileConfigurationController(options, new CompanyRegistrationPolicy(proxy, options))
            { ControllerContext = new() { HttpContext = new DefaultHttpContext() } };
        var result = Assert.IsType<OkObjectResult>((await controller.Get()).Result);
        var body = JsonSerializer.SerializeToElement(result.Value, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Assert.False(body.GetProperty("registration").GetProperty("available").GetBoolean());
        Assert.False(body.GetProperty("registration").GetProperty("allowsSelfRegistration").GetBoolean());
        Assert.Equal("Existing company", body.GetProperty("company").GetProperty("name").GetString());
    }

    [Fact]
    public async Task Policy_IsReusedWithinRequestButReloadedForNextRequest()
    {
        var proxy = new Proxy { Response = Policy(14) };
        var options = Options.Create(new CompanyOptions { DashboardCompanyId = 14 });
        var current = new CompanyRegistrationPolicy(proxy, options);
        Assert.True((await current.GetAsync(default)).AllowsSelfRegistration);
        await current.GetAsync(default);
        Assert.Single(proxy.Paths);
        proxy.Response = Policy(14, allowed: false);
        Assert.False((await new CompanyRegistrationPolicy(proxy, options).GetAsync(default)).AllowsSelfRegistration);
        Assert.Equal(2, proxy.Paths.Count);
    }

    private static JsonElement Policy(object companyId, bool allowed = true, string[]? blocked = null, bool wallet = false, bool referral = false) =>
        JsonSerializer.SerializeToElement(new { companyId, allowsSelfRegistration = allowed, requireExternalWallet = wallet,
            needsReferralCode = referral, referralCodeOptional = !referral, referralProgramEnabled = false, blockedCountries = blocked ?? [] });

    private sealed class Proxy : IProxyHoppaRequestUseCase
    {
        public bool Available { get; init; } = true;
        public JsonElement Response { get; set; } = Policy(14);
        public List<string> Paths { get; } = [];
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command, CancellationToken cancellationToken)
        {
            Assert.Equal(HttpMethod.Get, command.Method);
            Assert.Null(command.Request);
            Paths.Add(command.UpstreamPath);
            return Task.FromResult(Available ? ApplicationResult<JsonElement?>.Success(Response)
                : ApplicationResult<JsonElement?>.Failure(new("unavailable", "Unavailable", 503)));
        }
    }
}
