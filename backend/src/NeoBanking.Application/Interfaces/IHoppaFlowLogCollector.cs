using System.Net.Http;

namespace NeoBanking.Application.Interfaces;

public sealed class HoppaExchangeLog
{
    public DateTimeOffset OccurredAt { get; init; } = DateTimeOffset.UtcNow;

    public HttpMethod Method { get; init; } = HttpMethod.Get;

    public string Endpoint { get; init; } = string.Empty;

    public string? QueryString { get; init; }

    public int? StatusCode { get; init; }

    public long DurationMs { get; init; }

    public bool Succeeded { get; init; }

    public string? FailureCode { get; init; }

    public string? FailureMessage { get; init; }

    public string? RequestJson { get; init; }

    public string? ResponseJson { get; init; }
}

public interface IHoppaFlowLogCollector
{
    bool HasHoppaExchanges { get; }

    IReadOnlyList<HoppaExchangeLog> HoppaExchanges { get; }

    void AddHoppaExchange(HoppaExchangeLog exchange);
}
