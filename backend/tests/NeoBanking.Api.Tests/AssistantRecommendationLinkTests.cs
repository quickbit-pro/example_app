using System.Text.Json;
using NeoBanking.Api.Assistant;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed partial class AssistantServiceTests
{
    private static string LinkedAnswer(object? url, string scope = "hotels")
    {
        var answer = StructuredAnswer();
        var option = (Dictionary<string, object?>)((object[])answer["options"]!)[0];
        option["sourceUrl"] = url;
        return JsonSerializer.Serialize(new { scope, answer,
            searches = new[] { new { kind = "hotels", query = "Rome spa hotels" } } });
    }

    [Fact]
    public async Task RecommendationLink_UsesExactCitationAndKeepsOtherCardsWithoutLinks()
    {
        const string url = "https://www.trilussapalacehotel.it/en/?room=spa&guests=2";
        using var handler = new StubHandler(Envelope(Classification), Envelope(LinkedAnswer(url),
            [Citation(url, "Trilussa Palace website")]));
        var result = await Service(handler, new FakeQuota(), new AssistantOptions
            { Enabled = true, RecommendationLinksEnabled = true }).ChatAsync(CompanyId, UserId, Request(), default);

        Assert.True(result.IsSuccess);
        var response = result.Value!;
        Assert.Equal(Assert.Single(response.Sources), response.Answer!.Options[0].Source);
        Assert.Equal(url, response.Answer.Options[0].Source!.Url);
        Assert.Null(response.Answer.Options[1].Source);
        Assert.DoesNotContain(url, response.Reply);
        Assert.StartsWith("https://www.google.com/travel/hotels?q=", Assert.Single(response.Actions).Url);
        using var payload = JsonDocument.Parse(handler.Requests[1].Body);
        var prompt = payload.RootElement.GetProperty("messages")[0].GetProperty("content").GetString()!;
        Assert.Contains("Do not restrict recommendations to particular merchants", prompt);
        Assert.Contains("sourceUrl", prompt);
        Assert.Contains("Rank by the user's dates, budget", prompt);
    }

    [Theory]
    [InlineData("https://www.trilussapalacehotel.it/other-room")]
    [InlineData("https://www.trilussapalacehotel.it/?affiliate=invented")]
    [InlineData("https://www.trilussapalacehotel.it.evil.com/")]
    [InlineData("javascript:alert(1)")]
    [InlineData("https://127.0.0.1/")]
    [InlineData("https://user:password@www.trilussapalacehotel.it/")]
    [InlineData(42)]
    [InlineData(null)]
    public async Task RecommendationLink_UnmatchedOrMalformedReferenceDropsOnlyLink(object? url)
    {
        using var handler = new StubHandler(Envelope(Classification), Envelope(LinkedAnswer(url),
            [Citation("https://www.trilussapalacehotel.it/", "Hotel")]));
        var result = await Service(handler, new FakeQuota(), new AssistantOptions
            { Enabled = true, RecommendationLinksEnabled = true }).ChatAsync(CompanyId, UserId, Request(), default);
        Assert.True(result.IsSuccess);
        Assert.Equal(2, result.Value!.Answer!.Options.Count);
        Assert.All(result.Value.Answer.Options, option => Assert.Null(option.Source));
    }

    [Theory]
    [InlineData(true, "hotels", "hotels", false)] // No citations returned.
    [InlineData(false, "hotels", "hotels", true)] // Search off, even with provider annotations.
    [InlineData(true, "app_navigation", "hotels", true)] // Classifier suppresses links.
    [InlineData(true, "hotels", "app_navigation", true)] // Answer suppresses links.
    public async Task RecommendationLink_RequiresWebEvidenceAndTravelScope(
        bool web, string classified, string answerScope, bool citations)
    {
        const string url = "https://www.trilussapalacehotel.it/";
        using var handler = new StubHandler(Envelope(JsonSerializer.Serialize(new { scope = classified })),
            Envelope(LinkedAnswer(url, answerScope), citations ? [Citation(url, "Hotel")] : []));
        var result = await Service(handler, new FakeQuota(), new AssistantOptions
            { Enabled = true, WebSearchEnabled = web, RecommendationLinksEnabled = true })
            .ChatAsync(CompanyId, UserId, Request(), default);
        Assert.True(result.IsSuccess);
        Assert.All(result.Value!.Answer!.Options, option => Assert.Null(option.Source));
        Assert.Empty(result.Value.Sources);
        if (classified == "app_navigation" || answerScope == "app_navigation") Assert.Empty(result.Value.Actions);
    }

    [Fact]
    public async Task RecommendationLinks_DefaultOffRetainsExistingContractAndHotelSearch()
    {
        var content = JsonSerializer.Serialize(new { scope = "hotels", answer = StructuredAnswer(),
            searches = new[] { new { kind = "hotels", query = "Rome" } } });
        using var handler = new StubHandler(Envelope(Classification), Envelope(content));
        var result = await Service(handler, new FakeQuota()).ChatAsync(CompanyId, UserId, Request(), default);
        Assert.True(result.IsSuccess);
        Assert.StartsWith("https://www.booking.com/", Assert.Single(result.Value!.Actions).Url);
        Assert.DoesNotContain("Source", JsonSerializer.Serialize(result.Value.Answer));
        Assert.DoesNotContain("sourceUrl", handler.Requests[1].Body);
    }
}
