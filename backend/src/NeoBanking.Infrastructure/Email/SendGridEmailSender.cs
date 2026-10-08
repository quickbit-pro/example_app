#nullable enable

using System.Net;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NeoBanking.Application.Email;
using SendGrid;
using SendGrid.Helpers.Mail;

namespace NeoBanking.Infrastructure.Email;

public sealed class SendGridEmailSender : IEmailSender
{
    private readonly EmailOptions _options;
    private readonly ILogger<SendGridEmailSender> _logger;
    private readonly SendGridClient? _client;

    public SendGridEmailSender(IOptions<EmailOptions> options, ILogger<SendGridEmailSender> logger)
    {
        _options = options.Value;
        _logger = logger;

        if (!_options.IsSendGrid)
        {
            return;
        }

        if (string.IsNullOrWhiteSpace(_options.SendGrid.ApiKey))
        {
            logger.LogWarning("Email provider is sendgrid but Email:SendGrid:ApiKey is missing; delivery is disabled.");
            return;
        }

        if (string.IsNullOrWhiteSpace(_options.FromEmail))
        {
            logger.LogWarning("Email:FromEmail is missing; SendGrid delivery is disabled.");
            return;
        }

        var clientOptions = new SendGridClientOptions { ApiKey = _options.SendGrid.ApiKey };
        if (!string.IsNullOrWhiteSpace(_options.SendGrid.Host))
        {
            clientOptions.Host = _options.SendGrid.Host;
        }

        _client = new SendGridClient(clientOptions);
    }

    public string ProviderName => "SendGrid";

    public bool IsConfigured => _client is not null;

    public async Task<EmailSendResult> SendAsync(EmailEnvelope envelope, CancellationToken cancellationToken)
    {
        if (_client is null)
        {
            return EmailSendResult.Failure("SendGrid is not configured.", permanent: true);
        }

        var message = new SendGridMessage
        {
            From = new EmailAddress(_options.FromEmail, NullIfBlank(_options.FromName)),
            Subject = envelope.Subject,
            HtmlContent = envelope.HtmlBody,
            PlainTextContent = string.IsNullOrWhiteSpace(envelope.TextBody) ? null : envelope.TextBody
        };
        message.AddTo(new EmailAddress(envelope.ToEmail, NullIfBlank(envelope.ToName)));

        if (!string.IsNullOrWhiteSpace(_options.ReplyToEmail))
        {
            message.ReplyTo = new EmailAddress(_options.ReplyToEmail);
        }

        if (envelope.CustomArgs is { Count: > 0 })
        {
            foreach (var (key, value) in envelope.CustomArgs)
            {
                message.AddCustomArg(key, value);
            }
        }

        if (_options.SendGrid.SandboxMode)
        {
            message.MailSettings = new MailSettings { SandboxMode = new SandboxMode { Enable = true } };
        }

        // Transactional mail must not carry list-unsubscribe tracking noise.
        message.SetClickTracking(false, false);
        message.SetOpenTracking(false);

        try
        {
            var response = await _client.SendEmailAsync(message, cancellationToken);
            if (response.IsSuccessStatusCode)
            {
                var messageId = response.Headers.TryGetValues("X-Message-Id", out var values)
                    ? values.FirstOrDefault()
                    : null;
                return EmailSendResult.Success(messageId);
            }

            var body = await response.Body.ReadAsStringAsync(cancellationToken);
            var permanent = response.StatusCode is HttpStatusCode.BadRequest
                or HttpStatusCode.Unauthorized
                or HttpStatusCode.Forbidden
                or HttpStatusCode.NotFound
                or HttpStatusCode.RequestEntityTooLarge;
            _logger.LogWarning(
                "SendGrid rejected an email. StatusCode={StatusCode} Body={Body}",
                (int)response.StatusCode,
                Truncate(body));

            return EmailSendResult.Failure($"SendGrid returned {(int)response.StatusCode}: {Truncate(body)}", permanent);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            _logger.LogWarning(exception, "SendGrid request failed.");
            return EmailSendResult.Failure(exception.Message);
        }
    }

    private static string? NullIfBlank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value;

    private static string Truncate(string value) => value.Length <= 500 ? value : value[..500];
}
