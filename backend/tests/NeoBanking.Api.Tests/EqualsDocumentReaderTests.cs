using Xunit;
using System.Net;
using Microsoft.Extensions.Caching.Memory;
using NeoBanking.Api.Auth;

namespace NeoBanking.Api.Tests;

public sealed class EqualsDocumentReaderTests
{
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        { Calls++; return Task.FromResult(respond(request)); }
    }

    [Theory]
    [InlineData("https://localhost/secret")]
    [InlineData("http://equalsmoney.com/privacy")]
    [InlineData("https://equalsmoney.com.attacker.test/privacy")]
    [InlineData("https://user:password@equalsmoney.com/privacy")]
    public async Task UnapprovedAddressesAreNotFetched(string url)
    {
        var handler = new Handler(_ => throw new Exception("Must not fetch"));
        var reader = new EqualsDocumentReader(new HttpClient(handler), new MemoryCache(new MemoryCacheOptions()));
        await Assert.ThrowsAsync<InvalidDataException>(() => reader.ReadAsync(url, default));
        Assert.Equal(0, handler.Calls);
    }

    [Theory]
    [InlineData("https://www.songswallet.com/termsandconditions")]
    [InlineData("https://my.cardeo.pro/legal.pdf")]
    public async Task CustomerLegalHostsCanBeRead(string url)
    {
        var handler = new Handler(_ => new HttpResponseMessage(HttpStatusCode.OK) {
            Content = new StringContent("<main>Terms</main>", System.Text.Encoding.UTF8, "text/html")
        });
        var reader = new EqualsDocumentReader(new HttpClient(handler), new MemoryCache(new MemoryCacheOptions()));
        Assert.Equal(url, (await reader.ReadAsync(url, default)).SourceUrl);
    }

    [Fact]
    public async Task RedirectCannotReachPrivateAddress()
    {
        var handler = new Handler(_ => new HttpResponseMessage(HttpStatusCode.Redirect) {
            Headers = { Location = new Uri("https://127.0.0.1/private") }
        });
        var reader = new EqualsDocumentReader(new HttpClient(handler), new MemoryCache(new MemoryCacheOptions()));
        await Assert.ThrowsAsync<InvalidDataException>(() => reader.ReadAsync("https://equalsmoney.com/privacy", default));
        Assert.Equal(1, handler.Calls);
    }

    [Fact]
    public async Task FullPdfIsReturnedAndCachedWithoutForwardingCredentials()
    {
        var handler = new Handler(request => {
            Assert.Null(request.Headers.Authorization);
            Assert.False(request.Headers.Contains("x-api-key"));
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("%PDF-complete document", System.Text.Encoding.UTF8, "application/pdf") };
        });
        var reader = new EqualsDocumentReader(new HttpClient(handler), new MemoryCache(new MemoryCacheOptions()));
        var first = await reader.ReadAsync("https://docs.hoppa.global/terms.pdf", default);
        var second = await reader.ReadAsync(first.SourceUrl, default);
        Assert.Equal("%PDF-complete document", System.Text.Encoding.UTF8.GetString(second.Content));
        Assert.Equal(1, handler.Calls);
    }
}
