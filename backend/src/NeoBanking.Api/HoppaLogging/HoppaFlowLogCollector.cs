using NeoBanking.Application.Interfaces;

namespace NeoBanking.Api.HoppaLogging;

public sealed class HoppaFlowLogCollector : IHoppaFlowLogCollector
{
    private readonly List<HoppaExchangeLog> _hoppaExchanges = [];
    private readonly object _gate = new();

    public bool HasHoppaExchanges
    {
        get
        {
            lock (_gate)
            {
                return _hoppaExchanges.Count > 0;
            }
        }
    }

    public IReadOnlyList<HoppaExchangeLog> HoppaExchanges
    {
        get
        {
            lock (_gate)
            {
                return _hoppaExchanges.ToArray();
            }
        }
    }

    public void AddHoppaExchange(HoppaExchangeLog exchange)
    {
        lock (_gate)
        {
            _hoppaExchanges.Add(exchange);
        }
    }
}
