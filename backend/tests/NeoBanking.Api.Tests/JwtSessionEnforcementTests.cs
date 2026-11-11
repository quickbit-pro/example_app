using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Auth;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class JwtSessionEnforcementTests
{
    [Theory]
    [InlineData("active", "User")]
    [InlineData("pending", "User")]
    [InlineData("active", "Admin")]
    [InlineData("active", "Support")]
    public async Task ValidLocalSessionPreservesNormalCustomerAndStaffAccess(string status, string role)
    {
        await using var f = await Fixture.Create(status);
        Assert.True((await f.Authenticate(f.Token(role))).Succeeded);
    }

    [Fact]
    public async Task PreviouslyIssuedTokenStopsWorkingImmediatelyWhenAccountIsLocked()
    {
        await using var f = await Fixture.Create();
        var token = f.Token();
        Assert.True((await f.Authenticate(token)).Succeeded);
        await f.Change(db => db.Users.SingleAsync(x => x.Id == f.UserId),
            user => user.LockedAt = DateTimeOffset.UtcNow);
        Assert.False((await f.Authenticate(token)).Succeeded);
    }

    [Theory]
    [InlineData("locked")]
    [InlineData("suspended")]
    [InlineData("disabled")]
    [InlineData("deleted")]
    [InlineData("inactive")]
    [InlineData("unknown")]
    public async Task NonActiveAccountStatusRejectsExistingTokenEvenWithoutLockedTimestamp(string status)
    {
        await using var f = await Fixture.Create();
        var token = f.Token();
        await f.Change(db => db.Users.SingleAsync(x => x.Id == f.UserId), user => user.Status = status);
        Assert.False((await f.Authenticate(token)).Succeeded);
    }

    [Fact]
    public async Task RevokingOneSessionRejectsItsTokenWithoutLoggingOutAnotherDevice()
    {
        await using var f = await Fixture.Create();
        var secondId = Guid.NewGuid();
        await using (var scope = f.Services.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<NeoBankingDbContext>();
            db.RefreshSessions.Add(f.Session(secondId));
            await db.SaveChangesAsync();
        }
        var firstToken = f.Token();
        var secondToken = f.Token(change: p => p["sid"] = secondId.ToString());
        Assert.True((await f.Authenticate(firstToken)).Succeeded);
        Assert.True((await f.Authenticate(secondToken)).Succeeded);
        await f.Change(db => db.RefreshSessions.SingleAsync(x => x.Id == f.SessionId),
            session => { session.RevokedAt = DateTimeOffset.UtcNow; session.RevocationReason = "account-locked"; });
        Assert.False((await f.Authenticate(firstToken)).Succeeded);
        Assert.True((await f.Authenticate(secondToken)).Succeeded);
    }

    [Fact]
    public async Task ExpiredRefreshSessionCannotKeepUsingUnexpiredAccessToken()
    {
        await using var f = await Fixture.Create();
        await f.Change(db => db.RefreshSessions.SingleAsync(x => x.Id == f.SessionId),
            session => session.ExpiresAt = DateTimeOffset.UtcNow.AddSeconds(-1));
        Assert.False((await f.Authenticate(f.Token())).Succeeded);
    }

    [Theory]
    [InlineData("local_user_id")]
    [InlineData("company_installation_id")]
    [InlineData("sid")]
    public async Task MissingOrMalformedSessionBoundaryClaimIsRejected(string claim)
    {
        await using var f = await Fixture.Create();
        Assert.False((await f.Authenticate(f.Token(change: p => p.Remove(claim)))).Succeeded);
        Assert.False((await f.Authenticate(f.Token(change: p => p[claim] = "invalid"))).Succeeded);
        Assert.False((await f.Authenticate(f.Token(change: p => p[claim] = Guid.Empty.ToString()))).Succeeded);
        Assert.False((await f.Authenticate(f.Token(change: p => p[claim] = new[] { p[claim], p[claim] }))).Succeeded);
    }

    [Theory]
    [InlineData("local_user_id")]
    [InlineData("company_installation_id")]
    [InlineData("sid")]
    public async Task MismatchedUserCompanyOrSessionIsRejected(string claim)
    {
        await using var f = await Fixture.Create();
        Assert.False((await f.Authenticate(f.Token(change: p => p[claim] = Guid.NewGuid().ToString()))).Succeeded);
    }

    [Fact]
    public async Task SessionCannotCrossTheUsersTenantBoundary()
    {
        await using var f = await Fixture.Create();
        await f.Change(db => db.Users.SingleAsync(x => x.Id == f.UserId),
            user => user.CompanyInstallationId = Guid.NewGuid());
        Assert.False((await f.Authenticate(f.Token())).Succeeded);
    }

    [Fact]
    public async Task ForgedSignatureIsRejectedBeforeResolvingTheDatabase()
    {
        await using var f = await Fixture.Create();
        await using var services = new ServiceCollection().AddLogging().AddOptions()
            .AddSingleton<IOptions<JwtOptions>>(Options.Create(JwtConfiguration()))
            .AddAuthentication(AuthenticationSchemeNames.Bearer)
            .AddScheme<AuthenticationSchemeOptions, JwtBearerAuthenticationHandler>(AuthenticationSchemeNames.Bearer, _ => { })
            .Services.BuildServiceProvider();
        var token = f.Token();
        var signatureStart = token.LastIndexOf('.') + 1;
        token = token[..signatureStart] + (token[signatureStart] == 'A' ? "B" : "A") + token[(signatureStart + 1)..];
        // No DbContext is registered; an attempted database lookup would throw.
        Assert.False((await Authenticate(services, token)).Succeeded);
    }

    private const string SigningKey = "tests-only-unique-signing-key-at-least-32-characters";
    private static JwtOptions JwtConfiguration() => new()
    {
        Issuer = "session-tests",
        Audience = "session-tests",
        SigningKey = SigningKey,
        ClockSkewSeconds = 0
    };

    private static async Task<AuthenticateResult> Authenticate(ServiceProvider services, string token)
    {
        await using var scope = services.CreateAsyncScope();
        var context = new DefaultHttpContext { RequestServices = scope.ServiceProvider };
        context.Request.Headers.Authorization = "Bearer " + token;
        return await context.AuthenticateAsync(AuthenticationSchemeNames.Bearer);
    }

    private sealed class Fixture(ServiceProvider services, Guid companyId, Guid userId, Guid sessionId) : IAsyncDisposable
    {
        public ServiceProvider Services { get; } = services;
        public Guid CompanyId { get; } = companyId;
        public Guid UserId { get; } = userId;
        public Guid SessionId { get; } = sessionId;

        public static async Task<Fixture> Create(string status = "active")
        {
            var name = Guid.NewGuid().ToString();
            var collection = new ServiceCollection().AddLogging().AddOptions()
                .AddSingleton<IOptions<JwtOptions>>(Options.Create(JwtConfiguration()))
                .AddDbContext<NeoBankingDbContext>(o => o.UseInMemoryDatabase(name));
            collection.AddAuthentication(AuthenticationSchemeNames.Bearer)
                .AddScheme<AuthenticationSchemeOptions, JwtBearerAuthenticationHandler>(AuthenticationSchemeNames.Bearer, _ => { });
            var f = new Fixture(collection.BuildServiceProvider(), Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
            await using var scope = f.Services.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<NeoBankingDbContext>();
            db.Users.Add(new ApplicationUser { Id = f.UserId, CompanyInstallationId = f.CompanyId,
                Email = "member@example.test", EmailNormalized = "MEMBER@EXAMPLE.TEST", Status = status });
            db.RefreshSessions.Add(f.Session(f.SessionId));
            await db.SaveChangesAsync();
            return f;
        }

        public RefreshSession Session(Guid id) => new()
        {
            Id = id, UserId = UserId, CompanyInstallationId = CompanyId,
            TokenHash = "test-hash-" + id, ExpiresAt = DateTimeOffset.UtcNow.AddDays(30)
        };

        public async Task Change<T>(Func<NeoBankingDbContext, Task<T>> find, Action<T> change)
        {
            await using var scope = Services.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<NeoBankingDbContext>();
            change(await find(db));
            await db.SaveChangesAsync();
        }

        public string Token(string role = "User", Action<Dictionary<string, object?>>? change = null)
        {
            var now = DateTimeOffset.UtcNow;
            var payload = new Dictionary<string, object?>
            {
                ["iss"] = "session-tests", ["aud"] = "session-tests", ["sub"] = "1528",
                ["local_user_id"] = UserId.ToString(), ["company_installation_id"] = CompanyId.ToString(),
                ["sid"] = SessionId.ToString(), ["role"] = new[] { role },
                ["iat"] = now.ToUnixTimeSeconds(), ["nbf"] = now.AddSeconds(-1).ToUnixTimeSeconds(),
                ["exp"] = now.AddHours(48).ToUnixTimeSeconds()
            };
            change?.Invoke(payload);
            var header = Encode(JsonSerializer.SerializeToUtf8Bytes(new { alg = "HS256", typ = "JWT" }));
            var body = Encode(JsonSerializer.SerializeToUtf8Bytes(payload));
            var signed = header + "." + body;
            return signed + "." + Encode(HMACSHA256.HashData(Encoding.UTF8.GetBytes(SigningKey), Encoding.ASCII.GetBytes(signed)));
        }

        public Task<AuthenticateResult> Authenticate(string token) => JwtSessionEnforcementTests.Authenticate(Services, token);
        public ValueTask DisposeAsync() => Services.DisposeAsync();
        private static string Encode(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }
}
