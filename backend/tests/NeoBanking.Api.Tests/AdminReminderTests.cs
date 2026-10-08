using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Admin;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Company;
using NeoBanking.Application.Email;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Email;
using NeoBanking.Infrastructure.Persistence;
using Xunit;
using static NeoBanking.Api.Tests.AdminKpiServiceTests;

namespace NeoBanking.Api.Tests;

public sealed class AdminReminderTests
{
    [Fact]
    public async Task OnlyVerifiedUnlockedRealCustomersInTheStageGetOneReminderPerCooldown()
    {
        await using var db = Database();
        var company = await CreateCompany(db);
        var ready = await Customer(db, company, "ready", Now.AddDays(-9), approved: true);
        var tester = await Customer(db, company, "tester", Now.AddDays(-9), approved: true);
        var unconfirmed = await Customer(db, company, "unconfirmed", Now.AddDays(-9), approved: true);
        var locked = await Customer(db, company, "locked", Now.AddDays(-9), approved: true);
        var remindedEarlier = await Customer(db, company, "reminded", Now.AddDays(-9), approved: true);
        await Customer(db, company, "other-stage", Now.AddDays(-9), approved: false);
        db.AdminCustomerFlags.Add(new AdminCustomerFlag { CompanyInstallationId = company, UserId = tester, IsTestAccount = true });
        (await db.Users.SingleAsync(user => user.Id == unconfirmed)).EmailVerifiedAt = null;
        (await db.Users.SingleAsync(user => user.Id == locked)).LockedAt = Now.AddDays(-1);
        db.EmailMessages.Add(new EmailMessage
        {
            CompanyInstallationId = company, UserId = remindedEarlier, TemplateKey = EmailTemplateCatalog.ReminderAddMoney, ToEmail = "reminded@example.test",
            Subject = "s", HtmlBody = "h", TextBody = "t", Status = "sent", CreatedAt = Now.AddDays(-2), UpdatedAt = Now.AddDays(-2)
        });
        await db.SaveChangesAsync();
        var controller = Controller(db, company);

        var preview = Json(Assert.IsType<OkObjectResult>(await controller.Preview(new(AdminCustomerStages.Approved, null, 0), default)));
        Assert.Equal(1, preview.GetProperty("recipients").GetInt32());
        Assert.Equal(EmailTemplateCatalog.ReminderAddMoney, preview.GetProperty("templateKey").GetString());
        Assert.Equal("Your Example account is ready", preview.GetProperty("subject").GetString());
        var skipped = preview.GetProperty("skipped");
        Assert.Equal((1, 1, 1, 1), (skipped.GetProperty("recentlyReminded").GetInt32(), skipped.GetProperty("testAccounts").GetInt32(),
            skipped.GetProperty("emailNotConfirmed").GetInt32(), skipped.GetProperty("locked").GetInt32()));

        Assert.IsType<ConflictObjectResult>(await controller.Send(new(AdminCustomerStages.Approved, null, 2), default));
        var sent = Json(Assert.IsType<OkObjectResult>(await controller.Send(new(AdminCustomerStages.Approved, null, 1), default)));
        Assert.Equal(1, sent.GetProperty("queued").GetInt32());
        var message = await db.EmailMessages.SingleAsync(item => item.UserId == ready);
        Assert.Contains("https://app.example.test/", message.HtmlBody);
        Assert.Contains("lifecycle_reminder", message.MetadataJson);
        Assert.Equal("customers.reminder_sent", (await db.AuditLogEntries.SingleAsync()).Action);

        var again = Json(Assert.IsType<OkObjectResult>(await controller.Preview(new(AdminCustomerStages.Approved, null, 0), default)));
        Assert.Equal(0, again.GetProperty("recipients").GetInt32());
        Assert.IsType<BadRequestObjectResult>(await controller.Preview(new(AdminCustomerStages.Active, null, 0), default));
    }

    private static AdminCustomerRemindersController Controller(NeoBankingDbContext db, Guid company)
    {
        var context = new StaticCompanyContext();
        var outbox = new EmailOutbox(db, new EmailTemplateStore(db), context, NullLogger<EmailOutbox>.Instance);
        var service = new AdminReminderService(db, new EmailTemplateStore(db), outbox,
            Options.Create(new AdminRemindersOptions { AppUrl = "https://app.example.test/" }), new FixedClock(Now));
        return new AdminCustomerRemindersController(db, service)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity([new Claim("company_installation_id", company.ToString())], "test"))
                }
            }
        };
    }

    private static JsonElement Json(ObjectResult result) =>
        JsonSerializer.SerializeToElement(result.Value, new JsonSerializerOptions(JsonSerializerDefaults.Web));

    private sealed class StaticCompanyContext : ICompanyContextAccessor
    {
        public ICompanyContext Current { get; private set; } =
            new CompanyContext("example", "Example Ltd", "Example", new BrandingContext(null, "#0F172A", "support@example.test", null, null));

        public void SetCurrent(ICompanyContext context) => Current = context;

        public void Clear() { }
    }
}
