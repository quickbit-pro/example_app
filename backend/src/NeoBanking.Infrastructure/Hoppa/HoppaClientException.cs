using System;
using System.Net;

namespace NeoBanking.Infrastructure.Hoppa;

public sealed class HoppaClientException : Exception
{
    public HoppaClientException(HttpStatusCode statusCode, string responseBody)
        : base($"Hoppa API request failed with status {(int)statusCode}.")
    {
        StatusCode = statusCode;
        ResponseBody = responseBody;
    }

    public HttpStatusCode StatusCode { get; }

    public string ResponseBody { get; }
}
