using System.Net;
using Microsoft.AspNetCore.Http;

namespace NeoBanking.Infrastructure.Hoppa;

/// <summary>Preserves each client's rate-limit allowance across our API proxy.</summary>
public sealed class HoppaClientAddressHandler(IHttpContextAccessor accessor) : DelegatingHandler
{
    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        // Never relay a caller-supplied forwarding chain. Nginx overwrites
        // X-Real-IP and reaches Kestrel through loopback in our deployment.
        request.Headers.Remove("X-Forwarded-For");
        var client = TrustedClientAddress.Resolve(accessor.HttpContext);
        if (client is not null && !IPAddress.IsLoopback(client))
        {
            request.Headers.TryAddWithoutValidation("X-Forwarded-For", client.ToString());
        }
        return base.SendAsync(request, cancellationToken);
    }
}
