using System.Net;
using Microsoft.AspNetCore.Http;

namespace NeoBanking.Infrastructure.Hoppa;

/// <summary>Matches the deployment contract: only loopback nginx may supply its overwritten X-Real-IP.</summary>
public static class TrustedClientAddress
{
    public static IPAddress? Resolve(HttpContext? context)
    {
        var peer=context?.Connection.RemoteIpAddress;
        if(peer?.IsIPv4MappedToIPv6==true)peer=peer.MapToIPv4();
        if(peer is null)return null;
        var client=peer;
        if(IPAddress.IsLoopback(peer))
        {
            if(!IPAddress.TryParse(context!.Request.Headers["X-Real-IP"].ToString(),out client))return null;
        }
        if(client.IsIPv4MappedToIPv6)client=client.MapToIPv4();
        // Proxy/local addresses are unavailable observations, never a shared fraud fingerprint.
        return IPAddress.IsLoopback(client) ? null : client;
    }
}
