using Microsoft.Extensions.Caching.Memory;

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
        for (var redirects = 0; redirects <= 3; redirects++)
        {
            using var response = await client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, ct);
            if ((int)response.StatusCode is >= 300 and < 400)
            {
                if (response.Headers.Location is not { } location)
                    throw new InvalidDataException("Missing redirect address.");
                uri = new Uri(uri, location);
                if (!IsAllowed(uri)) throw new InvalidDataException("Unsupported redirect address.");
                continue;
            }
            response.EnsureSuccessStatusCode();
            var type = response.Content.Headers.ContentType?.MediaType;
            if (type is not ("text/html" or "application/pdf") ||
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
            var result = new EqualsDocumentContent(sourceUrl, type, bytes);
            cache.Set(cacheKey, result, TimeSpan.FromMinutes(5));
            return result;
        }
        throw new InvalidDataException("Too many document redirects.");
    }
}
