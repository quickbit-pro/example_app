using NeoBanking.Application.Email;
using Xunit;

namespace NeoBanking.Tests;

public sealed class EmailTemplateTests
{
    [Fact]
    public void RenderEncodesValuesInHtmlButNotInText()
    {
        var rendered = EmailTemplateRenderer.Render(
            "Hi {{userName}}",
            "<p>{{ userName }}</p>",
            "Hi {{USERNAME}}",
            new Dictionary<string, string> { ["userName"] = "<Rok & Co>" });

        Assert.Equal("Hi <Rok & Co>", rendered.Subject);
        Assert.Equal("<p>&lt;Rok &amp; Co&gt;</p>", rendered.HtmlBody);
        Assert.Equal("Hi <Rok & Co>", rendered.TextBody);
    }

    [Fact]
    public void RenderDropsUnknownPlaceholdersAndFlattensSubjectLines()
    {
        var rendered = EmailTemplateRenderer.Render(
            "Line one\nline two {{missing}}",
            "{{missing}}",
            string.Empty,
            new Dictionary<string, string>());

        Assert.Equal("Line one line two", rendered.Subject);
        Assert.Equal(string.Empty, rendered.HtmlBody);
    }

    [Fact]
    public void FindPlaceholdersIsCaseInsensitiveAndDistinct()
    {
        var found = EmailTemplateRenderer.FindPlaceholders("{{code}} {{ Code }}", "{{appName}}");

        Assert.Equal(["appName", "code"], found.Order(StringComparer.OrdinalIgnoreCase));
    }

    [Fact]
    public void DefaultTemplatesPassTheirOwnValidation()
    {
        foreach (var definition in EmailTemplateCatalog.All)
        {
            var errors = EmailTemplateCatalog.Validate(
                definition,
                definition.DefaultSubject,
                definition.DefaultHtmlBody,
                definition.DefaultTextBody);

            Assert.True(errors.Count == 0, $"{definition.Key}: {string.Join(" ", errors.SelectMany(pair => pair.Value))}");
        }
    }

    [Fact]
    public void DefaultTemplatesRenderWithoutLeftoverPlaceholders()
    {
        foreach (var definition in EmailTemplateCatalog.All)
        {
            var rendered = EmailTemplateRenderer.Render(
                definition.DefaultSubject,
                definition.DefaultHtmlBody,
                definition.DefaultTextBody,
                definition.SampleValues());

            Assert.DoesNotContain("{{", rendered.Subject);
            Assert.DoesNotContain("{{", rendered.HtmlBody);
            Assert.DoesNotContain("{{", rendered.TextBody);
            Assert.Contains(definition.Placeholders.First(p => p.Name == "appName").Sample, rendered.HtmlBody);
        }
    }

    [Fact]
    public void ValidationRejectsUnknownPlaceholdersAndMissingRequiredCode()
    {
        var definition = EmailTemplateCatalog.Find(EmailTemplateCatalog.PasswordReset)!;

        var errors = EmailTemplateCatalog.Validate(
            definition,
            "Reset {{nope}}",
            "<p>No code here</p>",
            "text without code");

        Assert.True(errors.ContainsKey("placeholders"));
        Assert.Contains(errors["placeholders"], message => message.Contains("{{nope}}"));
        Assert.Contains(errors["placeholders"], message => message.Contains("{{code}}"));
    }

    [Fact]
    public void ValidationRequiresSubjectAndHtml()
    {
        var definition = EmailTemplateCatalog.Find(EmailTemplateCatalog.AccountConnected)!;

        var errors = EmailTemplateCatalog.Validate(definition, "  ", "", null);

        Assert.True(errors.ContainsKey("subject"));
        Assert.True(errors.ContainsKey("htmlBody"));
    }

    [Fact]
    public void FindIsCaseInsensitiveAndTrimmed()
    {
        Assert.NotNull(EmailTemplateCatalog.Find(" Password_Reset "));
        Assert.Null(EmailTemplateCatalog.Find("unknown"));
        Assert.Null(EmailTemplateCatalog.Find(null));
    }
}
