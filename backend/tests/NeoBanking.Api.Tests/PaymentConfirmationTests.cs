using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Controllers;
using NeoBanking.Api.HoppaLogging;
using NeoBanking.Application.Interfaces;
using NeoBanking.Infrastructure.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class PaymentConfirmationTests
{
    [Fact]
    public async Task DownloadUsesAuthenticatedUserAndStreamsOriginalPrivatePdf()
    {
        var handler = new Capture();
        var client = Client(handler);
        var controller = Controller(client, "236");
        controller.Request.QueryString = new QueryString("?userId=999&paymentId=another");
        var result = Assert.IsType<FileStreamResult>(await controller.Download(91191, default));
        Assert.Equal("https://provider.invalid/api/v2/transactions/91191/equals-money/payment-confirmation?userId=236", handler.Uri?.ToString());
        Assert.Equal("application/pdf", result.ContentType);
        Assert.Equal("equals-payment-confirmation-91191.pdf", result.FileDownloadName);
        Assert.Equal("no-store", controller.Response.Headers.CacheControl.ToString());
        using var reader = new StreamReader(result.FileStream);
        Assert.Equal("%PDF-test-provider-original", await reader.ReadToEndAsync());
    }

    [Theory]
    [InlineData(null)] [InlineData("")] [InlineData("0")] [InlineData("invalid")]
    public async Task MissingUserCannotDownload(string? userId)
    {
        var handler = new Capture();
        var result = Assert.IsType<ObjectResult>(await Controller(Client(handler), userId).Download(91191, default));
        Assert.Equal(401, result.StatusCode);
        Assert.Null(handler.Uri);
    }

    [Theory]
    [InlineData(400)] [InlineData(401)] [InlineData(403)] [InlineData(404)] [InlineData(502)]
    public async Task UpstreamFailureIsNotServedAsPdf(int status)
    {
        var handler = new Capture(status);
        var result = Assert.IsType<ObjectResult>(await Controller(Client(handler), "236").Download(91191, default));
        Assert.Equal(status, result.StatusCode);
    }

    [Fact]
    public async Task HtmlSuccessIsRejected()
    {
        var handler = new Capture(200, "text/html");
        var result = Assert.IsType<ObjectResult>(await Controller(Client(handler), "236").Download(91191, default));
        Assert.Equal(502, result.StatusCode);
    }

    [Theory]
    [InlineData("/api/v2/transactions/1/equals-money/payment-confirmation", null)]
    [InlineData("/api/v2/transactions/1/equals-money/payment-confirmation", "0")]
    [InlineData("/api/v2/transactions/1/equals-money/payment-confirmation?userId=999", "236")]
    [InlineData("/api/v2/transactions/../equals-money/payment-confirmation", "236")]
    [InlineData("/api/v2/transactions/0/equals-money/payment-confirmation", "236")]
    [InlineData("https://other.invalid/api/v2/transactions/1/equals-money/payment-confirmation", "236")]
    [InlineData("/api/v2/transactions/1", "236")]
    public async Task DownloadAllowlistRejectsUnscopedOrArbitraryPaths(string path, string? userId)
    {
        var handler = new Capture();
        var result = await Client(handler).DownloadAsync(new HoppaRequest<object?> {
            Path = path, Query = new Dictionary<string,string?> { ["userId"] = userId }
        }, default);
        Assert.False(result.IsSuccess);
        Assert.Null(handler.Uri);
    }

    private static MobileTransactionConfirmationsController Controller(IHoppaClient client, string? userId)
    {
        var claims = userId == null ? Array.Empty<Claim>() : new[] { new Claim("hoppa_user_id", userId) };
        return new(client) { ControllerContext = new() { HttpContext = new DefaultHttpContext {
            User = new ClaimsPrincipal(new ClaimsIdentity(claims, "test")) } } };
    }
    private static HoppaClient Client(Capture handler) => new(
        new HttpClient(handler) { BaseAddress = new Uri("https://provider.invalid") },
        Options.Create(new HoppaOptions { ApiKey = "test-only-key" }), new HoppaFlowLogCollector());
    private sealed class Capture(int status = 200, string contentType = "application/pdf") : HttpMessageHandler
    {
        public Uri? Uri { get; private set; }
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Uri = request.RequestUri;
            var content = new StringContent("%PDF-test-provider-original");
            content.Headers.ContentType = new MediaTypeHeaderValue(contentType);
            return Task.FromResult(new HttpResponseMessage((HttpStatusCode)status) { Content = content });
        }
    }
}
