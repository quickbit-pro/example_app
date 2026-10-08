using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Controllers;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class ActivationProgressTests
{
    [AssistantPostgresFact]
    public async Task Migration_ClaimsIntroductionOnceAcrossDevices_AndKeepsDepositAfterSpending()
    {
        await using var fixture = await ActivationDatabase.CreateAsync(useMigrations: true);
        await using var first = fixture.Context();
        await using var second = fixture.Context();
        var results = await Task.WhenAll(
            Controller(first, fixture.CompanyId, fixture.OwnerId).RecordProgress(new(true, true), default),
            Controller(second, fixture.CompanyId, fixture.OwnerId).RecordProgress(new(true, true), default));
        Assert.Single(results, result => Json(result).GetProperty("ShowIntroduction").GetBoolean());
        await using var nextSession = fixture.Context();
        var returning = Json(await Controller(nextSession, fixture.CompanyId, fixture.OwnerId)
            .RecordProgress(new(false, true), default));
        Assert.False(returning.GetProperty("ShowIntroduction").GetBoolean());
        Assert.True(returning.GetProperty("HasCompletedDeposit").GetBoolean());
        var otherAccount = Json(await Controller(nextSession, fixture.CompanyId, fixture.PayerAId)
            .RecordProgress(new(false, true), default));
        Assert.True(otherAccount.GetProperty("ShowIntroduction").GetBoolean());
        Assert.False(otherAccount.GetProperty("HasCompletedDeposit").GetBoolean());
        Assert.False(nextSession.Database.HasPendingModelChanges());
    }

    [AssistantPostgresFact]
    public async Task WrongTenantAndMissingIdentityCannotChangeProgress()
    {
        await using var fixture = await ActivationDatabase.CreateAsync();
        await using var db = fixture.Context();
        Assert.IsType<NotFoundResult>(await Controller(db, fixture.OtherCompanyId, fixture.OwnerId)
            .RecordProgress(new(true, true), default));
        var anonymous = new MobileActivationController(db) { ControllerContext = new() { HttpContext = new DefaultHttpContext() } };
        Assert.IsType<UnauthorizedResult>(await anonymous.RecordProgress(new(true, true), default));
        var user = await db.Users.AsNoTracking().SingleAsync(u => u.Id == fixture.OwnerId);
        Assert.Null(user.ActivationIntroShownAt);
        Assert.Null(user.FirstDepositObservedAt);
    }

    private static JsonElement Json(IActionResult result) => JsonSerializer.SerializeToElement(Assert.IsType<OkObjectResult>(result).Value);
    private static MobileActivationController Controller(NeoBankingDbContext db, Guid company, Guid user) => new(db)
    {
        ControllerContext = new() { HttpContext = new DefaultHttpContext {
            User = new ClaimsPrincipal(new ClaimsIdentity([
                new Claim("local_user_id", user.ToString()), new Claim("company_installation_id", company.ToString())], "test")) } }
    };
}
