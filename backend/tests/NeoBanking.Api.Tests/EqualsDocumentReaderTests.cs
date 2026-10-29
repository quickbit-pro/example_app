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
    [InlineData("https://my.cardeo.pro/legal.pdf")]
    public async Task CustomerLegalHostsCanBeRead(string url)
    {
        var handler = new Handler(_ => new HttpResponseMessage(HttpStatusCode.OK) {
            Content = new StringContent("<main>Terms</main>", System.Text.Encoding.UTF8, "text/html")
        });
        var reader = new EqualsDocumentReader(new HttpClient(handler), new MemoryCache(new MemoryCacheOptions()));
        Assert.Equal(url, (await reader.ReadAsync(url, default)).SourceUrl);
    }

    private const string SongsTerms = "https://www.songswallet.com/termsandconditions";
    private const string WixMetadata = "https://siteassets.parastorage.com/pages/pages/thunderbolt?siteRevision=362&registryLibraries=1";
    private const string SongsEmbed = "https://www-songswallet-com.filesusr.com/html/e76d6e_4077f0d294bb44863774b7f6f73ec9fc.html";

    private static HttpResponseMessage Content(string body, string type = "text/html") => new(HttpStatusCode.OK)
    { Content = new StringContent(body, System.Text.Encoding.UTF8, type) };

    [Fact]
    public async Task SongsTermsResolveCurrentEmbedAndRetainConfiguredConsentUrl()
    {
        var handler = new Handler(request => {
            Assert.Null(request.Headers.Authorization);
            Assert.False(request.Headers.Contains("x-api-key"));
            return request.RequestUri!.AbsoluteUri switch {
                SongsTerms => Content($"<main>Terms and Conditions</main><link href=\"{WixMetadata}\" id=\"features_currentPage\">"),
                WixMetadata => Content(System.Text.Json.JsonSerializer.Serialize(new {
                    props = new { render = new { compProps = new { legal = new { url = SongsEmbed } } } }
                }), "application/json"),
                SongsEmbed => Content("<article><h1>Full legal terms</h1><p>First clause</p><p>Final clause</p></article>"),
                _ => throw new Exception("Unexpected request")
            };
        });
        var reader = new EqualsDocumentReader(new HttpClient(handler), new MemoryCache(new MemoryCacheOptions()));
        var document = await reader.ReadAsync(SongsTerms, default, "1");
        Assert.Equal(SongsTerms, document.SourceUrl);
        Assert.Equal("text/html", document.ContentType);
        Assert.Contains("Final clause", System.Text.Encoding.UTF8.GetString(document.Content));
        Assert.Equal(document, await reader.ReadAsync(SongsTerms, default, "1"));
        Assert.Equal(3, handler.Calls);
    }

    [Theory]
    [InlineData("<main>Terms and Conditions</main>")]
    [InlineData("<link id='features_page' href='https://127.0.0.1/private'>")]
    public async Task SongsTermsNeverTreatAnEmptyShellOrUnapprovedMetadataAsTheDocument(string shell)
    {
        var handler = new Handler(_ => Content(shell));
        var reader = new EqualsDocumentReader(new HttpClient(handler), new MemoryCache(new MemoryCacheOptions()));
        await Assert.ThrowsAsync<InvalidDataException>(() => reader.ReadAsync(SongsTerms, default));
        Assert.Equal(1, handler.Calls);
    }

    [Theory]
    [InlineData("https://127.0.0.1/private")]
    [InlineData("https://other-site.filesusr.com/html/e76d6e_4077f0d294bb44863774b7f6f73ec9fc.html")]
    [InlineData("https://www-songswallet-com.filesusr.com.attacker.test/html/e76d6e_4077f0d294bb44863774b7f6f73ec9fc.html")]
    public async Task SongsTermsCannotFetchAnUnapprovedEmbed(string url)
    {
        var handler = new Handler(request => request.RequestUri!.AbsoluteUri == SongsTerms
            ? Content($"<link id='features_page' href='{WixMetadata}'>")
            : Content(System.Text.Json.JsonSerializer.Serialize(new {
                props = new { render = new { compProps = new { legal = new { url } } } }
            }), "application/json"));
        var reader = new EqualsDocumentReader(new HttpClient(handler), new MemoryCache(new MemoryCacheOptions()));
        await Assert.ThrowsAsync<InvalidDataException>(() => reader.ReadAsync(SongsTerms, default));
        Assert.Equal(2, handler.Calls);
    }

    [Fact]
    public async Task SongsMetadataRedirectCannotReachAnotherHost()
    {
        var handler = new Handler(request => request.RequestUri!.AbsoluteUri == SongsTerms
            ? Content($"<link id='features_page' href='{WixMetadata}'>")
            : new HttpResponseMessage(HttpStatusCode.Redirect) {
                Headers = { Location = new Uri("https://127.0.0.1/private") }
            });
        var reader = new EqualsDocumentReader(new HttpClient(handler), new MemoryCache(new MemoryCacheOptions()));
        await Assert.ThrowsAsync<InvalidDataException>(() => reader.ReadAsync(SongsTerms, default));
        Assert.Equal(2, handler.Calls);
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
