using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Authentication;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Company;
using NeoBanking.Api.OpenApi;
using NeoBanking.Application;
using NeoBanking.Infrastructure;
using NeoBanking.Infrastructure.Persistence;
using NeoBanking.Infrastructure.Persistence.Seeders;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Api.HoppaLogging;
using NeoBanking.Api.Middleware;
using NeoBanking.Application.Interfaces;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Admin;
using NeoBanking.Api.Notifications;
using NeoBanking.Api.Email;
using NeoBanking.Infrastructure.Email;
using NeoBanking.Api.Assistant;
using NeoBanking.Infrastructure.Assistant;

var builder = WebApplication.CreateBuilder(args);

// Local developer overrides must never supersede deployment environment
// variables. Published releases can otherwise inherit a developer's tenant
// API key and send provider requests under the wrong company.
if (builder.Environment.IsDevelopment())
{
    builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true, reloadOnChange: true);
}

builder.Services.Configure<JwtOptions>(builder.Configuration.GetSection(JwtOptions.SectionName));
builder.Services.Configure<CompanyOptions>(builder.Configuration.GetSection(CompanyOptions.SectionName));
builder.Services.AddNeoBankingApplication();
builder.Services.AddNeoBankingInfrastructure(builder.Configuration);
builder.Services.AddCors(options =>
{
    options.AddPolicy("BrowserApps", policy =>
    {
        var configuredOrigins = builder.Configuration
            .GetSection("Cors:AllowedOrigins")
            .Get<string[]>() ?? [];

        policy
            .SetIsOriginAllowed(origin =>
            {
                if (!Uri.TryCreate(origin, UriKind.Absolute, out var uri))
                {
                    return false;
                }

                if (configuredOrigins.Contains(origin, StringComparer.OrdinalIgnoreCase))
                {
                    return true;
                }

                return builder.Environment.IsDevelopment() &&
                    (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps) &&
                    (uri.Host == "localhost" || uri.Host == "127.0.0.1");
            })
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials();
    });
});
builder.Services.AddControllers();
builder.Services.AddOpenApi();
builder.Services.AddSingleton<LoginAttemptTracker>();
// Credential endpoints are throttled per client IP so password spraying and
// credential stuffing cannot run unchecked (10 attempts per minute).
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy(RateLimitPolicies.Auth, context =>
        RateLimitPartition.GetFixedWindowLimiter(
            ClientAddress(context),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 20,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0
            }));
    options.AddPolicy(RateLimitPolicies.PeerSensitive, context =>
        RateLimitPartition.GetFixedWindowLimiter(
            $"{RateLimitKeys.PerUser(context, ClientAddress(context))}:{context.Request.Path.Value?.ToLowerInvariant()}",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 1,
                Window = TimeSpan.FromSeconds(15),
                QueueLimit = 0
            }));
    options.AddPolicy(RateLimitPolicies.PeerLookup, context =>
        RateLimitPartition.GetFixedWindowLimiter(
            RateLimitKeys.PerUser(context, ClientAddress(context)),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 15,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0
            }));
});
builder.Services.AddAuthentication(AuthenticationSchemeNames.Bearer)
    .AddScheme<AuthenticationSchemeOptions, JwtBearerAuthenticationHandler>(
        AuthenticationSchemeNames.Bearer,
        options => { });
builder.Services.AddNeoBankingAuthorization();
builder.Services.AddScoped<HoppaFlowLogCollector>();
builder.Services.AddScoped<IHoppaFlowLogCollector>(serviceProvider =>
    serviceProvider.GetRequiredService<HoppaFlowLogCollector>());
builder.Services.AddHostedService<AdminCustomerSyncWorker>();
builder.Services.AddScoped<NeoBanking.Api.Admin.AdminKpiService>();
builder.Services.Configure<NeoBanking.Api.Admin.AdminRemindersOptions>(
    builder.Configuration.GetSection(NeoBanking.Api.Admin.AdminRemindersOptions.SectionName));
