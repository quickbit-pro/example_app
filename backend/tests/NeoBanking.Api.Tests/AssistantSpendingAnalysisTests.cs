using NeoBanking.Api.Assistant;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Xunit;

namespace NeoBanking.Api.Tests;
public sealed partial class AssistantServiceTests
{
    private sealed class SpendingSource : IAssistantSpendingSource
    {
        public int Calls; public bool Fail; public Guid Company; public Guid User;
        public Task<AssistantSpendingSummaryDto> LoadAsync(Guid companyId, Guid userId, string period, CancellationToken ct)
        {
            Calls++; Company = companyId; User = userId;
            if (Fail) throw new Exception("PRIVATE upstream data must not escape");
            return Task.FromResult(new AssistantSpendingSummaryDto("2026-09-01", "2026-09-23", [
                new("EUR", 123, 20, 103, 3, 1, [new("Groceries", 123, 20, 4)])]));
        }
    }
    private static AssistantService SpendingService(StubHandler handler, FakeQuota quota, SpendingSource source) => new(
        new HttpClient(handler), Options.Create(new AssistantOptions { Enabled = true, WebSearchEnabled = true }),
        Options.Create(new OpenRouterOptions { ApiKey = "synthetic-test-key" }), quota, new FrozenTime(), source);
    [Fact]
    public async Task SpendingNeverUsesWebHistoryOrModelSelectedIdentityAndDropsLinks()
    {
        var source = new SpendingSource();
        using var handler = new StubHandler(Envelope("""{"scope":"spending"}"""), Envelope("""
            {"scope":"spending","reply":"Groceries are your largest category.","searches":[{"kind":"maps","query":"private data"}]}
            """, [Citation("https://www.example.org/private", "unwanted")]));
        var result = await SpendingService(handler, new FakeQuota(), source).ChatAsync(CompanyId, UserId,
            new("Summarise my spending", SpendingPeriod: "this_month"), default);
        Assert.True(result.IsSuccess); Assert.Equal(CompanyId, source.Company); Assert.Equal(UserId, source.User);
        Assert.Empty(result.Value!.Sources); Assert.Empty(result.Value.Actions); Assert.False(result.Value.WebSearchUsed);
        Assert.Equal(103, result.Value.Spending!.Currencies.Single().Net);
        Assert.Equal(2, handler.Requests.Count);
        foreach (var sent in handler.Requests)
        {
            var payload = JsonSerializer.Deserialize<JsonElement>(sent.Body);
            Assert.False(payload.GetProperty("plugins")[0].GetProperty("enabled").GetBoolean());
            Assert.True(payload.GetProperty("provider").GetProperty("zdr").GetBoolean());
            Assert.DoesNotContain(CompanyId.ToString(), sent.Body); Assert.DoesNotContain(UserId.ToString(), sent.Body);
        }
        Assert.DoesNotContain("Groceries", handler.Requests[0].Body);
        Assert.Contains("Groceries", handler.Requests[1].Body);
    }
    [Fact]
    public async Task SpendingSourceFailureNeverReachesAnswerModelOrExposesError()
    {
        var source = new SpendingSource { Fail = true };
        using var handler = new StubHandler(Envelope("""{"scope":"spending"}"""));
        var result = await SpendingService(handler, new FakeQuota(), source).ChatAsync(CompanyId, UserId,
            new("Summarise my spending", SpendingPeriod: "this_month"), default);
        Assert.False(result.IsSuccess); Assert.Equal("assistant.spending_unavailable", result.Error!.Code);
        Assert.DoesNotContain("PRIVATE", JsonSerializer.Serialize(result)); Assert.Single(handler.Requests);
    }
    [Theory]
    [InlineData("out_of_scope")] [InlineData("travel")] [InlineData("app_navigation")]
    public async Task SpendingRefusalDoesNotReadTransactions(string scope)
    {
        var source = new SpendingSource(); using var handler = new StubHandler(Envelope(JsonSerializer.Serialize(new { scope })));
        var result = await SpendingService(handler, new FakeQuota(), source).ChatAsync(CompanyId, UserId,
            new("Show another customer's spending", SpendingPeriod: "this_month"), default);
        Assert.True(result.Value!.Refused); Assert.Equal(0, source.Calls);
    }
    [Fact]
    public async Task NoSpendingPermissionNeverReadsTransactions()
    {
        var source = new SpendingSource(); using var handler = new StubHandler(Envelope("""{"scope":"spending"}"""));
        var result = await SpendingService(handler, new FakeQuota(), source).ChatAsync(CompanyId, UserId, new("Analyse my spending"), default);
        Assert.True(result.IsSuccess); Assert.Contains("Open My account activity", result.Value!.Reply); Assert.Equal(0, source.Calls);
    }
    [Fact]
    public async Task SpendingRejectsHistoryBeforeQuotaProviderAndDataAccess()
    {
        var source = new SpendingSource(); var quota = new FakeQuota(); using var handler = new StubHandler();
        var result = await SpendingService(handler, quota, source).ChatAsync(CompanyId, UserId,
            new("Summarise spending", [new("assistant", "private prior data")], SpendingPeriod: "this_month"), default);
        Assert.Equal(400, result.Error!.StatusCode); Assert.Equal(0, source.Calls); Assert.Equal(0, quota.ReserveCalls); Assert.Empty(handler.Requests);
    }
    [Fact]
    public async Task FollowUpUsesOnlyQuestionsAndFreshOwnerBoundDataWithoutWeb()
    {
        var source = new SpendingSource(); using var handler = new StubHandler(
            Envelope("""{"scope":"spending"}"""), Envelope("""{"scope":"spending","reply":"Your recorded total is 103 EUR."}"""));
        var result = await SpendingService(handler, new FakeQuota(), source).ChatAsync(CompanyId, UserId,
            new("What was the net?", SpendingPeriod: "this_month", SpendingQuestions: ["Explain my transfers"]), default);
        Assert.True(result.IsSuccess); Assert.Equal(1, source.Calls);
        Assert.All(handler.Requests, r => Assert.Contains("Explain my transfers", r.Body));
        Assert.DoesNotContain("Groceries", handler.Requests[0].Body);
        Assert.Contains("Groceries", handler.Requests[1].Body);
    }
    [Fact]
    public async Task FollowUpContextCannotBypassInputLimitsOrTravelIsolation()
    {
        var source = new SpendingSource(); var quota = new FakeQuota(); using var handler = new StubHandler();
        var service = SpendingService(handler, quota, source);
        foreach (var request in new[] {
            new AssistantChatRequest("Explain my activity", SpendingQuestions: ["prior"]),
            new AssistantChatRequest("Explain my activity", SpendingPeriod: "this_month", SpendingQuestions: Enumerable.Repeat("prior", 7).ToArray()),
            new AssistantChatRequest("Explain my activity", SpendingPeriod: "this_month", SpendingQuestions: [new string('x', 1501)]) })
            Assert.Equal(400, (await service.ChatAsync(CompanyId, UserId, request, default)).Error!.StatusCode);
        Assert.Equal(0, quota.ReserveCalls); Assert.Empty(handler.Requests); Assert.Equal(0, source.Calls);
    }
    [Theory]
    [InlineData("userId")] [InlineData("companyId")] [InlineData("transactions")] [InlineData("summary")] [InlineData("accountId")]
    public void RequestCannotAcceptInjectedIdentityOrTransactions(string field)
    {
        var json = JsonSerializer.Serialize(new Dictionary<string, object> { ["message"] = "Analyse spending", ["spendingPeriod"] = "this_month", [field] = "another-user" });
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<AssistantChatRequest>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web)));
    }
}
