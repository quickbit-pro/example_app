using System.Net.Http;

namespace NeoBanking.Application.UseCases.Hoppa;

public sealed class ProxyHoppaRequestCommand<TRequest>
{
    public HttpMethod Method { get; init; } = HttpMethod.Get;

    public string UpstreamPath { get; init; } = string.Empty;

    public IReadOnlyDictionary<string, string?> Query { get; init; } = new Dictionary<string, string?>();

    public TRequest? Request { get; init; }

    /// <summary>Server-derived authenticated admin identity; never copied from client input.</summary>
    public string? TrustedReferralActorId { get; init; }

    /// <summary>Server-only opt-out for sensitive analysis; never populated from a mobile DTO.</summary>
    public bool SuppressPayloadLogging { get; init; }

    public string FailureCode { get; init; } = "hoppa.request_failed";

    public string FailureMessage { get; init; } = "Hoppa request failed.";
}
