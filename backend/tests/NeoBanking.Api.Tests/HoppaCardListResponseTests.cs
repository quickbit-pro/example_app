using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using NeoBanking.Api.HoppaLogging;
using NeoBanking.Infrastructure.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class HoppaCardListResponseTests
{
    [Theory]
    [InlineData("""{"code":"ACCOUNT_NOT_FOUND","status":404}""")]
    [InlineData("""{"Code":"ACCOUNT_NOT_FOUND","Status":404}""")]
    public async Task MissingAccount_ReturnsEmptyCardCollection(string body)
    {
        var result = await SendAsync("GET", "/api/v2/cards", 404, body);

        Assert.True(result.IsSuccess);
        Assert.Empty(result.Value!.Value.GetProperty("cards").EnumerateArray());
        Assert.Equal(0, result.Value.Value.GetProperty("total").GetInt32());
        Assert.Equal(0, result.Value.Value.GetProperty("pageTotal").GetInt32());
    }

    [Theory]
    [InlineData("GET", "/api/v2/cards", 404, """{"code":"USER_NOT_FOUND"}""")]
    [InlineData("GET", "/api/v2/cards", 404, """{"code":"USER_OR_ACCOUNT_NOT_FOUND"}""")]
    [InlineData("GET", "/api/v2/cards", 404, """{"message":"Account not found"}""")]
    [InlineData("GET", "/api/v2/cards", 404, "not json")]
    [InlineData("GET", "/api/v2/cards", 404, "null")]
    [InlineData("GET", "/api/v2/cards", 404, "[]")]
    [InlineData("GET", "/api/v2/cards", 401, """{"code":"ACCOUNT_NOT_FOUND"}""")]
    [InlineData("GET", "/api/v2/cards", 500, """{"code":"ACCOUNT_NOT_FOUND"}""")]
    [InlineData("POST", "/api/v2/cards", 404, """{"code":"ACCOUNT_NOT_FOUND"}""")]
    [InlineData("GET", "/api/v2/cards/42", 404, """{"code":"ACCOUNT_NOT_FOUND"}""")]
    public async Task OtherFailures_PreserveStatusAndBody(string method, string path, int status, string body)
    {
        var result = await SendAsync(method, path, status, body);

        Assert.False(result.IsSuccess);
        Assert.Equal(status, result.Error!.StatusCode);
        Assert.Equal(body, result.Error.Detail);
    }

    [Fact]
    public async Task SuccessfulList_PreservesCards()
    {
        var result = await SendAsync("GET", "/api/v2/cards", 200,
            """{"cards":[{"id":42}],"total":1,"pageTotal":1}""");

        Assert.True(result.IsSuccess);
        Assert.Equal(42, result.Value!.Value.GetProperty("cards")[0].GetProperty("id").GetInt32());
    }

    private static async Task<NeoBanking.Application.Common.ApplicationResult<JsonElement?>> SendAsync(
        string method, string path, int status, string body)
    {
        using var http = new HttpClient(new ResponseHandler(status, body))
        {
            BaseAddress = new Uri("https://provider.invalid")
        };
        var client = new HoppaClient(http, Options.Create(new HoppaOptions { ApiKey = "test-key" }),
            new HoppaFlowLogCollector());
        return await client.SendAsync<object?, JsonElement?>(new()
        {
            Method = new HttpMethod(method),
            Path = path,
            Query = new Dictionary<string, string?> { ["userId"] = "1246" },
            FailureCode = "mobile.cards.list.failed",
            FailureMessage = "We could not list cards."
        }, CancellationToken.None);
    }

    private sealed class ResponseHandler(int status, string body) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            => Task.FromResult(new HttpResponseMessage((HttpStatusCode)status)
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json")
            });
    }
}