builder.Services.AddScoped<NeoBanking.Api.Admin.AdminReminderService>();
builder.Services.AddMemoryCache();
builder.Services.Configure<NeoBanking.Api.Admin.AdminInsightsOptions>(
    builder.Configuration.GetSection(NeoBanking.Api.Admin.AdminInsightsOptions.SectionName));
builder.Services.AddHttpClient<NeoBanking.Api.Admin.AdminInsightsService>(client => client.Timeout = Timeout.InfiniteTimeSpan)
    .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });
builder.Services.Configure<PushNotificationOptions>(
    builder.Configuration.GetSection(PushNotificationOptions.SectionName));
builder.Services.AddScoped<PushNotificationOutbox>();
builder.Services.AddScoped<NeoBanking.Api.Peer.PeerTransferService>();
builder.Services.Configure<OpenRouterOptions>(builder.Configuration.GetSection(OpenRouterOptions.SectionName));
builder.Services.Configure<AssistantOptions>(builder.Configuration.GetSection(AssistantOptions.SectionName));
builder.Services.AddScoped<IAssistantQuotaStore, AssistantQuotaStore>();
builder.Services.AddScoped<IAssistantSpendingSource, AssistantSpendingSource>();
builder.Services.AddHttpClient<AssistantService>(client => client.Timeout = Timeout.InfiniteTimeSpan)
    .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });
builder.Services.AddSingleton<FirebasePushSender>();
builder.Services.AddHostedService<PushNotificationDispatcher>();
builder.Services.AddHostedService<NeoBanking.Infrastructure.Referrals.ReferralAttributionDispatcher>();
builder.Services.AddScoped<AuthEmailNotifier>();
builder.Services.AddTransactionalEmailDispatcher();

NeoBanking.Api.Documents.DocumentServices.Add(builder.Services, builder.Configuration);

var app = builder.Build();

// The API listens on loopback behind nginx, which sets X-Forwarded-For; key
// throttling on the first hop so all customers do not share one bucket.
static string ClientAddress(HttpContext context)
{
    var forwarded = context.Request.Headers["X-Forwarded-For"].FirstOrDefault()?
        .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
        .FirstOrDefault();
    return string.IsNullOrWhiteSpace(forwarded)
        ? context.Connection.RemoteIpAddress?.ToString() ?? "unknown"
        : forwarded;
}

// A committed placeholder or short signing key would let anyone with
// repository access forge tokens; refuse to start outside Development.
if (!app.Environment.IsDevelopment())
{
    JwtOptionsGuard.EnsureProductionSafe(app.Services.GetRequiredService<IOptions<JwtOptions>>().Value);
}

if (args.Contains("--migrate-and-seed", StringComparer.OrdinalIgnoreCase))
{
    await using var scope = app.Services.CreateAsyncScope();
    var dbContext = scope.ServiceProvider.GetRequiredService<NeoBankingDbContext>();
    var adminSeedOptions = scope.ServiceProvider.GetRequiredService<IOptions<AdminSeedOptions>>().Value;

    await dbContext.Database.MigrateAsync();
    await NeoBankingDatabaseSeeder.SeedAsync(
        dbContext,
        scope.ServiceProvider.GetRequiredService<PasswordHasher<ApplicationUser>>(),
        adminSeedOptions);

    Console.WriteLine($"Database migrated and admin account seeded for {adminSeedOptions.Email.Trim()}.");

    return;
}

app.MapOpenApi();
app.MapScalarApiReference();

app.UseCors("BrowserApps");
app.UseMiddleware<ApiExceptionHandlingMiddleware>();
app.UseCompanyContext();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.UseMiddleware<HoppaFlowLoggingMiddleware>();

app.MapControllers();

app.MapGet("/health", () => Results.Ok(new
{
    status = "Healthy",
    timestamp = DateTimeOffset.UtcNow
}))
.AllowAnonymous()
.WithName("Health")
.WithTags("Operations");

app.MapGet("/", () => Results.Redirect("/scalar/v1"))
    .AllowAnonymous()
    .ExcludeFromDescription();

app.Run();

public partial class Program
{
}
