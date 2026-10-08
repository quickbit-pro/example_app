using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Controllers;
using NeoBanking.Api.HoppaLogging;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Infrastructure.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class ReferralCapContractTests
{
    [Theory]
    [InlineData("INHERIT", null, "CAPPED", "0")]
    [InlineData("UNLIMITED", null, "INHERIT", null)]
    [InlineData("CAPPED", "1234.56", "UNLIMITED", null)]
    [InlineData("UNLIMITED", null, "UNLIMITED", null)]
    public async Task DraftRoundTripPreservesIndependentModesNullAndZero(
        string volumeMode, string? volumeAmount, string rewardMode, string? rewardAmount)
    {
        var body = JsonSerializer.SerializeToElement(new
        {
            MaxEligibleVolumePerRelationship = (decimal?)null,
            MaximumRecurringReward = 0m,
            Levels = new[] { new {
                Name = "LV1", VolumeCapMode = volumeMode,
                VolumeCapAmount = Amount(volumeAmount),
                RecurringRewardCapMode = rewardMode,
                RecurringRewardCapAmount = Amount(rewardAmount),
                QualificationCalculationType = "FIXED", QualificationRate = 1m,
                TopupCalculationType = "PERCENT_OF_WL_FEE", TopupRate = 8m
            } }
        });
        using var handler = new Capture(body.GetRawText());
        using var client = new HttpClient(handler) { BaseAddress = new Uri("https://engine.invalid") };
        var controller = Create(client);
        controller.Request.QueryString = new QueryString("?companyId=999&apiKey=untrusted");
        var program = Guid.NewGuid(); var draft = Guid.NewGuid();

        var response = await controller.UpdateDraft(program, draft, body, default);

        Assert.Equal($"/api/v2/referrals/programs/{program:D}/drafts/{draft:D}", handler.Path);
        Assert.Equal(HttpMethod.Put, handler.Method);
        Assert.Equal(JsonValueKind.Null, handler.Body.GetProperty("MaxEligibleVolumePerRelationship").ValueKind);
        Assert.Equal(0m, handler.Body.GetProperty("MaximumRecurringReward").GetDecimal());
        var level = handler.Body.GetProperty("Levels")[0];
        Assert.Equal(volumeMode, level.GetProperty("VolumeCapMode").GetString());
        Assert.Equal(rewardMode, level.GetProperty("RecurringRewardCapMode").GetString());
        Assert.Equal(Amount(volumeAmount), ReadAmount(level.GetProperty("VolumeCapAmount")));
        Assert.Equal(Amount(rewardAmount), ReadAmount(level.GetProperty("RecurringRewardCapAmount")));
        Assert.Equal(1m, level.GetProperty("QualificationRate").GetDecimal());
        Assert.Equal(8m, level.GetProperty("TopupRate").GetDecimal());
        var result = Assert.IsType<JsonElement>(Assert.IsType<OkObjectResult>(response.Result).Value);
        Assert.Equal(body.GetRawText(), result.GetRawText());
    }

    [Fact]
    public async Task EffectiveCapProvenanceReachesAdminUnmodified()
    {
        const string json = """
            {"MaxEligibleVolumePerRelationship":null,"MaximumRecurringReward":0,
             "Levels":[{"VolumeCapMode":"UNLIMITED","VolumeCapAmount":null,
               "RecurringRewardCapMode":"INHERIT","RecurringRewardCapAmount":null,
               "EffectiveVolumeCap":null,"EffectiveRecurringRewardCap":0,
               "VolumeCapSource":"LEVEL_UNLIMITED","RecurringRewardCapSource":"PROGRAM_DEFAULT"}]}
            """;
        using var handler = new Capture(json);
        using var client = new HttpClient(handler) { BaseAddress = new Uri("https://engine.invalid") };
        var response = await Create(client).Program(Guid.NewGuid(), default);
        var result = Assert.IsType<JsonElement>(Assert.IsType<OkObjectResult>(response.Result).Value);
        Assert.Equal(json, result.GetRawText());
    }

    [Fact]
    public async Task PublicationStillUsesReviewedVersionEndpointAndPreservesEngineRejection()
    {
        using var handler = new Capture("{\"code\":\"INVALID_CAP_POLICY\",\"correlationId\":\"cap-test\"}", HttpStatusCode.UnprocessableEntity);
        using var client = new HttpClient(handler) { BaseAddress = new Uri("https://engine.invalid") };
        var program = Guid.NewGuid(); var draft = Guid.NewGuid();
        var response = await Create(client).Publish(program, draft,
            JsonSerializer.SerializeToElement(new { PreviewHash = "reviewed", IdempotencyKey = "publish-once" }), default);
        Assert.Equal($"/api/v2/referrals/programs/{program:D}/drafts/{draft:D}/publish", handler.Path);
        Assert.Equal("reviewed", handler.Body.GetProperty("PreviewHash").GetString());
        var error = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(422, error.StatusCode);
        Assert.Contains("INVALID_CAP_POLICY", JsonSerializer.Serialize(error.Value));
    }

    private static decimal? Amount(string? value) => value is null ? null : decimal.Parse(value, System.Globalization.CultureInfo.InvariantCulture);
    private static decimal? ReadAmount(JsonElement value) => value.ValueKind == JsonValueKind.Null ? null : value.GetDecimal();
    private static AdminReferralsController Create(HttpClient client) => new(new ProxyHoppaRequestUseCase(
        new HoppaClient(client, Options.Create(new HoppaOptions { ApiKey = "test-key" }), new HoppaFlowLogCollector())))
        { ControllerContext = new() { HttpContext = new DefaultHttpContext() } };

    private sealed class Capture(string response, HttpStatusCode status = HttpStatusCode.OK) : HttpMessageHandler
    {
        public JsonElement Body { get; private set; }
        public string? Path { get; private set; }
        public HttpMethod? Method { get; private set; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Path = request.RequestUri!.PathAndQuery;
            Method = request.Method;
            if (request.Content is not null)
                Body = JsonSerializer.Deserialize<JsonElement>(await request.Content.ReadAsStringAsync(cancellationToken));
            return new(status) { Content = new StringContent(response, Encoding.UTF8, "application/json") };
        }
    }
}
