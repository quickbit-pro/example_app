using System.Net;
using System.Text.Json;
using NeoBanking.Application.Common;
using NeoBanking.Application.Interfaces;

namespace NeoBanking.Application.UseCases.Hoppa;

public sealed class ProxyHoppaRequestUseCase : IProxyHoppaRequestUseCase
{
    private readonly IHoppaClient _hoppaClient;

    public ProxyHoppaRequestUseCase(IHoppaClient hoppaClient)
    {
        _hoppaClient = hoppaClient;
    }

    public Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(
        ProxyHoppaRequestCommand<TRequest> command,
        CancellationToken cancellationToken)
    {
        var validationError = ValidatePath(command.UpstreamPath);
        if (validationError is not null)
        {
            return Task.FromResult(ApplicationResult<JsonElement?>.Failure(validationError));
        }

        return _hoppaClient.SendAsync<TRequest, JsonElement?>(
            new HoppaRequest<TRequest>
            {
                Method = command.Method,
                Path = command.UpstreamPath,
                Query = command.Query,
                Body = command.Request,
                TrustedReferralActorId = command.TrustedReferralActorId,
                SuppressPayloadLogging = command.SuppressPayloadLogging,
                FailureCode = command.FailureCode,
                FailureMessage = command.FailureMessage
            },
            cancellationToken);
    }

    private static ApplicationError? ValidatePath(string upstreamPath)
    {
        if (string.IsNullOrWhiteSpace(upstreamPath))
        {
            return InvalidPath("Hoppa upstream path is required.");
        }

        if (!upstreamPath.StartsWith('/'))
        {
            return InvalidPath("Hoppa upstream path must be absolute relative to the configured base URL.");
        }

        if (upstreamPath.Contains("://", StringComparison.Ordinal) || upstreamPath.Contains('\\', StringComparison.Ordinal))
        {
            return InvalidPath("Hoppa upstream path must not contain a scheme or backslashes.");
        }

        return null;
    }

    private static ApplicationError InvalidPath(string detail)
    {
        return new ApplicationError(
            "hoppa.path.invalid",
            "The Hoppa upstream path is invalid.",
            (int)HttpStatusCode.InternalServerError,
            detail);
    }
}
