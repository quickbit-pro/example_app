#nullable enable

using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NeoBanking.Application.Email;

namespace NeoBanking.Infrastructure.Email;

/// <summary>
/// Development sender: writes the rendered email to the application log and
/// reports success so flows that depend on email can be exercised locally.
/// </summary>
public sealed class LoggingEmailSender(IOptions<EmailOptions> options, ILogger<LoggingEmailSender> logger) : IEmailSender
{
    public string ProviderName => options.Value.IsLog ? "Application log" : "Disabled";

    public bool IsConfigured => options.Value.IsLog;

    public Task<EmailSendResult> SendAsync(EmailEnvelope envelope, CancellationToken cancellationToken)
    {
        if (!IsConfigured)
        {
            return Task.FromResult(EmailSendResult.Failure("Email delivery is disabled.", permanent: true));
        }

        logger.LogInformation(
            "Email (log provider) To={To} Subject={Subject}\n{Text}",
            envelope.ToEmail,
            envelope.Subject,
            string.IsNullOrWhiteSpace(envelope.TextBody) ? envelope.HtmlBody : envelope.TextBody);

        return Task.FromResult(EmailSendResult.Success($"log-{Guid.NewGuid():N}"));
    }
}
