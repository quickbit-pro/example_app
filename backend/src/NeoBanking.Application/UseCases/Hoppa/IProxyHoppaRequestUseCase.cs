using System.Text.Json;
using NeoBanking.Application.Common;

namespace NeoBanking.Application.UseCases.Hoppa;

public interface IProxyHoppaRequestUseCase
{
    Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(
        ProxyHoppaRequestCommand<TRequest> command,
        CancellationToken cancellationToken);
}
