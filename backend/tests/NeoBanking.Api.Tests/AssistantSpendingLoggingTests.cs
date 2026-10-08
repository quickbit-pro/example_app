using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Options;
using NeoBanking.Api.HoppaLogging;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Infrastructure.Hoppa;
using Xunit;
namespace NeoBanking.Api.Tests;
public sealed class AssistantSpendingLoggingTests
{
    [Theory]
    [InlineData(HttpStatusCode.OK)] [InlineData(HttpStatusCode.BadGateway)]
    public async Task SensitiveProxyResponseAndIdentityNeverEnterFlowCollector(HttpStatusCode status)
    {
        using var http = new HttpClient(new Handler(status)) { BaseAddress = new Uri("https://engine.invalid") };
        var collector = new HoppaFlowLogCollector();
        var client = new HoppaClient(http, Options.Create(new HoppaOptions { ApiKey = "synthetic-test-key" }), collector);
        var proxy = new ProxyHoppaRequestUseCase(client);
        await proxy.ExecuteAsync(new ProxyHoppaRequestCommand<object?> { Method = HttpMethod.Get,
            UpstreamPath = "/api/v2/transactions", Query = new Dictionary<string, string?> { ["userId"] = "17" },
            SuppressPayloadLogging = true }, default);
        Assert.Empty(collector.HoppaExchanges);
    }
    private sealed class Handler(HttpStatusCode status) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) =>
            Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent("{\"private\":\"raw merchant and account data\"}") });
    }
}
