using System.Net.Http;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Cards;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Cards;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobileCardsControllerTests
{
    [Fact]
    public async Task ValidateDiscount_UsesSessionIdentityAndForwardsPrices()
    {
        var proxy = new RecordingProxy { Responder = _ => Json("""{"isValid":true,"discountType":"fixed","buyDiscountFixed":3,"monthlyDiscountFixed":0,"yearlyDiscountFixed":10}""") };
        var response = await CreateController(proxy).ValidateDiscountCode(
            new() { Code = " save " }, CancellationToken.None);
        var ok = Assert.IsType<OkObjectResult>(response.Result);
        var prices = Assert.IsType<JsonElement>(ok.Value);
        Assert.Equal(3, prices.GetProperty("buyDiscountFixed").GetInt32());
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("/api/v2/discount-codes/validate", request.Path);
        Assert.Equal(10466, request.Body!.Value.GetProperty("UserId").GetInt32());
        Assert.Equal("SAVE", request.Body.Value.GetProperty("Code").GetString());
    }

    [Theory]
    [InlineData(false, "SAVE", 401)]
    [InlineData(true, " ", 400)]
    public async Task ValidateDiscount_RejectsMissingIdentityOrCode(bool identity, string code, int status)
    {
        var proxy = new RecordingProxy();
        var response = await CreateController(proxy, includeIdentity: identity).ValidateDiscountCode(
            new() { Code = code }, CancellationToken.None);
        Assert.Equal(status, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Empty(proxy.Requests);
    }

    [Fact]
    public async Task CreateCard_PreservesDiscountThroughPhoneEnrichment()
    {
        var proxy = new RecordingProxy();
        var db = CreateDatabase();
        var user = await SeedUserAsync(db, "+386 40 123 456");
        var response = await CreateController(proxy, dbContext: db, localUserId: user.Id).CreateCard(
            new() { CardTypeId = 326, DiscountCode = "SAVE" }, CancellationToken.None);
        Assert.IsType<OkObjectResult>(response.Result);
        Assert.Equal("SAVE", Assert.Single(proxy.Requests).Body!.Value.GetProperty("DiscountCode").GetString());
    }

    [Fact]
    public async Task GetWidget_ProxiesThePublicCardWidgetContract()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);

        var response = await controller.GetWidget("42", CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Get, request.Method);
        Assert.Equal("/api/v2/cards/42/widget", request.Path);
        Assert.Equal("10466", request.Query["userId"]);
        Assert.Null(request.Body);
    }

    [Fact]
    public async Task GetWidget_RejectsRequestsWithoutHoppaIdentity()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy, includeIdentity: false);

        var response = await controller.GetWidget("42", CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status401Unauthorized, problem.StatusCode);
        Assert.Empty(proxy.Requests);
    }

    [Fact]
    public async Task CreateCard_UsesTheLocalPhoneNumberWithoutAskingHoppa()
    {
        var proxy = new RecordingProxy();
        var dbContext = CreateDatabase();
        var user = await SeedUserAsync(dbContext, "+386 40 123 456");
        var controller = CreateController(proxy, dbContext: dbContext, localUserId: user.Id);

        var response = await controller.CreateCard(new CreateCardRequestDto { CardTypeId = 326, Nickname = "New card" }, CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal("/api/v2/cards", request.Path);
        Assert.Equal("+38640123456", request.Body!.Value.GetProperty("Phone").GetString());
        Assert.Equal("386", request.Body.Value.GetProperty("PhoneCode").GetString());
    }

    [Fact]
    public async Task CreateCard_FallsBackToTheHoppaProfilePhoneAndRemembersIt()
    {
        var proxy = new RecordingProxy
        {
            Responder = path => path == "/api/v2/users/10466"
                ? Json("""{"id":10466,"email":"user@example.com","phone":"+491782686605"}""")
                : null
        };
        var dbContext = CreateDatabase();
        var user = await SeedUserAsync(dbContext, phoneNumber: null);
        var controller = CreateController(proxy, dbContext: dbContext, localUserId: user.Id);

        var response = await controller.CreateCard(new CreateCardRequestDto { CardTypeId = 326, Nickname = "New card" }, CancellationToken.None);

        Assert.IsType<OkObjectResult>(response.Result);
        Assert.Equal(2, proxy.Requests.Count);
        Assert.Equal(HttpMethod.Get, proxy.Requests[0].Method);
        Assert.Equal("/api/v2/users/10466", proxy.Requests[0].Path);
        var order = proxy.Requests[1];
        Assert.Equal("/api/v2/cards", order.Path);
        Assert.Equal("+491782686605", order.Body!.Value.GetProperty("Phone").GetString());
        Assert.Equal("49", order.Body.Value.GetProperty("PhoneCode").GetString());

        var stored = await dbContext.Users.AsNoTracking().SingleAsync(candidate => candidate.Id == user.Id);
        Assert.Equal("+491782686605", stored.PhoneNumber);
    }

    [Fact]
    public async Task CreateCard_RefusesTheOrderWhenNoPhoneNumberExists()
    {
        var proxy = new RecordingProxy
        {
            Responder = path => path == "/api/v2/users/10466"
                ? Json("""{"id":10466,"email":"user@example.com","phone":null}""")
                : null
        };
        var dbContext = CreateDatabase();
        var user = await SeedUserAsync(dbContext, phoneNumber: null);
        var controller = CreateController(proxy, dbContext: dbContext, localUserId: user.Id);

        var response = await controller.CreateCard(new CreateCardRequestDto { CardTypeId = 326, Nickname = "New card" }, CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status422UnprocessableEntity, problem.StatusCode);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal("/api/v2/users/10466", request.Path);
        Assert.DoesNotContain(proxy.Requests, candidate => candidate.Path == "/api/v2/cards");
    }

    [Fact]
    public async Task CreateCard_RefusesTheOrderWhenTheStoredPhoneNumberIsInvalid()
    {
        var proxy = new RecordingProxy();
        var dbContext = CreateDatabase();
        var user = await SeedUserAsync(dbContext, "+4912");
        var controller = CreateController(proxy, dbContext: dbContext, localUserId: user.Id);

        var response = await controller.CreateCard(new CreateCardRequestDto { CardTypeId = 326, Nickname = "New card" }, CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status422UnprocessableEntity, problem.StatusCode);
        var details = Assert.IsType<ProblemDetails>(problem.Value);
        Assert.Contains("not a valid number", details.Detail ?? details.Title);
        Assert.Empty(proxy.Requests);
    }

    [Fact]
    public async Task CreateCard_ExplainsInsufficientFundsWithTheRequiredAmount()
    {
        var proxy = new RecordingProxy
        {
            FailureResponder = path => path == "/api/v2/cards"
                ? new ApplicationError(
                    "mobile.cards.create.failed",
                    "We could not create card.",
                    StatusCodes.Status400BadRequest,
                    """{"success":false,"cardTypeId":260,"totalCost":5.00,"currency":"USD","errorCode":"PAYMENT_REQUIRED","errorMessage":"Insufficient funds. Required amount: 5.00 USD. Please top up your account."}""")
                : null
        };
        var dbContext = CreateDatabase();
        var user = await SeedUserAsync(dbContext, "+386 40 123 456");
        var controller = CreateController(proxy, dbContext: dbContext, localUserId: user.Id);

        var response = await controller.CreateCard(new CreateCardRequestDto { CardTypeId = 260, Nickname = "New card" }, CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status422UnprocessableEntity, problem.StatusCode);
        var details = Assert.IsType<ProblemDetails>(problem.Value);
        Assert.Equal(CardOrderFailures.InsufficientFundsCode, details.Extensions["code"]);
        Assert.Contains("5.00 USD", details.Title);
        Assert.Contains("unload a card", details.Title);
    }

    [Fact]
    public async Task CreateCard_PassesOtherIssuerRefusalsThroughUnchanged()
    {
        var proxy = new RecordingProxy
        {
            FailureResponder = path => path == "/api/v2/cards"
                ? new ApplicationError(
                    "mobile.cards.create.failed",
                    "We could not create card.",
                    StatusCodes.Status400BadRequest,
                    """{"errorCode":"CARD_LIMIT_REACHED","errorMessage":"Maximum number of cards reached."}""")
                : null
        };
        var dbContext = CreateDatabase();
        var user = await SeedUserAsync(dbContext, "+386 40 123 456");
        var controller = CreateController(proxy, dbContext: dbContext, localUserId: user.Id);

        var response = await controller.CreateCard(new CreateCardRequestDto { CardTypeId = 260, Nickname = "New card" }, CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status400BadRequest, problem.StatusCode);
        var details = Assert.IsType<ProblemDetails>(problem.Value);
        Assert.Equal("mobile.cards.create.failed", details.Extensions["code"]);
    }

    [Fact]
    public async Task UpdateAutoFreeze_ForwardsTheSwitchToTheIssuersAutoLock()
    {
        var proxy = new RecordingProxy
        {
            Responder = path => path == "/api/v2/cards/42/auto-lock"
                ? Json("""{"Success":true,"Message":"Auto lock enabled","AutoLockEnabled":true,"AutoLockActiveUntil":"2026-09-11T17:10:00Z"}""")
                : null
        };
        var controller = CreateController(proxy);

        var response = await controller.UpdateAutoFreeze(
            "42", new UpdateCardAutoFreezeRequestDto { Enabled = true }, CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);
        var body = Assert.IsType<CardAutoFreezeResponseDto>(ok.Value);
        Assert.True(body.Enabled);
        Assert.Equal(new DateTimeOffset(2026, 9, 11, 17, 10, 0, TimeSpan.Zero), body.ActiveUntil);
        Assert.Contains("10 minutes", body.Message);
        var request = Assert.Single(proxy.Requests);
        Assert.Equal(HttpMethod.Put, request.Method);
        Assert.Equal("/api/v2/cards/42/auto-lock", request.Path);
        Assert.Equal("10466", request.Query["userId"]);
        Assert.True(request.Body!.Value.GetProperty("Enabled").GetBoolean());
    }

    [Fact]
    public async Task UpdateAutoFreeze_TrustsTheIssuersAnswerOverTheRequest()
    {
        var proxy = new RecordingProxy
        {
            Responder = path => path == "/api/v2/cards/42/auto-lock"
                ? Json("""{"Success":true,"AutoLockEnabled":false}""")
                : null
        };
        var controller = CreateController(proxy);

        var response = await controller.UpdateAutoFreeze(
            "42", new UpdateCardAutoFreezeRequestDto { Enabled = true }, CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);
        var body = Assert.IsType<CardAutoFreezeResponseDto>(ok.Value);
        Assert.False(body.Enabled);
        Assert.Equal("Auto freeze is off.", body.Message);
    }

    [Fact]
    public async Task UpdateAutoFreeze_PassesTheIssuersRefusalThrough()
    {
        var proxy = new RecordingProxy
        {
            FailureResponder = path => path == "/api/v2/cards/42/auto-lock"
                ? new ApplicationError("hoppa.request_failed", "Card not found", StatusCodes.Status404NotFound)
                : null
        };
        var controller = CreateController(proxy);

        var response = await controller.UpdateAutoFreeze(
            "42", new UpdateCardAutoFreezeRequestDto { Enabled = false }, CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status404NotFound, problem.StatusCode);
    }

    [Fact]
    public async Task UpdateAutoFreeze_RejectsAnEmptyChoice()
    {
        var proxy = new RecordingProxy();
        var controller = CreateController(proxy);

        var response = await controller.UpdateAutoFreeze(
            "42", new UpdateCardAutoFreezeRequestDto(), CancellationToken.None);

        var problem = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status400BadRequest, problem.StatusCode);
        Assert.Empty(proxy.Requests);
    }

    [Fact]
    public async Task GetControls_ReportsTheIssuersAutoFreezeSwitch()
    {
        var proxy = new RecordingProxy
        {
            Responder = path => path == "/api/v2/cards/42"
                ? Json("""{"Id":42,"Status":"ACTIVE","AutoLockEnabled":true,"AutoLockActiveUntil":"2026-09-11T17:10:00Z","SupportedActions":["freeze"]}""")
                : null
        };
        var controller = CreateController(proxy);

        var response = await controller.GetControls("42", CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);
        var element = Assert.IsType<JsonElement>(ok.Value);
        Assert.True(element.GetProperty("AutoFreezeEnabled").GetBoolean());
        Assert.Equal("2026-09-11T17:10:00+00:00", element.GetProperty("AutoFreezeActiveUntil").GetString());
        Assert.True(element.GetProperty("CanFreeze").GetBoolean());
    }

    private static NeoBankingDbContext CreateDatabase()
    {
        return new NeoBankingDbContext(
            new DbContextOptionsBuilder<NeoBankingDbContext>()
                .UseInMemoryDatabase(Guid.NewGuid().ToString("N"))
                .Options);
    }

    private static async Task<ApplicationUser> SeedUserAsync(NeoBankingDbContext dbContext, string? phoneNumber)
    {
        var user = new ApplicationUser
        {
            CompanyInstallationId = Guid.NewGuid(),
            Email = "user@example.com",
            EmailNormalized = "USER@EXAMPLE.COM",
            PhoneNumber = phoneNumber,
            Status = "active",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        dbContext.Users.Add(user);
        await dbContext.SaveChangesAsync();
        dbContext.ChangeTracker.Clear();
        return user;
    }

    private static MobileCardsController CreateController(
        RecordingProxy proxy,
        bool includeIdentity = true,
        NeoBankingDbContext? dbContext = null,
        Guid? localUserId = null)
    {
        var claims = new List<Claim>();
        if (includeIdentity)
        {
            claims.Add(new Claim("hoppa_user_id", "10466"));
        }
        if (localUserId is not null)
        {
            claims.Add(new Claim("local_user_id", localUserId.Value.ToString()));
        }
        dbContext ??= new NeoBankingDbContext(
            new DbContextOptionsBuilder<NeoBankingDbContext>().Options);

        return new MobileCardsController(proxy, dbContext)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(claims, "test"))
                }
            }
        };
    }

    private static JsonElement Json(string value)
    {
        using var document = JsonDocument.Parse(value);
        return document.RootElement.Clone();
    }

    private sealed class RecordingProxy : IProxyHoppaRequestUseCase
    {
        public List<RecordedRequest> Requests { get; } = [];

        /// <summary>Optional canned response per upstream path; other paths answer <c>{"success":true}</c>.</summary>
        public Func<string, JsonElement?>? Responder { get; init; }

        /// <summary>Optional canned failure per upstream path, checked before <see cref="Responder"/>.</summary>
        public Func<string, ApplicationError?>? FailureResponder { get; init; }

        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(
            ProxyHoppaRequestCommand<TRequest> command,
            CancellationToken cancellationToken)
        {
            JsonElement? body = command.Request is null
                ? null
                : JsonSerializer.SerializeToElement(command.Request);
            Requests.Add(new RecordedRequest(
                command.Method,
                command.UpstreamPath,
                command.Query,
                body));

            var failure = FailureResponder?.Invoke(command.UpstreamPath);
            if (failure is not null)
            {
                return Task.FromResult(ApplicationResult<JsonElement?>.Failure(failure));
            }

            return Task.FromResult(ApplicationResult<JsonElement?>.Success(
                Responder?.Invoke(command.UpstreamPath) ?? Json("""{"success":true}""")));
        }
    }

    private sealed record RecordedRequest(
        HttpMethod Method,
        string Path,
        IReadOnlyDictionary<string, string?> Query,
        JsonElement? Body);
}
