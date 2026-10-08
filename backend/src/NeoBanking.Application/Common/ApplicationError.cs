using System.Collections.Generic;

namespace NeoBanking.Application.Common;

public sealed class ApplicationError
{
    public ApplicationError(
        string code,
        string message,
        int statusCode,
        string? detail = null,
        IReadOnlyDictionary<string, string[]>? validationErrors = null)
    {
        Code = code;
        Message = message;
        StatusCode = statusCode;
        Detail = detail;
        ValidationErrors = validationErrors;
    }

    public string Code { get; }

    public string Message { get; }

    public int StatusCode { get; }

    public string? Detail { get; }

    public IReadOnlyDictionary<string, string[]>? ValidationErrors { get; }
}
