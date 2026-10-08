using System.Net.Http;
using System.Text.Json;
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
                TrustedReferralActorId = trustedReferralActorId,
                FailureCode = failureCode,
                FailureMessage = failureMessage
            },
            cancellationToken);
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
