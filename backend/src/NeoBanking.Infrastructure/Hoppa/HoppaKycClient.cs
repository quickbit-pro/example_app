using System;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Options;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Kyc;
using NeoBanking.Application.Interfaces;
using NeoBanking.Infrastructure.Hoppa.DTOs;

namespace NeoBanking.Infrastructure.Hoppa;

public sealed class HoppaKycClient : IHoppaKycClient
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.General)
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly HttpClient _httpClient;
    private readonly HoppaOptions _options;

    public HoppaKycClient(HttpClient httpClient, IOptions<HoppaOptions> options)
    {
        _httpClient = httpClient;
        _options = options.Value;
    }

    public async Task<ApplicationResult<SumSubAccessTokenResponseDto>> CreateSumSubAccessTokenAsync(
        string userId,
        string? clientIpAddress,
        SumSubAccessTokenRequestDto request,
        CancellationToken cancellationToken)
    {
        if (_httpClient.BaseAddress is null)
        {
            return Failure("hoppa.configuration.missing_base_url", "Hoppa base URL is not configured.", HttpStatusCode.InternalServerError);
        }

        if (string.IsNullOrWhiteSpace(_options.ApiKey))
        {
            return Failure("hoppa.configuration.missing_api_key", "Hoppa API key is not configured.", HttpStatusCode.InternalServerError);
        }

        using var httpRequest = new HttpRequestMessage(
            HttpMethod.Post,
            $"/api/v2/users/{Uri.EscapeDataString(userId)}/kyc/sumsub-access-token");

        httpRequest.Headers.TryAddWithoutValidation("x-api-key", _options.ApiKey);
        httpRequest.Content = JsonContent.Create(
            new HoppaSumSubAccessTokenRequest
            {
                Occupation = request.Occupation,
                AnnualSalary = request.AnnualSalary,
                AccountPurpose = request.AccountPurpose,
                ExpectedMonthlyVolume = request.ExpectedMonthlyVolume,
                DocumentIssueDate = request.DocumentIssueDate,
                IpAddress = clientIpAddress
            },
            options: JsonOptions);

        try
        {
            using var response = await _httpClient.SendAsync(httpRequest, cancellationToken).ConfigureAwait(false);
            var responseBody = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);

            if (!response.IsSuccessStatusCode)
            {
                return Failure(
                    "hoppa.kyc.sumsub_token_failed",
                    "Hoppa failed to create a SumSub access token.",
                    response.StatusCode,
                    responseBody);
            }

            var hoppaResponse = JsonSerializer.Deserialize<HoppaSumSubAccessTokenResponse>(responseBody, JsonOptions);
            if (string.IsNullOrWhiteSpace(hoppaResponse?.Token))
            {
                return Failure(
                    "hoppa.kyc.invalid_response",
                    "Hoppa returned an invalid SumSub access token response.",
                    HttpStatusCode.BadGateway,
                    responseBody);
            }

            return ApplicationResult<SumSubAccessTokenResponseDto>.Success(
                new SumSubAccessTokenResponseDto
                {
                    Token = hoppaResponse.Token,
                    UserId = hoppaResponse.UserId ?? userId,
                    LevelName = hoppaResponse.LevelName ?? request.LevelName,
                    ExpiresAt = hoppaResponse.ExpiresAt ?? CalculateExpiry(hoppaResponse.ExpiresInSecs)
                });
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return Failure("hoppa.timeout", "Hoppa request timed out.", HttpStatusCode.GatewayTimeout);
        }
        catch (HttpRequestException exception)
        {
            return Failure("hoppa.unavailable", "Hoppa is unavailable.", HttpStatusCode.BadGateway, exception.Message);
        }
        catch (JsonException exception)
        {
            return Failure("hoppa.kyc.invalid_response", "Hoppa returned malformed JSON.", HttpStatusCode.BadGateway, exception.Message);
        }
    }

    private static DateTimeOffset? CalculateExpiry(int? expiresInSecs)
    {
        return expiresInSecs is > 0
            ? DateTimeOffset.UtcNow.AddSeconds(expiresInSecs.Value)
            : null;
    }

    private static ApplicationResult<SumSubAccessTokenResponseDto> Failure(
        string code,
        string message,
        HttpStatusCode statusCode,
        string? detail = null)
    {
        return ApplicationResult<SumSubAccessTokenResponseDto>.Failure(
            new ApplicationError(code, message, (int)statusCode, detail));
    }
}
