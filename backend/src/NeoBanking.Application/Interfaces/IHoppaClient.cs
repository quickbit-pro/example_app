using System.Net.Http;
using System.Text.Json;
using NeoBanking.Application.Common;

namespace NeoBanking.Application.Interfaces;

public sealed class HoppaRequest<TRequest>
{
    public HttpMethod Method { get; init; } = HttpMethod.Get;

    public string Path { get; init; } = string.Empty;

    public IReadOnlyDictionary<string, string?> Query { get; init; } = new Dictionary<string, string?>();

    public TRequest? Body { get; init; }

    /// <summary>Server-derived authenticated admin identity; never copied from client input.</summary>
    public string? TrustedReferralActorId { get; init; }

    /// <summary>Server-only opt-out for sensitive analysis; never populated from a mobile DTO.</summary>
    public bool SuppressPayloadLogging { get; init; }

    public string FailureCode { get; init; } = "hoppa.request_failed";

    public string FailureMessage { get; init; } = "Hoppa request failed.";
}

public sealed class HoppaDownload(HttpResponseMessage response, Stream content) : IDisposable
{
    public Stream Content { get; } = content;
    public void Dispose() { Content.Dispose(); response.Dispose(); }
}

public interface IHoppaClient
{
    Task<ApplicationResult<HoppaDownload>> DownloadAsync(HoppaRequest<object?> request,CancellationToken cancellationToken) =>
        Task.FromResult(ApplicationResult<HoppaDownload>.Failure(new("hoppa.download.unsupported","Downloads are unavailable.",501)));

    Task<ApplicationResult<TResponse>> SendAsync<TRequest, TResponse>(
        HoppaRequest<TRequest> request,
        CancellationToken cancellationToken);
}
