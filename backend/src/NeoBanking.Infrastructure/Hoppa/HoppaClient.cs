using System.Net;
using System.Net.Http.Json;
using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;
using NeoBanking.Application.Common;
using NeoBanking.Application.Interfaces;

namespace NeoBanking.Infrastructure.Hoppa;

public sealed class HoppaClient : IHoppaClient
{
    private static readonly HashSet<string> SensitiveJsonProperties = new(StringComparer.OrdinalIgnoreCase)
    {
        "password",
        "adminPassword",
        "uboIdNumber",
        "uboDob",
        "widgetUrl",
        "code",
        "otp",
        "otpCode",
        "token",
        "accessToken",
        "refreshToken",
        "apiKey",
        "serverObservedIp", "server_observed_ip",
        "installationToken", "installation_token",
        "invitationToken", "invitation_token",
        "consentToken", "consent_token",
        "quoteToken", "quote_token",
        "quoteReceipt", "quote_receipt", "referralQuoteReceipt", "referral_quote_receipt",
        "secret"
    };

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.General)
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly HttpClient _httpClient;
    private readonly HoppaOptions _options;
    private readonly IHoppaFlowLogCollector _flowLogCollector;

    public HoppaClient(
        HttpClient httpClient,
        IOptions<HoppaOptions> options,
        IHoppaFlowLogCollector flowLogCollector)
    {
        _httpClient = httpClient;
        _options = options.Value;
        _flowLogCollector = flowLogCollector;
    }

    public async Task<ApplicationResult<HoppaDownload>> DownloadAsync(HoppaRequest<object?> request,CancellationToken ct)
    {
        var configurationError=ValidateConfiguration<HoppaDownload>();
        if(configurationError is not null) return configurationError;
        // Download routes are server-constructed and confined to referral resources.
        if(request.Method!=HttpMethod.Get || !request.Path.StartsWith("/api/v2/referrals/",StringComparison.Ordinal) ||
            request.Path.Contains("..",StringComparison.Ordinal) || request.Path.Contains('\\'))
            return Failure<HoppaDownload>("hoppa.download.invalid_path","Invalid download path.",HttpStatusCode.BadRequest);
        using var outgoing=new HttpRequestMessage(HttpMethod.Get,BuildRequestUri(request.Path,request.Query));
        outgoing.Headers.TryAddWithoutValidation("x-api-key",_options.ApiKey);
        await ReferralActorSigner.SignAsync(outgoing,request.TrustedReferralActorId,_options.ReferralAuditDelegation,ct);
        HttpResponseMessage? response=null;
        try
        {
            response=await _httpClient.SendAsync(outgoing,HttpCompletionOption.ResponseHeadersRead,ct);
            if(!response.IsSuccessStatusCode)
            {
                var detail=await response.Content.ReadAsStringAsync(ct);
                var error=Failure<HoppaDownload>(request.FailureCode,request.FailureMessage,response.StatusCode,detail);
                response.Dispose(); return error;
            }
            var stream=await response.Content.ReadAsStreamAsync(ct);
            return ApplicationResult<HoppaDownload>.Success(new HoppaDownload(response,stream));
        }
        catch(HttpRequestException)
        { response?.Dispose(); return Failure<HoppaDownload>("hoppa.unavailable","The export provider is unavailable.",HttpStatusCode.BadGateway); }
        catch(OperationCanceledException) when(!ct.IsCancellationRequested)
        { response?.Dispose(); return Failure<HoppaDownload>("hoppa.timeout","The export request timed out.",HttpStatusCode.GatewayTimeout); }
        catch { response?.Dispose(); throw; }
    }

    public async Task<ApplicationResult<TResponse>> SendAsync<TRequest, TResponse>(
        HoppaRequest<TRequest> request,
        CancellationToken cancellationToken)
    {
        var configurationError = ValidateConfiguration<TResponse>();
        if (configurationError is not null)
        {
            return configurationError;
        }

        var requestUri = BuildRequestUri(request.Path, request.Query);
        var requestJson = SerializeRequestBody(request.Body);
        using var httpRequest = new HttpRequestMessage(request.Method, requestUri);
        httpRequest.Headers.TryAddWithoutValidation("x-api-key", _options.ApiKey);

        if (request.Body is HttpContent httpContent)
        {
            httpRequest.Content = httpContent;
        }
        else if (request.Body is not null)
        {
            httpRequest.Content = JsonContent.Create(request.Body, options: JsonOptions);
        }

        await ReferralActorSigner.SignAsync(httpRequest, request.TrustedReferralActorId, _options.ReferralAuditDelegation, cancellationToken);

        var stopwatch = Stopwatch.StartNew();

        try
        {
            using var response = await _httpClient.SendAsync(httpRequest, cancellationToken).ConfigureAwait(false);
            var responseBody = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            stopwatch.Stop();
            RecordExchange(
                request,
                requestUri,
                requestJson,
                response.StatusCode,
                stopwatch.ElapsedMilliseconds,
                response.IsSuccessStatusCode,
                response.IsSuccessStatusCode ? null : request.FailureCode,
                response.IsSuccessStatusCode ? null : request.FailureMessage,
                responseBody);

            if (!response.IsSuccessStatusCode)
            {
                // A registered user may not have a provider account yet. Only this
                // explicit card-list refusal represents an empty collection.
                if (request.Method == HttpMethod.Get &&
                    request.Path == "/api/v2/cards" &&
                    response.StatusCode == HttpStatusCode.NotFound &&
                    IsMissingCardAccount(responseBody))
                {
                    var empty = JsonSerializer.Deserialize<TResponse>(
                        """{"cards":[],"total":0,"pageTotal":0}""", JsonOptions);
                    return ApplicationResult<TResponse>.Success(empty!);
                }

                return Failure<TResponse>(
                    request.FailureCode,
                    request.FailureMessage,
                    response.StatusCode,
                    responseBody);
            }

            if (string.IsNullOrWhiteSpace(responseBody))
            {
                return ApplicationResult<TResponse>.Success(default!);
            }

            var value = JsonSerializer.Deserialize<TResponse>(responseBody, JsonOptions);
            return ApplicationResult<TResponse>.Success(value!);
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            stopwatch.Stop();
            RecordExchange(
                request,
                requestUri,
                requestJson,
                HttpStatusCode.GatewayTimeout,
                stopwatch.ElapsedMilliseconds,
                false,
                "hoppa.timeout",
                "The provider request timed out.",
                null);
            return Failure<TResponse>("hoppa.timeout", "The provider request timed out.", HttpStatusCode.GatewayTimeout);
        }
        catch (HttpRequestException exception)
        {
            stopwatch.Stop();
            RecordExchange(
                request,
                requestUri,
                requestJson,
                HttpStatusCode.BadGateway,
                stopwatch.ElapsedMilliseconds,
                false,
                "hoppa.unavailable",
                "The provider is unavailable right now. Try again shortly.",
                exception.Message);
            return Failure<TResponse>("hoppa.unavailable", "The provider is unavailable right now. Try again shortly.", HttpStatusCode.BadGateway, exception.Message);
        }
        catch (JsonException exception)
        {
            stopwatch.Stop();
            RecordExchange(
                request,
                requestUri,
                requestJson,
                HttpStatusCode.BadGateway,
                stopwatch.ElapsedMilliseconds,
                false,
                "hoppa.invalid_response",
                "The provider returned an invalid response.",
                exception.Message);
            return Failure<TResponse>("hoppa.invalid_response", "The provider returned an invalid response.", HttpStatusCode.BadGateway, exception.Message);
        }
    }

    private void RecordExchange<TRequest>(
        HoppaRequest<TRequest> request,
        string requestUri,
        string? requestJson,
        HttpStatusCode statusCode,
        long durationMs,
        bool succeeded,
        string? failureCode,
        string? failureMessage,
        string? responseJson)
    {
        if (request.SuppressPayloadLogging) return;
        var questionMarkIndex = requestUri.IndexOf('?', StringComparison.Ordinal);
        _flowLogCollector.AddHoppaExchange(new HoppaExchangeLog
        {
            Method = request.Method,
            Endpoint = questionMarkIndex < 0 ? requestUri : requestUri[..questionMarkIndex],
            QueryString = questionMarkIndex < 0 ? null : requestUri[questionMarkIndex..],
            StatusCode = (int)statusCode,
            DurationMs = durationMs,
            Succeeded = succeeded,
            FailureCode = failureCode,
            FailureMessage = failureMessage,
            RequestJson = requestJson,
            ResponseJson = (request.Path.StartsWith("/api/v2/mor/public/", StringComparison.Ordinal) || request.Path.EndsWith("/widget", StringComparison.Ordinal))
                ? RedactSensitiveResponse(responseJson)
                : responseJson
        });
    }

    private static string? RedactSensitiveResponse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return json;
        try
        {
            var node = JsonNode.Parse(json);
            RedactSensitiveProperties(node);
            return node?.ToJsonString(JsonOptions);
        }
        catch (JsonException)
        {
            return "[Unstructured sensitive response omitted]";
        }
    }

    private static string? SerializeRequestBody<TRequest>(TRequest? body)
    {
        if (body is null)
        {
            return null;
        }

        if (body is HttpContent)
        {
            return "{\"content\":\"HttpContent body was streamed to Hoppa.\"}";
        }

        var node = JsonSerializer.SerializeToNode(body, JsonOptions);
        RedactSensitiveProperties(node);
        return node?.ToJsonString(JsonOptions);
    }

    private static void RedactSensitiveProperties(JsonNode? node)
    {
        if (node is JsonObject jsonObject)
        {
            foreach (var property in jsonObject.ToList())
            {
                if (SensitiveJsonProperties.Contains(property.Key))
                {
                    jsonObject[property.Key] = "[REDACTED]";
                }
                else
                {
                    RedactSensitiveProperties(property.Value);
                }
            }
        }
        else if (node is JsonArray jsonArray)
        {
            foreach (var item in jsonArray)
            {
                RedactSensitiveProperties(item);
            }
        }
    }

    private ApplicationResult<TResponse>? ValidateConfiguration<TResponse>()
    {
        if (_httpClient.BaseAddress is null)
        {
            return Failure<TResponse>(
                "hoppa.configuration.missing_base_url",
                "Hoppa base URL is not configured.",
                HttpStatusCode.InternalServerError);
        }

        if (string.IsNullOrWhiteSpace(_options.ApiKey))
        {
            return Failure<TResponse>(
                "hoppa.configuration.missing_api_key",
                "Hoppa API key is not configured.",
                HttpStatusCode.InternalServerError);
        }

        return null;
    }

    private static string BuildRequestUri(string path, IReadOnlyDictionary<string, string?> query)
    {
        if (query.Count == 0)
        {
            return path;
        }

        var queryParameters = query
            .Where(pair => !string.IsNullOrWhiteSpace(pair.Value))
            .ToDictionary(pair => pair.Key, pair => pair.Value);

        return queryParameters.Count == 0
            ? path
            : QueryHelpers.AddQueryString(path, queryParameters);
    }

    private static bool IsMissingCardAccount(string body)
    {
        try
        {
            using var document = JsonDocument.Parse(body);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
                return false;

            return document.RootElement.EnumerateObject().Any(property =>
                string.Equals(property.Name, "code", StringComparison.OrdinalIgnoreCase) &&
                property.Value.ValueKind == JsonValueKind.String &&
                property.Value.GetString() == "ACCOUNT_NOT_FOUND");
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static ApplicationResult<TResponse> Failure<TResponse>(
        string code,
        string message,
        HttpStatusCode statusCode,
        string? detail = null)
    {
        return ApplicationResult<TResponse>.Failure(
            new ApplicationError(code, message, (int)statusCode, detail));
    }
}
