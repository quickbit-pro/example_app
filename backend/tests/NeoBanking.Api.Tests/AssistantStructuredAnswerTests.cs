using System.Text.Json;
using NeoBanking.Api.Assistant;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed partial class AssistantServiceTests
{
    private static Dictionary<string, object?> StructuredAnswer() => new()
    {
        ["title"] = "Quiet stays in Rome",
        ["summary"] = "Two options with different spa experiences.",
        ["options"] = new object[]
        {
            new Dictionary<string, object?>
            {
                ["title"] = "Trilussa Palace",
                ["highlights"] = new[] { "Private spa sessions", "Trastevere location" },
                ["details"] = "Check the selected room rate for cancellation terms."
            },
            new Dictionary<string, object?>
            {
                ["title"] = "The Code Hotel",
                ["highlights"] = new[] { "Central location" }
            }
        },
        ["nextStep"] = "What are your dates and party size?"
    };

    [Fact]
    public async Task StructuredAnswer_ReturnsBoundedCardsAndComposesLegacyReplyWithOneDisclosure()
    {
        var content = JsonSerializer.Serialize(new { scope = "hotels", answer = StructuredAnswer(), searches = Array.Empty<object>(),
            reply = "Untrusted duplicate prose at https://discard.example" });
        using var handler = new StubHandler(Envelope(Classification), Envelope(content,
            [Citation("https://www.turismoroma.it/en", "Rome tourism")]));
        var quota = new FakeQuota();

        var result = await Service(handler, quota).ChatAsync(CompanyId, UserId, Request(), default);

        Assert.True(result.IsSuccess);
        var response = result.Value!;
        Assert.Equal("web_sources", response.Verification);
        Assert.Equal("Quiet stays in Rome", response.Answer!.Title);
        Assert.Equal(2, response.Answer.Options.Count);
        Assert.Equal("Trastevere location", response.Answer.Options[0].Highlights[1]);
        Assert.Null(response.Answer.Options[1].Details);
        Assert.Contains("Trilussa Palace\n• Private spa sessions\n• Trastevere location", response.Reply);
        Assert.Contains("Check the selected room rate for cancellation terms.", response.Reply);
        Assert.Contains("What are your dates and party size?", response.Reply);
        Assert.DoesNotContain("Untrusted duplicate", response.Reply);
        const string note = "Found on the web. Confirm final prices and availability with the provider.";
        Assert.Equal(2, response.Reply.Split(note).Length);
        Assert.DoesNotContain(note, JsonSerializer.Serialize(response.Answer));
        Assert.Single(quota.Released);
    }

    [Fact]
    public async Task StructuredClarification_CanHaveNoOptionsOrOptionalText()
    {
        var content = JsonSerializer.Serialize(new { scope = "travel", answer = new
        {
            title = "Your next escape", summary = "Which dates work for you?", options = Array.Empty<object>(),
            nextStep = (string?)null
        } });
        using var handler = new StubHandler(Envelope(Classification), Envelope(content));

        var result = await Service(handler, new FakeQuota()).ChatAsync(CompanyId, UserId, Request(), default);

        Assert.True(result.IsSuccess);
        Assert.Empty(result.Value!.Answer!.Options);
        Assert.Null(result.Value.Answer.NextStep);
        Assert.Equal("planning", result.Value.Verification);
    }

    [Fact]
    public async Task StructuredNavigation_DoesNotAppendTravelDisclaimerOrExposeLinks()
    {
        var content = JsonSerializer.Serialize(new { scope = "app_navigation", answer = new
        {
            title = "Your cards", summary = "Open Cards to see your cards.", options = Array.Empty<object>()
        }, searches = new[] { new { kind = "maps", query = "Bank support" } } });
        using var handler = new StubHandler(Envelope("""{"scope":"app_navigation"}"""), Envelope(content,
            [Citation("https://www.turismoroma.it/en", "Unexpected citation")]));

        var result = await Service(handler, new FakeQuota()).ChatAsync(CompanyId, UserId, Request(), default);

        Assert.True(result.IsSuccess);
        Assert.NotNull(result.Value!.Answer);
        Assert.Equal("Your cards\n\nOpen Cards to see your cards.", result.Value.Reply);
        Assert.Empty(result.Value.Actions);
        Assert.Empty(result.Value.Sources);
        Assert.Null(result.Value.Verification);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task LegacyReply_StillWorksWhenStructuredAnswerIsAbsentOrNull(bool explicitNull)
    {
        var content = explicitNull
            ? """{"scope":"travel","answer":null,"reply":"Consider Rome."}"""
            : """{"scope":"travel","reply":"Consider Rome."}""";
        using var handler = new StubHandler(Envelope(Classification), Envelope(content));

        var result = await Service(handler, new FakeQuota()).ChatAsync(CompanyId, UserId, Request(), default);

        Assert.True(result.IsSuccess);
        Assert.Null(result.Value!.Answer);
        Assert.StartsWith("Consider Rome.", result.Value.Reply);
        Assert.Equal("planning", result.Value.Verification);
    }

    [Theory]
    [InlineData("app_navigation", "app_navigation")]
    [InlineData("app_navigation", "travel")]
    [InlineData("travel", "app_navigation")]
    public async Task Verification_UsesServerScopeRatherThanModelAssertion(string classifierScope, string answerScope)
    {
        var content = JsonSerializer.Serialize(new { scope = answerScope, answer = StructuredAnswer(),
            verification = "web_sources", searches = Array.Empty<object>() });
        using var handler = new StubHandler(Envelope(JsonSerializer.Serialize(new { scope = classifierScope })),
            Envelope(content, [Citation("https://www.turismoroma.it/en", "Unexpected source")]));

        var result = await Service(handler, new FakeQuota()).ChatAsync(CompanyId, UserId, Request(), default);

        Assert.True(result.IsSuccess);
        Assert.Null(result.Value!.Verification);
        Assert.Empty(result.Value.Sources);
        Assert.False(result.Value.WebSearchUsed);
    }

    [Fact]
    public async Task Verification_IsNullForRefusal()
    {
        using var handler = new StubHandler(Envelope("""{"scope":"out_of_scope","verification":"web_sources"}"""));
        var result = await Service(handler, new FakeQuota()).ChatAsync(CompanyId, UserId, Request(), default);
        Assert.True(result.IsSuccess);
        Assert.True(result.Value!.Refused);
        Assert.Null(result.Value.Verification);
    }

    [Fact]
    public async Task Verification_CannotBeClaimedByModelWithoutValidSources()
    {
        var content = JsonSerializer.Serialize(new { scope = "travel", answer = StructuredAnswer(), verification = "web_sources" });
        using var handler = new StubHandler(Envelope(Classification), Envelope(content));
        var result = await Service(handler, new FakeQuota()).ChatAsync(CompanyId, UserId, Request(), default);
        Assert.True(result.IsSuccess);
        Assert.Equal("planning", result.Value!.Verification);
    }

    public static IEnumerable<object[]> InvalidStructuredAnswers()
    {
        foreach (var field in new[] { "title", "summary", "options" })
        {
            var answer = StructuredAnswer();
            answer.Remove(field);
            yield return [JsonSerializer.Serialize(answer)];
        }
        foreach (var (field, limit) in new[] { ("title", 80), ("summary", 240), ("nextStep", 200) })
        {
            foreach (var invalid in new object?[] { "", " \n ", 123, new string('x', limit + 1) })
            {
                var answer = StructuredAnswer();
                answer[field] = invalid;
                yield return [JsonSerializer.Serialize(answer)];
            }
        }
        foreach (var invalid in new object?[] { null, 1, "text", new object[4] })
        {
            var answer = StructuredAnswer();
            answer["options"] = invalid;
            yield return [JsonSerializer.Serialize(answer)];
        }
        foreach (var (field, invalid) in new (string, object?)[]
        {
            ("title", null), ("title", ""), ("title", new string('x', 81)),
            ("highlights", null), ("highlights", "one fact"), ("highlights", Array.Empty<string>()),
            ("highlights", new[] { "one", "two", "three" }), ("highlights", new object[] { 1 }),
            ("highlights", new[] { "" }), ("highlights", new[] { new string('x', 161) }),
            ("details", " "), ("details", 123), ("details", new string('x', 601)),
            ("url", "https://untrusted.example")
        })
        {
            var answer = StructuredAnswer();
            var option = (Dictionary<string, object?>)((object[])answer["options"]!)[0];
            option[field] = invalid;
            yield return [JsonSerializer.Serialize(answer)];
        }
        foreach (var unsafeText in new[] { "https://untrusted.example", "example://transfer", "www.untrusted.example", "[Book](example.com)", "<a href='example.com'>Book</a>", "Unsafe\0text" })
        {
            foreach (var field in new[] { "title", "summary", "nextStep", "optionTitle", "highlights", "details" })
            {
                var answer = StructuredAnswer();
                var option = (Dictionary<string, object?>)((object[])answer["options"]!)[0];
                if (field == "optionTitle") option["title"] = unsafeText;
                else if (field == "highlights") option[field] = new[] { unsafeText };
                else if (field == "details") option[field] = unsafeText;
                else answer[field] = unsafeText;
                yield return [JsonSerializer.Serialize(answer)];
            }
        }
        yield return ["[]"];
        yield return ["\"text\""];
        yield return ["""{"title":"One","title":"Two","summary":"Summary","options":[]}"""];
        yield return ["""{"title":"One","summary":"Summary","options":[],"script":"ignored code"}"""];
        yield return ["""{"title":"One","summary":"Summary","options":[{"title":"Hotel","highlights":["Fact"],"details":null,"details":"Duplicate"}]}"""];
        yield return [JsonSerializer.Serialize(MaximumAnswer(2401))];
    }

    [Theory]
    [MemberData(nameof(InvalidStructuredAnswers))]
    public async Task InvalidStructuredAnswer_FailsClosedEvenWithValidLegacyReply(string answer)
    {
        var content = "{\"scope\":\"travel\",\"reply\":\"Legacy fallback\",\"answer\":" + answer + "}";
        using var handler = new StubHandler(Envelope(Classification), Envelope(content));
        var quota = new FakeQuota();

        var result = await Service(handler, quota).ChatAsync(CompanyId, UserId, Request(), default);

        Assert.False(result.IsSuccess);
        Assert.Equal("assistant.provider_unavailable", result.Error!.Code);
        Assert.Null(result.Value);
        Assert.Single(quota.Released);
    }

    [Fact]
    public async Task MaximumStructuredText_IsAcceptedAndLegacyReplyFitsHistoryLimit()
    {
        var content = JsonSerializer.Serialize(new { scope = "travel", answer = MaximumAnswer(2400) });
        using var handler = new StubHandler(Envelope(Classification), Envelope(content));

        var result = await Service(handler, new FakeQuota()).ChatAsync(CompanyId, UserId, Request(), default);

        Assert.True(result.IsSuccess);
        Assert.Equal(3, result.Value!.Answer!.Options.Count);
        Assert.True(result.Value.Reply.Length <= AssistantService.MaxHistoryCharacters);
    }

    private static object MaximumAnswer(int total) => new
    {
        title = new string('x', 80), summary = new string('x', 240), nextStep = new string('x', 200),
        options = Enumerable.Range(0, 3).Select(index => new
        {
            title = new string('x', 80), highlights = new[] { new string('x', 160), new string('x', 160) },
            details = index switch { 0 => new string('x', 600), 1 => new string('x', total - 2320), _ => (string?)null }
        }).ToArray()
    };
}
