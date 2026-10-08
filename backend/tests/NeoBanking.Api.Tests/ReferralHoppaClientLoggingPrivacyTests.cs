using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using NeoBanking.Api.HoppaLogging;
using NeoBanking.Application.Interfaces;
using NeoBanking.Infrastructure.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class ReferralHoppaClientLoggingPrivacyTests
{
    [Fact]
    public async Task ObservationPayloadReachesEngineWhileCollectorExcludesRawSignalsAndActorEnvelope()
    {
        var handler = new Capture();
        using var client = new HttpClient(handler) { BaseAddress = new Uri("https://engine.invalid") };
        var collector = new HoppaFlowLogCollector();
        var provider = new HoppaClient(client, Options.Create(new HoppaOptions { ApiKey = "private-api-key",
            ReferralAuditDelegation = new() { Enabled = true, InstallationId = "app", CompanyId = 1, Secret = new string('x', 40) } }), collector);
        var result = await provider.SendAsync<object, JsonElement>(new()
        {
            Method = HttpMethod.Post, Path = "/api/v2/referrals/signup-signals", TrustedReferralActorId = "admin:7",
            Body = new { ServerObservedIp = "private-ip", InstallationToken = "private-install", nested = new[] { new { invitation_token = "private-invite" } }, Source = "SIGNUP" }
        }, default);
        Assert.True(result.IsSuccess);
        Assert.Contains("private-ip", handler.Body!);
        Assert.Contains("private-install", handler.Body!);
        Assert.NotNull(handler.ActorEnvelope);
        var exchange = Assert.Single(collector.HoppaExchanges);
        Assert.Contains("SIGNUP", exchange.RequestJson!);
        Assert.DoesNotContain("private-", exchange.RequestJson!);
        Assert.DoesNotContain(handler.ActorEnvelope!, JsonSerializer.Serialize(exchange));
    }
    private sealed class Capture : HttpMessageHandler
    {
        public string? Body { get; private set; }
        public string? ActorEnvelope { get; private set; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Body = await request.Content!.ReadAsStringAsync(cancellationToken);
            ActorEnvelope = request.Headers.GetValues("X-Referral-Actor").Single();
            return new(HttpStatusCode.OK) { Content = new StringContent("{\"status\":\"RECORDED\"}", Encoding.UTF8, "application/json") };
        }
    }
}
