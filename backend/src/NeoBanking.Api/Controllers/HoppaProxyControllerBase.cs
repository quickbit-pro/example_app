using System.Net.Http;
using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

public abstract class HoppaProxyControllerBase : ApiControllerBase
{
    private readonly IProxyHoppaRequestUseCase _proxyHoppa;

    protected HoppaProxyControllerBase(IProxyHoppaRequestUseCase proxyHoppa)
    {
        _proxyHoppa = proxyHoppa;
    }

    protected Task<ApplicationResult<JsonElement?>> SendHoppaAsync<TRequest>(
        HttpMethod method,
        string upstreamPath,
        TRequest? request,
        string failureCode,
        string failureMessage,
        CancellationToken cancellationToken,
        IReadOnlyDictionary<string, string?>? query = null,
        string? trustedReferralActorId = null)
    {
        return _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<TRequest>
            {
                Method = method,
                UpstreamPath = upstreamPath,
                Query = query ?? new Dictionary<string, string?>(),
                Request = request,
                IdempotencyKey = MorIdempotencyKey(method, upstreamPath),
                TrustedReferralActorId = trustedReferralActorId,
                FailureCode = failureCode,
                FailureMessage = failureMessage
            },
            cancellationToken);
    }

    private string? MorIdempotencyKey(HttpMethod method, string path)
    {
        if (method != HttpMethod.Post || !path.StartsWith("/api/v2/mor/public/", StringComparison.Ordinal)
            || HttpContext is null || !Request.Headers.TryGetValue("Idempotency-Key", out var keys)) return null;
        if (keys.Count != 1 || keys[0] is not { Length: >= 8 and <= 200 } key || key.Any(c => c < 33 || c > 126))
            return "!"; // Upstream rejects invalid keys before any operation.
        // Different signed-in actors sharing an installation cannot replay each other's response.
        TryGetLocalUserId(out var actor);
        return "mor-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes($"{actor}:{key}")));
    }

    protected Task<ApplicationResult<JsonElement?>> SendAdminHoppaAsync<TRequest>(
        HttpMethod method,
        string adminRelativePath,
        TRequest? request,
        string failureCode,
        string failureMessage,
        CancellationToken cancellationToken,
        IReadOnlyDictionary<string, string?>? query = null)
    {
        return SendHoppaAsync(
            method,
            $"/api/v2/{adminRelativePath}",
            request,
            failureCode,
            failureMessage,
            cancellationToken,
            query);
    }
}
