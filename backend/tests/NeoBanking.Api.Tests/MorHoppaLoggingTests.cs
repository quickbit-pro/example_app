using System.Net;
using System.Reflection;
using NeoBanking.Api.HoppaLogging;
using System.Text.Json;
using Microsoft.Extensions.Options;
using NeoBanking.Application.Interfaces;
using NeoBanking.Infrastructure.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MorHoppaLoggingTests
{
    [Theory]
    [InlineData("/api/v2/mor/public/companies")]
    [InlineData("/api/v2/cards/42/widget")]
    public async Task MorCredentialsAndWidgetUrlsAreRedactedFromLogsButPreservedOnWire(string path)
    {
        var handler = new Handler(); var collector = new Collector();
        var http = new HttpClient(handler) { BaseAddress = new Uri("https://hoppa.example.test") };
        var client = new HoppaClient(http, Options.Create(new HoppaOptions { ApiKey = "server-key" }), collector);
        var result = await client.SendAsync<object, JsonElement>(new HoppaRequest<object> {
            Method = HttpMethod.Post, Path = path,
            Body = new { AdminPassword = "private-password", UboInformation = new { UboIdNumber = "private-id", UboDob = "1990-01-01" } },
            FailureCode = "test", FailureMessage = "test"
        }, default);
        Assert.True(result.IsSuccess);
        Assert.Equal("https://widget.example.test/?secret=private-widget", result.Value.GetProperty("widgetUrl").GetString());
        Assert.Equal("private-token", result.Value.GetProperty("widgetToken").GetString());
        Assert.Contains("private-password", handler.Body);
        var log = Assert.Single(collector.HoppaExchanges);
        Assert.DoesNotContain("private-password", log.RequestJson);
        Assert.DoesNotContain("private-id", log.RequestJson);
        Assert.DoesNotContain("1990-01-01", log.RequestJson);
        Assert.DoesNotContain("private-widget", log.ResponseJson);
        Assert.DoesNotContain("private-token", log.ResponseJson);
        Assert.Contains("[REDACTED]", log.RequestJson);
    }
    [Fact]
    public void AppFlowLogsAlsoRedactRevealAndProvisioningSecrets()
    {
        var normalize = typeof(HoppaFlowLoggingMiddleware).GetMethod("NormalizeBody", BindingFlags.NonPublic | BindingFlags.Static)!;
        var body = JsonSerializer.Serialize(new { currentPassword = "private-current", adminPassword = "private-admin", code = "private-code", widgetUrl = "private-widget", widgetToken = "private-token", uboInformation = new { uboIdNumber = "private-id" } });
        var result = (string)normalize.Invoke(null, [body, true])!;
        Assert.DoesNotContain("private-", result);
        Assert.Contains("REDACTED", result);
        var malformed = (string)normalize.Invoke(null, ["{ currentPassword: private-secret", true])!;
        Assert.DoesNotContain("private-secret", malformed);
    }

    [Theory]
    [InlineData("POST", "/api/v2/mor/public/cards/batch", true)]
    [InlineData("GET", "/api/v2/mor/public/cards", false)]
    [InlineData("POST", "/api/v2/transfers/crypto-to-quantum-transfer", false)]
    public async Task ProxyKeyReachesOnlyMorPostRequests(string method, string path, bool expected)
    {
        var handler = new Handler();
        var client = new HoppaClient(new HttpClient(handler) { BaseAddress = new Uri("https://hoppa.example.test") },
            Options.Create(new HoppaOptions { ApiKey = "server-key" }), new Collector());
        var proxy = new NeoBanking.Application.UseCases.Hoppa.ProxyHoppaRequestUseCase(client);
        await proxy.ExecuteAsync(new NeoBanking.Application.UseCases.Hoppa.ProxyHoppaRequestCommand<object>
        { Method = new HttpMethod(method), UpstreamPath = path, Request = new {}, IdempotencyKey = "test-operation-001",
          FailureCode = "test", FailureMessage = "test" }, default);
        Assert.Equal(expected ? "test-operation-001" : null, handler.Key);
    }

    private sealed class Handler : HttpMessageHandler
    {
        public string? Body { get; private set; }
        public string? Key { get; private set; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            Body = request.Content is null ? null : await request.Content.ReadAsStringAsync(ct);
            Key = request.Headers.TryGetValues("Idempotency-Key", out var keys) ? Assert.Single(keys) : null;
            Assert.Equal("server-key", Assert.Single(request.Headers.GetValues("x-api-key")));
            return new(HttpStatusCode.OK) { Content = new StringContent("{\"widgetUrl\":\"https://widget.example.test/?secret=private-widget\",\"widgetToken\":\"private-token\",\"success\":true}") };
        }
    }
    private sealed class Collector : IHoppaFlowLogCollector
    {
        private readonly List<HoppaExchangeLog> _logs = [];
        public bool HasHoppaExchanges => _logs.Count > 0;
        public IReadOnlyList<HoppaExchangeLog> HoppaExchanges => _logs;
        public void AddHoppaExchange(HoppaExchangeLog exchange) => _logs.Add(exchange);
    }
}
