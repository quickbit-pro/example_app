using System.Net;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobileWalletsControllerTests
{
    [Fact]
    public async Task ListWallets_ReturnsAssets_WhenWalletProviderFails()
    {
        var walletsError = Failure(HttpStatusCode.InternalServerError);
        var assetsPayload = Json("""{"data":[{"Currency":"USD","Balance":"27.08"}]}""");
        var proxy = new StubProxy(walletsError, ApplicationResult<JsonElement?>.Success(assetsPayload));
        var controller = CreateController(proxy);

        var response = await controller.ListWallets(
            null, null, null, null, null, null, null, CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);
        var body = Assert.IsType<JsonElement>(ok.Value);
        Assert.Equal("USD", body.GetProperty("data")[0].GetProperty("Currency").GetString());
        Assert.Equal(
            ["/api/v2/users/10466/wallets", "/api/v2/users/10466/assets"],
            proxy.Paths);
    }

    [Fact]
    public async Task ListWallets_DoesNotFallback_ForClientErrors()
    {
        var proxy = new StubProxy(Failure(HttpStatusCode.BadRequest));
        var controller = CreateController(proxy);

        var response = await controller.ListWallets(
            null, null, null, null, null, null, null, CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status400BadRequest, problem.StatusCode);
        Assert.Equal(["/api/v2/users/10466/wallets"], proxy.Paths);
    }

    [Fact]
    public async Task ListWallets_PreservesWalletError_WhenFallbackAlsoFails()
    {
        var proxy = new StubProxy(
            Failure(HttpStatusCode.InternalServerError, "wallets.failed"),
            Failure(HttpStatusCode.BadGateway, "assets.failed"));
        var controller = CreateController(proxy);

        var response = await controller.ListWallets(
            null, null, null, null, null, null, null, CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status500InternalServerError, problem.StatusCode);
        var details = Assert.IsType<ProblemDetails>(problem.Value);
        Assert.Equal("wallets.failed", details.Extensions["code"]);
    }

    private static MobileWalletsController CreateController(StubProxy proxy)
    {
        return new MobileWalletsController(proxy)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(
                        new ClaimsIdentity([new Claim("hoppa_user_id", "10466")], "test"))
                }
            }
        };
    }

    private static ApplicationResult<JsonElement?> Failure(
        HttpStatusCode status,
        string code = "wallets.failed")
    {
        return ApplicationResult<JsonElement?>.Failure(
            new ApplicationError(code, "Upstream request failed.", (int)status));
    }

    private static JsonElement Json(string value)
    {
        using var document = JsonDocument.Parse(value);
        return document.RootElement.Clone();
    }

    private sealed class StubProxy(params ApplicationResult<JsonElement?>[] results)
        : IProxyHoppaRequestUseCase
    {
        private readonly Queue<ApplicationResult<JsonElement?>> _results = new(results);

        public List<string> Paths { get; } = [];

        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(
            ProxyHoppaRequestCommand<TRequest> command,
            CancellationToken cancellationToken)
        {
            Paths.Add(command.UpstreamPath);
            return Task.FromResult(_results.Dequeue());
        }
    }
}
