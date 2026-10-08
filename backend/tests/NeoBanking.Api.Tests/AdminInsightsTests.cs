using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Admin;
using NeoBanking.Api.Assistant;
using NeoBanking.Infrastructure.Admin;
using Xunit;
using static NeoBanking.Api.Tests.AdminKpiServiceTests;

namespace NeoBanking.Api.Tests;

public sealed class AdminInsightsTests
{
    [Fact]
    public async Task ModelSeesOnlyAggregates_AndItsAnswerIsValidatedCachedAndLinkedToAdminPagesOnly()
    {
        await using var db = Database();
        var company = await CreateCompany(db);
        var user = await Customer(db, company, "Hubert Wistak", Now.AddDays(-5), approved: true, cards: 1);
        Ledger(db, company, user, "p1", AdminTransactionKinds.CardPurchase, 12m, Now.AddDays(-1), merchant: "OPENAI");
        await db.SaveChangesAsync();
        var handler = new ProviderHandler(Envelope("""
            {"headline":"Spend is up and declines are low.","insights":[
              {"title":"Card spend $12.00","detail":"One purchase at OPENAI.","tone":"good","area":"cards","link":"card_spend"},
              {"title":"Bad tone is dropped","detail":"x","tone":"great","area":"cards","link":"none"},
              {"title":"Unknown link becomes none","detail":"Check it.","tone":"neutral","area":"operations","link":"https://evil.example"}]}
            """));
        var service = Service(db, handler, new MemoryCache(new MemoryCacheOptions()), apiKey: "test-key");

        var first = await service.GetAsync(company, 30, refresh: false, default);
        var second = await service.GetAsync(company, 30, refresh: false, default);

        Assert.Same(first, second);
        Assert.Equal(1, handler.Calls);
        Assert.Equal("ai", first.Source);
        Assert.Equal("deepseek/deepseek-v4.1-flash", first.Model);
        Assert.Equal(2, first.Items.Count);
        Assert.Equal("/money?kind=card_purchase&status=completed", first.Items[0].Link);
        Assert.Null(first.Items[1].Link);

        var sent = handler.LastBody!;
        Assert.Contains("deepseek/deepseek-v4.1-flash", sent);
        Assert.Contains("\"zdr\":true", sent);
        Assert.Contains("OPENAI", sent);
        Assert.DoesNotContain("Hubert", sent);
        Assert.DoesNotContain("example.test", sent);
        Assert.DoesNotContain(user.ToString(), sent);
    }

    [Fact]
    public async Task WithoutKeyOrWhenTheProviderFails_TheSameShapeComesFromRules()
    {
        await using var db = Database();
        var company = await CreateCompany(db);
        await Customer(db, company, "approved", Now.AddDays(-5), approved: true);
        await db.SaveChangesAsync();

        var unconfigured = await Service(db, new ProviderHandler("{}"), new MemoryCache(new MemoryCacheOptions()), apiKey: "")
            .GetAsync(company, 30, refresh: false, default);
        Assert.Equal("rules", unconfigured.Source);
        Assert.Contains("not configured", unconfigured.Notice);
        Assert.Contains(unconfigured.Items, item => item.Link == "/customers?stage=approved" && item.Title.StartsWith("1 approved", StringComparison.Ordinal));

        var failing = await Service(db, new ProviderHandler("{}", HttpStatusCode.BadGateway), new MemoryCache(new MemoryCacheOptions()), apiKey: "key")
            .GetAsync(company, 30, refresh: false, default);
        Assert.Equal("rules", failing.Source);
        Assert.Contains("unavailable", failing.Notice);
    }

    [Fact]
    public void ParserRejectsIncompleteOrOffSchemaAnswers()
    {
        var now = Now;
        Assert.Throws<JsonException>(() => AdminInsightsService.Parse(Doc(Envelope("""{"insights":[]}""")), 30, now, "m"));
        Assert.Throws<JsonException>(() => AdminInsightsService.Parse(Doc(Envelope("""{"headline":"h","insights":[{"title":"t","detail":"d","tone":"bad","area":"nowhere","link":"none"}]}""")), 30, now, "m"));
        Assert.Throws<JsonException>(() => AdminInsightsService.Parse(Doc("""{"choices":[{"finish_reason":"length","message":{"content":"{}"}}]}"""), 30, now, "m"));
        var parsed = AdminInsightsService.Parse(Doc(Envelope("""{"headline":"h\u0007","insights":[{"title":"t","detail":"d","tone":"bad","area":"money","link":"deposits"}]}""")), 30, now, "m");
        Assert.Equal("h", parsed.Headline);
        Assert.Equal("/money?kind=deposit&status=completed", parsed.Items.Single().Link);
    }

    private static AdminInsightsService Service(NeoBanking.Infrastructure.Persistence.NeoBankingDbContext db, ProviderHandler handler, IMemoryCache cache, string apiKey) =>
        new(new HttpClient(handler), new AdminKpiService(db, new FixedClock(Now)), cache,
            Options.Create(new AdminInsightsOptions()), Options.Create(new OpenRouterOptions { ApiKey = apiKey }),
            new FixedClock(Now), NullLogger<AdminInsightsService>.Instance);

    private static string Envelope(string content) => JsonSerializer.Serialize(new
    {
        choices = new[] { new { finish_reason = "stop", message = new { content } } }
    });

    private static JsonElement Doc(string json) => JsonDocument.Parse(json).RootElement.Clone();

    private sealed class ProviderHandler(string body, HttpStatusCode status = HttpStatusCode.OK) : HttpMessageHandler
    {
        public int Calls;
        public string? LastBody;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            LastBody = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
            return new HttpResponseMessage(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
        }
    }
}
