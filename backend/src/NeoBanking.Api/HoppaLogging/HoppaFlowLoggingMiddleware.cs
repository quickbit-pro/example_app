using System.Security.Claims;
using System.Text;
using System.Text.Json;
using NeoBanking.Application.Company;
using NeoBanking.Application.Interfaces;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.HoppaLogging;

public sealed class HoppaFlowLoggingMiddleware(
    RequestDelegate next,
    ILogger<HoppaFlowLoggingMiddleware> logger)
{
    private const int MaxBodyCharacters = 120_000;

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = false
    };

    private static readonly HashSet<string> SensitiveKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        "accessToken",
        "apiKey",
        "authorization",
        "idToken",
        "serverObservedIp", "server_observed_ip",
        "installationToken", "installation_token",
        "invitationToken", "invitation_token",
        "consentToken", "consent_token",
        "quoteToken", "quote_token",
        "quoteReceipt", "quote_receipt", "referralQuoteReceipt", "referral_quote_receipt",
        "password",
        "currentPassword",
        "newPassword",
        "adminPassword",
        "code",
        "otp",
        "otpCode",
        "widgetUrl",
        "uboIdNumber",
        "uboDob",
        "refreshToken",
        "secret",
        "token"
    };

    public async Task InvokeAsync(
        HttpContext context,
        IHoppaFlowLogCollector collector,
        NeoBankingDbContext dbContext,
        ICompanyContextAccessor companyContextAccessor)
    {
        // Assistant conversations must bypass request/response body logging.
        if (context.Request.Path.StartsWithSegments("/api/v1/mobile/assistant", StringComparison.OrdinalIgnoreCase) ||
            context.Request.Path.StartsWithSegments("/api/v1/mobile/transaction-documents", StringComparison.OrdinalIgnoreCase) ||
            context.Request.Path.StartsWithSegments("/api/v1/mobile/documents", StringComparison.OrdinalIgnoreCase))
        { await next(context); return; }
        var appRequestBody = IsSensitiveReferralRequest(context.Request.Path)
            ? "[REDACTED REFERRAL PAYLOAD]"
            : await ReadRequestBodyAsync(context.Request).ConfigureAwait(false);
        var originalResponseBody = context.Response.Body;
        await using var responseBuffer = new MemoryStream();
        context.Response.Body = responseBuffer;

        try
        {
            await next(context).ConfigureAwait(false);
        }
        finally
        {
            responseBuffer.Position = 0;
            var appResponseBody = await ReadResponseBodyAsync(responseBuffer).ConfigureAwait(false);
            responseBuffer.Position = 0;
            await responseBuffer.CopyToAsync(originalResponseBody, context.RequestAborted).ConfigureAwait(false);
            context.Response.Body = originalResponseBody;

            if (collector.HasHoppaExchanges)
            {
                try
                {
                    await PersistAsync(
                        context,
                        collector,
                        dbContext,
                        companyContextAccessor.Current,
                        appRequestBody,
                        appResponseBody).ConfigureAwait(false);
                }
                catch (Exception exception)
                {
                    logger.LogError(
                        exception,
                        "Failed to persist Hoppa API call log for trace {TraceId}.",
                        context.TraceIdentifier);
                }
            }
        }
    }

    private static async Task PersistAsync(
        HttpContext context,
        IHoppaFlowLogCollector collector,
        NeoBankingDbContext dbContext,
        ICompanyContext company,
        string? appRequestBody,
        string? appResponseBody)
    {
        Guid? companyInstallationId = Guid.TryParse(company.InstallationId, out var parsedCompanyId)
            ? parsedCompanyId
            : null;
        Guid? actorUserId = TryGetActorUserId(context.User);
        var queryString = SanitizeQuery(context.Request.QueryString.Value);

        var morFlow = context.Request.Path.StartsWithSegments("/api/v1/mor") || context.Request.Path.StartsWithSegments("/api/v1/admin/mor");
        foreach (var exchange in collector.HoppaExchanges)
        {
            dbContext.HoppaApiCallLogs.Add(new HoppaApiCallLog
            {
                CompanyInstallationId = companyInstallationId,
                ActorUserId = actorUserId,
                TraceId = context.TraceIdentifier,
                IpAddress = IsSensitiveReferralRequest(context.Request.Path) ? null : GetClientIpAddress(context),
                UserAgent = context.Request.Headers.UserAgent.FirstOrDefault(),
                OccurredAt = exchange.OccurredAt,
                AppMethod = context.Request.Method,
                Direction = "outbound",
                AppPath = context.Request.Path.Value ?? string.Empty,
                AppQueryString = queryString,
                AppStatusCode = context.Response.StatusCode,
                AppRequestJson = NormalizeBody(appRequestBody, morFlow),
                AppResponseJson = NormalizeBody(appResponseBody, morFlow),
                HoppaMethod = exchange.Method.Method,
                HoppaEndpoint = exchange.Endpoint,
                HoppaQueryString = SanitizeQuery(exchange.QueryString),
                HoppaStatusCode = exchange.StatusCode,
                HoppaDurationMs = exchange.DurationMs,
                Succeeded = exchange.Succeeded,
                FailureCode = exchange.FailureCode,
                FailureMessage = exchange.FailureMessage,
                HoppaRequestJson = NormalizeBody(exchange.RequestJson),
                HoppaResponseJson = NormalizeBody(exchange.ResponseJson)
            });
        }

        await dbContext.SaveChangesAsync(CancellationToken.None).ConfigureAwait(false);
    }

    private static Guid? TryGetActorUserId(ClaimsPrincipal user)
    {
        foreach (var claimType in new[] { "local_user_id", ClaimTypes.NameIdentifier, "user_id", "uid" })
        {
            var value = user.FindFirstValue(claimType);
            if (Guid.TryParse(value, out var userId))
            {
                return userId;
            }
        }

        return null;
    }

    private static string? GetClientIpAddress(HttpContext context)
    {
        var forwardedFor = context.Request.Headers["X-Forwarded-For"].FirstOrDefault();
        var forwardedAddress = forwardedFor?.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(forwardedAddress))
        {
            return forwardedAddress;
        }

        var realIp = context.Request.Headers["X-Real-IP"].FirstOrDefault();
        return !string.IsNullOrWhiteSpace(realIp)
            ? realIp
            : context.Connection.RemoteIpAddress?.ToString();
    }

    private static bool IsSensitiveReferralRequest(PathString path) =>
        path.StartsWithSegments("/api/v1/mobile/auth/signup", StringComparison.OrdinalIgnoreCase) ||
        path.StartsWithSegments("/api/v1/mobile/auth/referral-quote", StringComparison.OrdinalIgnoreCase);

    private static string? SanitizeQuery(string? query)
    {
        if (string.IsNullOrEmpty(query)) return null;
        var parameters = Microsoft.AspNetCore.WebUtilities.QueryHelpers.ParseQuery(query);
        return QueryString.Create(parameters.SelectMany(parameter => parameter.Value.Select(value =>
            new KeyValuePair<string, string?>(parameter.Key,
                SensitiveKeys.Contains(parameter.Key) ? "[REDACTED]" : value)))).Value;
    }

    private static async Task<string?> ReadRequestBodyAsync(HttpRequest request)
    {
        if (request.ContentLength is null or 0 || !IsTextLike(request.ContentType))
        {
            return null;
        }

        request.EnableBuffering();
        using var reader = new StreamReader(request.Body, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);
        var body = await reader.ReadToEndAsync().ConfigureAwait(false);
        request.Body.Position = 0;
        return Truncate(body);
    }

    private static async Task<string?> ReadResponseBodyAsync(Stream responseBody)
    {
        using var reader = new StreamReader(responseBody, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);
        return Truncate(await reader.ReadToEndAsync().ConfigureAwait(false));
    }

    private static bool IsTextLike(string? contentType)
    {
        if (string.IsNullOrWhiteSpace(contentType))
        {
            return false;
        }

        return contentType.Contains("json", StringComparison.OrdinalIgnoreCase) ||
               contentType.Contains("text/", StringComparison.OrdinalIgnoreCase) ||
               contentType.Contains("xml", StringComparison.OrdinalIgnoreCase) ||
               contentType.Contains("form", StringComparison.OrdinalIgnoreCase);
    }

    private static string? NormalizeBody(string? body, bool omitUnstructured = false)
    {
        if (string.IsNullOrWhiteSpace(body))
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(body);
            return JsonSerializer.Serialize(RedactElement(document.RootElement), JsonOptions);
        }
        catch (JsonException)
        {
            return JsonSerializer.Serialize(new { raw = omitUnstructured ? "[Unstructured MOR payload omitted]" : Truncate(body) }, JsonOptions);
        }
    }

    private static object? RedactElement(JsonElement element)
    {
        return element.ValueKind switch
        {
            JsonValueKind.Object => element.EnumerateObject().ToDictionary(
                property => property.Name,
                property => SensitiveKeys.Contains(property.Name) ? "***REDACTED***" : RedactElement(property.Value)),
            JsonValueKind.Array => element.EnumerateArray().Select(RedactElement).ToArray(),
            JsonValueKind.String => element.GetString(),
            JsonValueKind.Number => element.TryGetInt64(out var integer) ? integer : element.GetDecimal(),
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.Null => null,
            _ => element.GetRawText()
        };
    }

    private static string? Truncate(string? value)
    {
        if (string.IsNullOrEmpty(value) || value.Length <= MaxBodyCharacters)
        {
            return value;
        }

        return string.Concat(value.AsSpan(0, MaxBodyCharacters), "...[truncated]");
    }
}
