using System.Text.Json;
using NeoBanking.Api.Controllers;
using NeoBanking.Domain.Entities;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobileOnboardingControllerTests
{
    [Fact]
    public async Task GetStatus_RequestsAccountTypeAndBankingStatusTogether()
    {
        var proxy = new GatedProxy(
            ("/api/v2/users/10466", """{ "data": { "accountType": "personal" } }"""),
            ("/api/v2/users/10466/kyc/detailed-status", """{ "EqualsMoney": { "RequiredAction": "upload_documents" } }"""));
        var dbContext = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(dbContext);
        dbContext.OnboardingApplications.Add(new OnboardingApplication
        {
            CompanyInstallationId = user.CompanyInstallationId,
            ApplicantUserId = user.Id,
            Status = "started",
            CurrentStep = "profile",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        });
        await dbContext.SaveChangesAsync();
        dbContext.ChangeTracker.Clear();
        var controller = new MobileOnboardingController(dbContext, proxy)
        {
            ControllerContext = MobileIdentityTestSupport.ControllerContext(user.Id)
        };

        var pending = controller.GetStatus(CancellationToken.None);
        await proxy.Arrived(2);

        Assert.Equal(
            ["/api/v2/users/10466", "/api/v2/users/10466/kyc/detailed-status"],
            proxy.Paths.Order());

        proxy.Release();
        var payload = MobileIdentityTestSupport.Payload(await pending);

        Assert.Equal("personal", payload.GetProperty("accountType").GetString());
        Assert.Equal("upload_documents", payload.GetProperty("status").GetString());
        Assert.Equal("profile", payload.GetProperty("currentStep").GetString());
        Assert.Equal(["upload_documents"], payload.GetProperty("requiredActions").EnumerateArray().Select(item => item.GetString()));
    }
}
