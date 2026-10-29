using Microsoft.Extensions.Caching.Memory;
using System.Text;

namespace NeoBanking.Api.Auth;

public sealed record EqualsDocumentContent(string SourceUrl, string ContentType, byte[] Content);

/// <summary>Public legal documents only. Never forward customer credentials to a document host.</summary>
public sealed class EqualsDocumentReader(HttpClient client, IMemoryCache cache)
{
    private const int MaximumBytes = 12 * 1024 * 1024;
    public static bool IsAllowed(Uri uri) => uri.Scheme == "https" && uri.IsDefaultPort &&
        string.IsNullOrEmpty(uri.UserInfo) && uri.Host is
            "docs.hoppa.global" or "songswallet.com" or "www.songswallet.com" or
            "cardeo.pro" or "www.cardeo.pro" or "my.cardeo.pro" or "equalsmoney.com" or "www.equalsmoney.com" or
            "assets.website-files.com" or "cdn.prod.website-files.com";

    public async Task<EqualsDocumentContent> ReadAsync(string sourceUrl, CancellationToken ct, string? version = null)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));
        ct = timeout.Token;
        if (!Uri.TryCreate(sourceUrl, UriKind.Absolute, out var uri) || !IsAllowed(uri))
            throw new InvalidDataException("Unsupported document address.");
        var cacheKey = $"equals-document:{sourceUrl}:{version}";
        if (cache.TryGetValue<EqualsDocumentContent>(cacheKey, out var cached)) return cached!;
        var result = await FetchAsync(uri, IsAllowed, ["text/html", "application/pdf"], ct);
        if (result.ContentType == "text/html" && SongsWalletTermsDocument.IsTermsPage(uri))
        {
            // Wix publishes only its page shell in the initial HTML. Resolve
            // the current legal embed from that page's public metadata.
            var metadataUrl = SongsWalletTermsDocument.MetadataUrl(Encoding.UTF8.GetString(result.Content));
            var metadata = await FetchAsync(metadataUrl, SongsWalletTermsDocument.IsMetadataUrl,
                ["application/json"], ct);
            var documentUrl = SongsWalletTermsDocument.DocumentUrl(metadata.Content);
            result = await FetchAsync(documentUrl, SongsWalletTermsDocument.IsDocumentUrl, ["text/html"], ct);
        }
        result = result with { SourceUrl = sourceUrl };
        cache.Set(cacheKey, result, TimeSpan.FromMinutes(5));
        return result;
    }

    private async Task<EqualsDocumentContent> FetchAsync(Uri uri, Func<Uri, bool> allowed,
        string[] contentTypes, CancellationToken ct)
    {
        if (!allowed(uri)) throw new InvalidDataException("Unsupported document address.");
        for (var redirects = 0; redirects <= 3; redirects++)
        {
            using var response = await client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, ct);
            if ((int)response.StatusCode is >= 300 and < 400)
            {
                if (response.Headers.Location is not { } location)
                    throw new InvalidDataException("Missing redirect address.");
                uri = new Uri(uri, location);
                if (!allowed(uri)) throw new InvalidDataException("Unsupported redirect address.");
                continue;
            }
            response.EnsureSuccessStatusCode();
            var type = response.Content.Headers.ContentType?.MediaType;
            if (!contentTypes.Contains(type ?? "") ||
                response.Content.Headers.ContentLength > MaximumBytes)
                throw new InvalidDataException("Unsupported document content.");
            using var content = new MemoryStream();
            await using var stream = await response.Content.ReadAsStreamAsync(ct);
            var buffer = new byte[8192];
            int count;
            while ((count = await stream.ReadAsync(buffer, ct)) > 0)
            {
                if (content.Length + count > MaximumBytes) throw new InvalidDataException("Document too large.");
                content.Write(buffer, 0, count);
            }
            var bytes = content.ToArray();
            if (bytes.Length == 0 || (type == "application/pdf" && !bytes.AsSpan().StartsWith("%PDF-"u8)))
                throw new InvalidDataException("Empty or invalid document.");
            return new EqualsDocumentContent(uri.AbsoluteUri, type!, bytes);
        }
        throw new InvalidDataException("Too many document redirects.");
    }
}
