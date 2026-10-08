namespace NeoBanking.Api.Assistant;

/// <summary>Provider-enforced shapes; local validation remains the final boundary.</summary>
internal static class AssistantResponseFormats
{
    public static object Classifier => Format("assistant_scope", Shape(new()
    {
        ["scope"] = Choice("travel", "flights", "hotels", "dining", "activities", "airport", "app_navigation", "spending", "out_of_scope")
    }));

    public static object Answer(bool recommendationLinks = false, bool spending = false)
    {
        Dictionary<string, object> option = new()
        {
            ["title"] = Text(80),
            ["highlights"] = new { type = "array", items = Text(160), minItems = 1, maxItems = 2 },
            ["details"] = Text(600, nullable: true)
        };
        if (recommendationLinks && !spending) option["sourceUrl"] = Text(2048, nullable: true);
        var answer = Shape(new()
        {
            ["title"] = Text(80), ["summary"] = Text(240),
            ["options"] = new { type = "array", items = Shape(option), maxItems = 3 },
            ["nextStep"] = Text(200, nullable: true)
        });
        Dictionary<string, object> root = new()
        {
            ["scope"] = spending ? Choice("spending", "out_of_scope")
                : Choice("travel", "flights", "hotels", "dining", "activities", "airport", "app_navigation", "out_of_scope"),
            // Refusals may omit content while retaining the same strict root shape.
            ["answer"] = new { anyOf = new object[] { answer, new { type = "null" } } }
        };
        if (!spending) root["searches"] = new
        {
            type = "array", maxItems = 3,
            items = Shape(new() { ["kind"] = Choice("flights", "hotels", "maps"), ["query"] = Text(160) })
        };
        return Format(spending ? "assistant_spending" : "assistant_travel", Shape(root));
    }

    private static object Format(string name, object schema) => new
    {
        type = "json_schema", json_schema = new { name, strict = true, schema }
    };

    private static object Shape(Dictionary<string, object> properties) => new
    {
        type = "object", properties, required = properties.Keys.ToArray(), additionalProperties = false
    };

    private static object Choice(params string[] values) => new { type = "string", @enum = values };

    private static object Text(int maximum, bool nullable = false) => new Dictionary<string, object>
    {
        ["type"] = nullable ? new[] { "string", "null" } : (object)"string",
        ["minLength"] = 1, ["maxLength"] = maximum
    };
}
