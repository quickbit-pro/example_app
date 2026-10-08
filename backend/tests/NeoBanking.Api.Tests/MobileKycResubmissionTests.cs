using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobileKycResubmissionTests
{
    [Theory]
    [InlineData("Interlace", "RequiredAction")]
    [InlineData("interlace", "requiredAction")]
    public async Task Resume_UsesAuthenticatedUserAndExistingHostedFlow(string providerKey, string actionKey)
    {
        var proxy = new RecordingProxy(JsonSerializer.Serialize(new Dictionary<string, object>
        {
            [providerKey] = new Dictionary<string, string> { [actionKey] = "RESUBMIT_DOCUMENTS" }
        }));
        var controller = CreateController(proxy);
        var response = await controller.ResumeVerification(default);
        Assert.IsType<OkObjectResult>(response.Result);
        Assert.Equal(new[] { "/api/v2/users/10466/kyc/detailed-status", "/api/v2/users/10466/sumsub/kyc-url" }, proxy.Paths);
        Assert.Equal("{}", proxy.PostBody);
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("{\"Interlace\":{\"RequiredAction\":\"CONTACT_SUPPORT\"}}")]
    [InlineData("{\"Interlace\":{\"RequiredAction\":\"RESUBMIT_DATA\"}}")]
    [InlineData("{\"HoppaCardKycApproved\":true}")]
    public async Task Resume_WithoutDocumentReset_DoesNotRequestLink(string json)
    {
        var proxy = new RecordingProxy(json);
        var response = await CreateController(proxy).ResumeVerification(default);
        Assert.Equal(409, Assert.IsAssignableFrom<ObjectResult>(response.Result).StatusCode);
        Assert.Single(proxy.Paths);
    }

    [Fact]
    public async Task Resume_StatusFailure_DoesNotRequestLink()
    {
        var proxy = new RecordingProxy("{}", fail: true);
        var response = await CreateController(proxy).ResumeVerification(default);
        Assert.Equal(502, Assert.IsAssignableFrom<ObjectResult>(response.Result).StatusCode);
        Assert.Single(proxy.Paths);
    }

    [Fact]
    public async Task Resume_WithoutIdentity_DoesNotCallProvider()
    {
        var proxy = new RecordingProxy("{}");
        var controller = new MobileKycController(null!, proxy)
        { ControllerContext = new ControllerContext { HttpContext = new Microsoft.AspNetCore.Http.DefaultHttpContext() } };
        await controller.ResumeVerification(default);
        Assert.Empty(proxy.Paths);
    }

    private static MobileKycController CreateController(RecordingProxy proxy) => new(null!, proxy)
    { ControllerContext = MobileIdentityTestSupport.ControllerContext(Guid.NewGuid()) };

    private sealed class RecordingProxy(string json, bool fail = false) : IProxyHoppaRequestUseCase
    {
        public List<string> Paths { get; } = [];
        public string? PostBody { get; private set; }
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command, CancellationToken cancellationToken)
        {
            Paths.Add(command.UpstreamPath);
            if (fail) return Task.FromResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError("unavailable", "Unavailable", (int)HttpStatusCode.BadGateway)));
            var body = json;
            if (command.Method == HttpMethod.Post)
            {
                PostBody = JsonSerializer.Serialize(command.Request);
                body = "{\"accessToken\":\"https://in.sumsub.com/websdk/p/existing\"}";
            }
            return Task.FromResult(ApplicationResult<JsonElement?>.Success(JsonDocument.Parse(body).RootElement.Clone()));
        }
    }
}
