#nullable enable

using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NeoBanking.Application.Email;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Infrastructure.Email;

/// <summary>
/// Delivers queued <see cref="EmailMessage"/> rows through the configured
/// <see cref="IEmailSender"/> with retry and back-off, mirroring the push
/// notification dispatcher.
/// </summary>
public sealed class EmailDispatcher(
    IServiceScopeFactory scopeFactory,
    IEmailSender sender,
    IOptions<EmailOptions> options,
    ILogger<EmailDispatcher> logger) : BackgroundService
{
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan StaleProcessing = TimeSpan.FromMinutes(5);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!sender.IsConfigured)
        {
            logger.LogWarning(
                "Email provider {Provider} is not configured; queued emails will wait until it is.",
                sender.ProviderName);
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (sender.IsConfigured)
                {
                    await DispatchBatchAsync(stoppingToken);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "Email dispatch cycle failed.");
            }

            await Task.Delay(PollInterval, stoppingToken);
        }
    }

    private async Task DispatchBatchAsync(CancellationToken cancellationToken)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<NeoBankingDbContext>();
        var maxAttempts = Math.Max(1, options.Value.MaxAttempts);
        var now = DateTimeOffset.UtcNow;
        var staleBefore = now.Subtract(StaleProcessing);

        var messages = await dbContext.EmailMessages
            .Where(message =>
                (message.Status == "pending" ||
                 message.Status == "retry" ||
                 (message.Status == "processing" && message.UpdatedAt < staleBefore)) &&
                (message.NextAttemptAt == null || message.NextAttemptAt <= now) &&
                message.AttemptCount < maxAttempts)
            .OrderBy(message => message.CreatedAt)
            .Take(25)
            .ToListAsync(cancellationToken);

        foreach (var message in messages)
        {
            var claimed = await dbContext.EmailMessages
                .Where(candidate =>
                    candidate.Id == message.Id &&
                    (candidate.Status == "pending" ||
                     candidate.Status == "retry" ||
                     (candidate.Status == "processing" && candidate.UpdatedAt < staleBefore)))
                .ExecuteUpdateAsync(setters => setters
                    .SetProperty(candidate => candidate.Status, "processing")
                    .SetProperty(candidate => candidate.AttemptCount, candidate => candidate.AttemptCount + 1)
                    .SetProperty(candidate => candidate.UpdatedAt, now),
                    cancellationToken);
            if (claimed == 0)
            {
                continue;
            }

            message.Status = "processing";
            message.AttemptCount++;

            try
            {
                // A delayed retry must never send a recovery code replaced by
                // a resend, already used, or expired while waiting in the queue.
                if (await IsObsoleteRecoveryAsync(dbContext, message, cancellationToken))
                {
                    message.Status = "cancelled";
                    message.ErrorMessage = "Recovery code was replaced, used, or expired before delivery.";
                    message.NextAttemptAt = null;
                    message.UpdatedAt = DateTimeOffset.UtcNow;
                    continue;
                }
                var result = await sender.SendAsync(
                    new EmailEnvelope(
                        message.ToEmail,
                        message.ToName,
                        message.Subject,
                        message.HtmlBody,
                        message.TextBody,
                        new Dictionary<string, string>
                        {
                            ["neobanking_message_id"] = message.Id.ToString(),
                            ["neobanking_template"] = message.TemplateKey
                        }),
                    cancellationToken);

                if (result.Succeeded)
                {
                    message.Status = "sent";
                    message.SentAt = now;
                    message.ProviderMessageId = result.ProviderMessageId;
                    message.ErrorMessage = null;
                    message.NextAttemptAt = null;
                }
                else if (result.Permanent)
                {
                    message.Status = "failed";
                    message.NextAttemptAt = null;
                    message.ErrorMessage = Truncate(result.Error ?? "Delivery rejected.");
                }
                else
                {
                    ScheduleRetry(message, now, result.Error ?? "Delivery failed.", maxAttempts);
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Email {MessageId} delivery failed.", message.Id);
                ScheduleRetry(message, now, exception.Message, maxAttempts);
            }

            message.UpdatedAt = now;
        }

        await dbContext.SaveChangesAsync(cancellationToken);
    }

    public static async Task<bool> IsObsoleteRecoveryAsync(NeoBankingDbContext db, EmailMessage message, CancellationToken ct)
    {
        if (message.TemplateKey != EmailTemplateCatalog.PasswordReset) return false;
        using var metadata = JsonDocument.Parse(message.MetadataJson);
        if (!metadata.RootElement.TryGetProperty("verificationCodeId", out var value) ||
            !value.TryGetGuid(out var codeId)) return false; // Legacy queued messages.
        var now = DateTimeOffset.UtcNow;
        return !await db.UserVerificationCodes.AnyAsync(code => code.Id == codeId &&
            code.CompanyInstallationId == message.CompanyInstallationId && code.UserId == message.UserId &&
            code.ConsumedAt == null && code.ExpiresAt > now, ct);
    }

    private static void ScheduleRetry(EmailMessage message, DateTimeOffset now, string error, int maxAttempts)
    {
        message.ErrorMessage = Truncate(error);
        if (message.AttemptCount >= maxAttempts)
        {
            message.Status = "failed";
            message.NextAttemptAt = null;
            return;
        }

        message.Status = "retry";
        message.NextAttemptAt = now.AddSeconds(Math.Pow(2, message.AttemptCount) * 15);
    }

    private static string Truncate(string value) => value.Length <= 1000 ? value : value[..1000];
}
