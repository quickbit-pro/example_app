using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Company;
using NeoBanking.Api.Controllers;
using NeoBanking.Domain.Entities;
using Xunit;

namespace NeoBanking.Api.Tests;

public class EqualsReagreementTests
{
    private static IOptions<CompanyOptions> Options(string? url = "https://example.test/terms-v1.pdf", bool enabled = true) =>
        Microsoft.Extensions.Options.Options.Create(new CompanyOptions {
            Features = new() { EqualsMoneyEnabled = enabled },
            Branding = new() { EqualsGeneralTermsUrl = url }
        });

    private static DefaultHttpContext Context(ApplicationUser user, Guid? company = null) => new() {
        User = new ClaimsPrincipal(new ClaimsIdentity(new[] {
            new Claim("local_user_id", user.Id.ToString()),
            new Claim("company_installation_id", (company ?? user.CompanyInstallationId).ToString())
        }, "test"))
    };

    [Fact]
    public async Task ExistingCustomerRequiresBothRecordsAndChangedDocumentsRequireFreshConsent()
    {
        await using var db = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(db);
        var options = Options();
        var service = new EqualsConsentService(db, options);
        Assert.True((await service.StatusAsync(user, default)).RequiresAcceptance);
        var received = DateTimeOffset.UtcNow;
        EqualsConsentService.AddEvidence(db, user, options.Value.Branding, received, "mobile_reagreement");
        await db.SaveChangesAsync();
        Assert.False((await service.StatusAsync(user, default)).RequiresAcceptance);
        var evidence = await db.AuditLogEntries.ToListAsync();
        Assert.Equal(2, evidence.Count);
        Assert.All(evidence, row => Assert.Equal(received, row.OccurredAt));
        Assert.Equal(2, evidence.Select(x => x.EntityType).Distinct().Count());
        var changed = new EqualsConsentService(db, Options("https://example.test/terms-v2.pdf"));
        Assert.True((await changed.StatusAsync(user, default)).RequiresAcceptance);
        Assert.Equal(2, await db.AuditLogEntries.CountAsync()); // Never rewrite history.
        db.AuditLogEntries.Remove(evidence.Single(x => x.EntityType == "equals_money_privacy"));
        await db.SaveChangesAsync();
        Assert.True((await service.StatusAsync(user, default)).RequiresAcceptance);
    }

    [Fact]
    public async Task AcceptRejectsStaleAndIncompleteRequestsAndIsIdempotentAfterSuccess()
    {
        await using var db = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(db);
        var options = Options();
        var controller = new MobileEqualsAgreementsController(db, new(db, options), options) {
            ControllerContext = new() { HttpContext = Context(user) }
        };
        var documents = EqualsConsentService.Documents(options.Value.Branding);
        var request = new AcceptEqualsAgreements(documents.Version, documents.TermsUrl, documents.PrivacyUrl, true, true, true);
        Assert.IsType<ConflictObjectResult>(await controller.Accept(request with { Version = "old" }, default));
        Assert.IsType<ConflictObjectResult>(await controller.Accept(request with { PrivacyUrl = "https://other.test" }, default));
        Assert.IsType<BadRequestObjectResult>(await controller.Accept(request with { TermsAccepted = false }, default));
        Assert.IsType<BadRequestObjectResult>(await controller.Accept(request with { PrivacyAccepted = false }, default));
        Assert.IsType<BadRequestObjectResult>(await controller.Accept(request with { TermsAccessed = false }, default));
        Assert.Empty(db.AuditLogEntries);
        Assert.IsType<OkObjectResult>(await controller.Accept(request, default));
        Assert.IsType<OkObjectResult>(await controller.Accept(request, default));
        Assert.Equal(2, await db.AuditLogEntries.CountAsync());
    }

    [Fact]
    public async Task IdentityCannotCrossCompanyAndMissingTermsFailClosed()
    {
        await using var db = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(db);
        var options = Options(null);
        var service = new EqualsConsentService(db, options);
        Assert.True((await service.StatusAsync(user, default)).RequiresAcceptance);
        Assert.False((await service.StatusAsync(user, default)).Documents.Available);
        var controller = new MobileEqualsAgreementsController(db, service, options) {
            ControllerContext = new() { HttpContext = Context(user, Guid.NewGuid()) }
        };
        Assert.IsType<UnauthorizedResult>(await controller.Status(default));
        var request = new AcceptEqualsAgreements("", "", "", true, true, true);
        Assert.IsType<UnauthorizedResult>(await controller.Accept(request, default));
        controller.ControllerContext = new() { HttpContext = Context(user) };
        Assert.Equal(503, Assert.IsType<ObjectResult>(await controller.Accept(request, default)).StatusCode);
        Assert.Empty(db.AuditLogEntries);
    }

    [Fact]
    public async Task NonEqualsPersonalCustomerIsUnaffectedButBusinessStillRequiresConsent()
    {
        await using var db = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(db);
        var service = new EqualsConsentService(db, Options(enabled: false));
        user.MetadataJson = "{\"accountType\":\"personal\"}";
        Assert.False((await service.StatusAsync(user, default)).Required);
        user.MetadataJson = "{\"accountType\":\"business\"}";
        Assert.True((await service.StatusAsync(user, default)).RequiresAcceptance);
    }

    [Theory]
    [InlineData("POST", "/api/v1/mobile/banking/payouts", false)]
    [InlineData("PATCH", "/api/v1/mobile/banking/payees/123", false)]
    [InlineData("GET", "/api/v1/mobile/banking/accounts", true)]
    [InlineData("DELETE", "/api/v1/mobile/banking/payees/123", true)]
    [InlineData("POST", "/api/v1/mobile/banking/transfers/123/cancel", true)]
    public async Task BankingMutationsRequireConsentWhileReadsAndCancellationRemainAvailable(string method, string path, bool allowed)
    {
        await using var db = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(db);
        var http = Context(user); http.Request.Method = method; http.Request.Path = path;
        var action = new ActionContext(http, new RouteData(), new ActionDescriptor());
        var context = new ActionExecutingContext(action, [], new Dictionary<string, object?>(), new object());
        var called = false;
        Task<ActionExecutedContext> Next() {
            called = true;
            return Task.FromResult(new ActionExecutedContext(action, [], context.Controller));
        }
        var options = Options();
        var filter = new EqualsConsentFilter(db, new(db, options));
        await filter.OnActionExecutionAsync(context, Next);
        Assert.Equal(allowed, called);
        if (!allowed) {
            Assert.Equal(428, Assert.IsType<ObjectResult>(context.Result).StatusCode);
            EqualsConsentService.AddEvidence(db, user, options.Value.Branding, DateTimeOffset.UtcNow, "mobile_signup");
            await db.SaveChangesAsync();
            context.Result = null;
            await filter.OnActionExecutionAsync(context, Next);
            Assert.True(called);
            Assert.Null(context.Result);
        }
    }
}
