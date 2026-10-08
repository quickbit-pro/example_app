using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Controllers;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobileProfileControllerTests
{
    [Theory]
    [InlineData("submitted", false, false)]
    [InlineData("pending", false, false)]
    [InlineData("rejected", false, false)]
    [InlineData("approved", true, true)]
    [InlineData("approved", false, false)]
    public async Task GetCurrentUser_CardEligibilityRequiresInterlaceApproval(
        string issuerStatus, bool issuerApproved, bool expected)
    {
        var kyc = JsonSerializer.Serialize(new
        {
            hoppaCardKycApproved = true,
            interlace = new { status = issuerStatus, approved = issuerApproved },
            equalsMoney = new { accountId = "existing-bank-account", approved = true }
        });
        var proxy = new GatedProxy(
            ("/api/v2/users/10466", """{ "accountType": "personal" }"""),
            ("/api/v2/users/10466/kyc/detailed-status", kyc));
        var dbContext = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(dbContext);
        var controller = new MobileProfileController(dbContext, proxy)
        {
            ControllerContext = MobileIdentityTestSupport.ControllerContext(user.Id)
        };
        var pending = controller.GetCurrentUser(CancellationToken.None);
        await proxy.Arrived(2);
        proxy.Release();
        var payload = MobileIdentityTestSupport.Payload(await pending);
        Assert.Equal("approved", payload.GetProperty("kycStatus").GetString());
        Assert.Equal("completed", payload.GetProperty("onboardingStatus").GetString());
        Assert.Equal(expected, payload.GetProperty("interlaceKycApproved").GetBoolean());
    }

    [Fact]
    public async Task GetCurrentUser_RequestsAccountTypeAndKycStatusTogether()
    {
        var proxy = new GatedProxy(
            ("/api/v2/users/10466", """{ "accountType": "business" }"""),
            ("/api/v2/users/10466/kyc/detailed-status", """{ "EqualsMoney": { "ApplicationStatus": "submitted" } }"""));
        var dbContext = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(dbContext);
        var controller = new MobileProfileController(dbContext, proxy)
        {
            ControllerContext = MobileIdentityTestSupport.ControllerContext(user.Id)
        };

        var pending = controller.GetCurrentUser(CancellationToken.None);
        await proxy.Arrived(2);

        Assert.Equal(
            ["/api/v2/users/10466", "/api/v2/users/10466/kyc/detailed-status"],
            proxy.Paths.Order());

        proxy.Release();
        var payload = MobileIdentityTestSupport.Payload(await pending);

        Assert.Equal("business", payload.GetProperty("accountType").GetString());
        Assert.Equal("submitted", payload.GetProperty("onboardingStatus").GetString());
        var onboarding = payload.GetProperty("onboarding");
        Assert.Equal("submitted", onboarding.GetProperty("status").GetString());
        Assert.Equal("business", onboarding.GetProperty("kind").GetString());
        Assert.Equal("start", onboarding.GetProperty("currentStep").GetString());
        Assert.Equal(["start_onboarding"], onboarding.GetProperty("requiredActions").EnumerateArray().Select(item => item.GetString()));
        Assert.Equal(2, proxy.Paths.Count);
        Assert.False(payload.GetProperty("interlaceKycApproved").GetBoolean());
    }

    [Fact]
    public async Task GetCurrentUser_EmbedsCompletedOnboardingFromLiveBankingStatus()
    {
        var proxy = new GatedProxy(
            ("/api/v2/users/10466", """{ "accountType": "personal" }"""),
            ("/api/v2/users/10466/kyc/detailed-status", """{ "EqualsMoney": { "AccountId": "F59168" } }"""));
        var dbContext = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(dbContext);
        var controller = new MobileProfileController(dbContext, proxy)
        {
            ControllerContext = MobileIdentityTestSupport.ControllerContext(user.Id)
        };

        var pending = controller.GetCurrentUser(CancellationToken.None);
        await proxy.Arrived(2);
        proxy.Release();
        var onboarding = MobileIdentityTestSupport.Payload(await pending).GetProperty("onboarding");

        Assert.Equal("completed", onboarding.GetProperty("status").GetString());
        Assert.Equal("complete", onboarding.GetProperty("currentStep").GetString());
        Assert.Empty(onboarding.GetProperty("requiredActions").EnumerateArray());
    }
}
