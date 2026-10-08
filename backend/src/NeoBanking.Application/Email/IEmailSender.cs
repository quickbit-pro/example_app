namespace NeoBanking.Application.Email;

public sealed record EmailEnvelope(
    string ToEmail,
    string? ToName,
    string Subject,
    string HtmlBody,
    string TextBody,
    IReadOnlyDictionary<string, string>? CustomArgs = null);

public sealed record EmailSendResult(bool Succeeded, string? ProviderMessageId, string? Error, bool Permanent = false)
{
    public static EmailSendResult Success(string? providerMessageId) => new(true, providerMessageId, null);

    public static EmailSendResult Failure(string error, bool permanent = false) => new(false, null, error, permanent);
}

public interface IEmailSender
{
    /// <summary>Human readable provider name shown to admins.</summary>
    string ProviderName { get; }

    /// <summary>True when the provider has everything it needs to deliver mail.</summary>
    bool IsConfigured { get; }

    Task<EmailSendResult> SendAsync(EmailEnvelope envelope, CancellationToken cancellationToken);
}
