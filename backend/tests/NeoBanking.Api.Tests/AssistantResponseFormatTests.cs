using System.Text.Json;
using NeoBanking.Api.Assistant;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed partial class AssistantServiceTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task ProviderSchemas_EnforceRootSearchesAndBoundedRecommendationFields(bool links)
    {
        using var handler = new StubHandler(Envelope(Classification), Envelope(ValidAnswer));
        var result = await Service(handler, new FakeQuota(), new AssistantOptions
            { Enabled = true, RecommendationLinksEnabled = links }).ChatAsync(CompanyId, UserId, Request(), default);
        Assert.True(result.IsSuccess);
        foreach (var sent in handler.Requests)
        {
            using var payload = JsonDocument.Parse(sent.Body);
            var root = payload.RootElement;
            Assert.True(root.GetProperty("provider").GetProperty("require_parameters").GetBoolean());
            var format = root.GetProperty("response_format");
            Assert.Equal("json_schema", format.GetProperty("type").GetString());
            Assert.True(format.GetProperty("json_schema").GetProperty("strict").GetBoolean());
        }
        using var classifier = JsonDocument.Parse(handler.Requests[0].Body);
        var classifierSchema = classifier.RootElement.GetProperty("response_format").GetProperty("json_schema").GetProperty("schema");
        Assert.False(classifierSchema.GetProperty("additionalProperties").GetBoolean());
        Assert.Equal("scope", Assert.Single(classifierSchema.GetProperty("properties").EnumerateObject()).Name);
        using var response = JsonDocument.Parse(handler.Requests[1].Body);
        var schema = response.RootElement.GetProperty("response_format").GetProperty("json_schema").GetProperty("schema");
        Assert.False(schema.GetProperty("additionalProperties").GetBoolean());
        Assert.True(schema.GetProperty("properties").TryGetProperty("searches", out _));
        var answer = schema.GetProperty("properties").GetProperty("answer").GetProperty("anyOf")[0];
        Assert.False(answer.GetProperty("additionalProperties").GetBoolean());
        Assert.False(answer.GetProperty("properties").TryGetProperty("searches", out _));
        var options = answer.GetProperty("properties").GetProperty("options");
        Assert.Equal(3, options.GetProperty("maxItems").GetInt32());
        var option = options.GetProperty("items");
        Assert.False(option.GetProperty("additionalProperties").GetBoolean());
        Assert.Equal(links, option.GetProperty("properties").TryGetProperty("sourceUrl", out _));
        Assert.Equal(160, option.GetProperty("properties").GetProperty("highlights").GetProperty("items").GetProperty("maxLength").GetInt32());
    }

    [Theory]
    [InlineData(-1, 5, 60)]
    [InlineData(45, 45, 60)]
    [InlineData(90, 90, 105)]
    [InlineData(120, 90, 105)]
    [InlineData(int.MaxValue, 90, 105)]
    public async Task RequestDeadlineFitsClientAndLeaseOutlivesProcessing(int configured, int deadline, int lease)
    {
        var options = new AssistantOptions { Enabled = true, TimeoutSeconds = configured };
        Assert.Equal(deadline, options.RequestTimeoutSeconds);
        Assert.Equal(lease, options.LeaseSeconds);
        using var handler = new StubHandler(Envelope(Classification), Envelope(ValidAnswer));
        var quota = new FakeQuota();
        var result = await Service(handler, quota, options).ChatAsync(CompanyId, UserId, Request(), default);
        Assert.True(result.IsSuccess);
        Assert.Equal(lease, quota.LastLimits!.LeaseSeconds);
        Assert.True(lease > deadline);
        Assert.Single(quota.Released);
    }

    [Fact]
    public async Task MisnestedSearchesRemainInvalidIfProviderIgnoresSchema()
    {
        var answer = StructuredAnswer();
        answer["searches"] = new[] { new { kind = "hotels", query = "Rome" } };
        using var handler = new StubHandler(Envelope(Classification), Envelope(JsonSerializer.Serialize(new { scope = "hotels", answer })));
        var result = await Service(handler, new FakeQuota()).ChatAsync(CompanyId, UserId, Request(), default);
        Assert.Equal("assistant.provider_unavailable", result.Error!.Code);
    }
}
