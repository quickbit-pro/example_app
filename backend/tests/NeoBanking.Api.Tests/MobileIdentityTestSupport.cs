using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

internal static class MobileIdentityTestSupport
{
    public static NeoBankingDbContext CreateDatabase()
    {
        return new NeoBankingDbContext(
            new DbContextOptionsBuilder<NeoBankingDbContext>()
                .UseInMemoryDatabase(Guid.NewGuid().ToString("N"))
                .Options);
    }

    public static async Task<ApplicationUser> SeedUserAsync(NeoBankingDbContext dbContext)
    {
        var user = new ApplicationUser
        {
            CompanyInstallationId = Guid.NewGuid(),
            Email = "user@example.com",
            EmailNormalized = "USER@EXAMPLE.COM",
            DisplayName = "Customer",
            Status = "active",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        dbContext.Users.Add(user);
        await dbContext.SaveChangesAsync();
        dbContext.ChangeTracker.Clear();
        return user;
    }

    public static ControllerContext ControllerContext(Guid localUserId)
    {
        return new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(
                    [
                        new Claim("hoppa_user_id", "10466"),
                        new Claim("local_user_id", localUserId.ToString())
                    ],
                    "test"))
            }
        };
    }

    public static JsonElement Payload(ActionResult<object> response)
    {
        var ok = Assert.IsType<OkObjectResult>(response.Result);
        return JsonSerializer.SerializeToElement(ok.Value);
    }
}

/// <summary>
/// Holds every upstream request until <see cref="Release"/>, so a test can
/// prove which requests were issued before any response existed.
/// </summary>
internal sealed class GatedProxy(params (string Path, string Json)[] responses) : IProxyHoppaRequestUseCase
{
    private readonly Dictionary<string, string> _responses = responses.ToDictionary(pair => pair.Path, pair => pair.Json);
    private readonly List<(string Path, TaskCompletionSource<ApplicationResult<JsonElement?>> Source)> _waiting = [];
    private readonly object _gate = new();
    private TaskCompletionSource? _arrivals;
    private int _expected;

    public List<string> Paths { get; } = [];

    public Task Arrived(int count)
    {
        lock (_gate)
        {
            if (Paths.Count >= count)
            {
                return Task.CompletedTask;
            }

            _expected = count;
            _arrivals = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            return _arrivals.Task;
        }
    }

    public void Release()
    {
        List<(string Path, TaskCompletionSource<ApplicationResult<JsonElement?>> Source)> waiting;
        lock (_gate)
        {
            waiting = [.. _waiting];
            _waiting.Clear();
        }

        foreach (var (path, source) in waiting)
        {
            source.SetResult(Respond(path));
        }
    }

    public Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(
        ProxyHoppaRequestCommand<TRequest> command,
        CancellationToken cancellationToken)
    {
        var source = new TaskCompletionSource<ApplicationResult<JsonElement?>>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (_gate)
        {
            Paths.Add(command.UpstreamPath);
            _waiting.Add((command.UpstreamPath, source));
            if (Paths.Count >= _expected)
            {
                _arrivals?.TrySetResult();
            }
        }

        return source.Task;
    }

    private ApplicationResult<JsonElement?> Respond(string path)
    {
        using var document = JsonDocument.Parse(_responses.TryGetValue(path, out var json) ? json : "{}");
        return ApplicationResult<JsonElement?>.Success(document.RootElement.Clone());
    }
}
