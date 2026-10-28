using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Api.Controllers;
using NeoBanking.Api.Support;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class ComplaintForwardingTests
{
    [Theory]
    [InlineData("Staging", "staging_preview")]
    [InlineData("Production", "pending")]
    public async Task ComplaintAndForwardingPersistTogether_AndRetryDoesNotDuplicate(string environment, string status)
    {
        await using var db = Database();
        var user = await Seed(db);
        var controller = Controller(db, user, environment);
        var request = new MobileComplaintsController.ComplaintRequest(Guid.NewGuid(), "Payment problem", "I am unhappy <script>test</script>");
        Assert.IsType<CreatedResult>((await controller.Create(request, default)).Result);
        Assert.IsType<OkObjectResult>((await controller.Create(request, default)).Result);
        Assert.Single(db.SupportTickets);
        var email = Assert.Single(db.EmailMessages);
        Assert.Equal(status, email.Status);
        Assert.Equal(EqualsComplaintForwarding.Recipient, email.ToEmail);
        Assert.Contains("Hoppa", email.TextBody);
        Assert.Contains("11068", email.TextBody);
        Assert.Contains(user.Email, email.TextBody);
        Assert.Contains(request.Body, email.TextBody);
        Assert.DoesNotContain("<script>", email.HtmlBody);
        Assert.Null(email.SentAt);
        var detail = await EqualsComplaintForwarding.Detail(db, await db.SupportTickets.Include(x => x.Messages).SingleAsync(), false, default);
        Assert.Equal(status, detail.ComplaintForwarding!.Status);
    }

    [Fact]
    public async Task AnotherCustomerCannotReadOrReuseComplaintRequestId()
    {
        await using var db = Database();
        var owner = await Seed(db);
        var request = new MobileComplaintsController.ComplaintRequest(Guid.NewGuid(), "Problem", "Complaint details");
        await Controller(db, owner, "Production").Create(request, default);
        var other = await Seed(db);
        Assert.IsType<NotFoundResult>((await Controller(db, other, "Production").Create(request, default)).Result);
        Assert.Single(db.SupportTickets);
        Assert.Single(db.EmailMessages);
    }

    [Fact]
    public async Task CustomerFollowUpIsQueuedWithOriginalComplaintContext()
    {
        await using var db = Database();
        var owner = await Seed(db);
        var request = new MobileComplaintsController.ComplaintRequest(Guid.NewGuid(), "Problem", "Original details");
        var controller = Controller(db, owner, "Staging");
        await controller.Create(request, default);
        var ticket = await db.SupportTickets.SingleAsync();
        var support = new MobileSupportTicketsController(db) { ControllerContext = controller.ControllerContext };
        await support.Reply(ticket.Id, new("More information", ticket.Revision), default);
        Assert.Equal(2, await db.EmailMessages.CountAsync());
        var followUp = await db.EmailMessages.SingleAsync(x => x.Id != ticket.Id);
        Assert.Equal("staging_preview", followUp.Status);
        Assert.Contains("Original details", followUp.TextBody);
        Assert.Contains("More information", followUp.TextBody);
    }

    [Fact]
    public async Task AdminForwardingIsTenantScopedAndDoesNotResendPendingComplaint()
    {
        await using var db = Database();
        var owner = await Seed(db);
        var mobile = Controller(db, owner, "Production");
        var request = new MobileComplaintsController.ComplaintRequest(Guid.NewGuid(), "Problem", "Details");
        await mobile.Create(request, default);
        var ticket = await db.SupportTickets.SingleAsync();
        var admin = new AdminComplaintForwardingController(db, Options.Create(new CompanyOptions()), new Environment("Production")) { ControllerContext = mobile.ControllerContext };
        Assert.IsType<OkObjectResult>((await admin.Forward(ticket.Id, new(ticket.Revision), default)).Result);
        Assert.Single(db.EmailMessages);
        admin.ControllerContext = Controller(db, await Seed(db), "Production").ControllerContext;
        Assert.IsType<NotFoundResult>((await admin.Forward(ticket.Id, new(ticket.Revision), default)).Result);
    }

    private static NeoBankingDbContext Database() => new(new DbContextOptionsBuilder<NeoBankingDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
    private static async Task<ApplicationUser> Seed(NeoBankingDbContext db) {
        var user = new ApplicationUser { CompanyInstallationId = Guid.NewGuid(), Email = "member@example.test", EmailNormalized = "MEMBER@EXAMPLE.TEST" };
        db.Users.Add(user); await db.SaveChangesAsync(); return user;
    }
    private static MobileComplaintsController Controller(NeoBankingDbContext db, ApplicationUser user, string environment) =>
        new(db, Options.Create(new CompanyOptions { BrandName = "Hoppa" }), new Environment(environment)) {
            ControllerContext = new() { HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(new ClaimsIdentity([
                new Claim("company_installation_id", user.CompanyInstallationId.ToString()), new Claim("local_user_id", user.Id.ToString()), new Claim("hoppa_user_id", "11068")], "test")) } }
        };
    private sealed class Environment(string name) : IHostEnvironment {
        public string EnvironmentName { get; set; } = name;
        public string ApplicationName { get; set; } = "Test";
        public string ContentRootPath { get; set; } = "/tmp";
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
