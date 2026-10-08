using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using Google.Apis.Auth.OAuth2;
using Microsoft.Extensions.Options;

namespace NeoBanking.Api.Notifications;

public sealed class FirebasePushSender
{
    private readonly FirebaseMessaging? _messaging;
    private readonly ILogger<FirebasePushSender> _logger;

    public FirebasePushSender(IOptions<PushNotificationOptions> options, ILogger<FirebasePushSender> logger)
    {
        _logger = logger;
        var configuration = options.Value;
        if (!configuration.Enabled)
        {
            return;
        }
        if (string.IsNullOrWhiteSpace(configuration.FirebaseProjectId))
        {
            logger.LogWarning("Push notifications are enabled but PushNotifications:FirebaseProjectId is missing.");
            return;
        }

        try
        {
            var credential = string.IsNullOrWhiteSpace(configuration.ServiceAccountPath)
                ? GoogleCredential.GetApplicationDefault()
                : CredentialFactory.FromFile<ServiceAccountCredential>(configuration.ServiceAccountPath).ToGoogleCredential();
            var app = FirebaseApp.Create(new AppOptions
            {
                Credential = credential,
                ProjectId = configuration.FirebaseProjectId
            }, "neobanking-push");
            _messaging = FirebaseMessaging.GetMessaging(app);
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Firebase Admin initialization failed; push delivery is disabled.");
        }
    }

    public bool IsConfigured => _messaging is not null;

    public async Task<FirebaseSendResult> SendAsync(
        IReadOnlyList<string> registrationTokens,
        string title,
        string body,
        IReadOnlyDictionary<string, string> data,
        CancellationToken cancellationToken)
    {
        if (_messaging is null || registrationTokens.Count == 0)
        {
            return new FirebaseSendResult(0, registrationTokens.Count, []);
        }

        var permanentlyFailedTokens = new List<string>();
        var failureCount = 0;
        var successCount = 0;
        foreach (var batch in registrationTokens.Chunk(500))
        {
            var tokens = batch.ToList();
#pragma warning disable CS0618
            var response = await _messaging.SendEachForMulticastAsync(new MulticastMessage
            {
                Tokens = tokens,
                Notification = new Notification { Title = title, Body = body },
                Data = new Dictionary<string, string>(data),
                Android = new AndroidConfig
                {
                    Priority = Priority.High,
                    Notification = new AndroidNotification
                    {
                        ChannelId = "banking_activity",
                        Sound = "default"
                    }
                },
                Apns = new ApnsConfig
                {
                    Aps = new Aps { Sound = "default", ContentAvailable = true }
                }
            }, cancellationToken: cancellationToken);
#pragma warning restore CS0618
            successCount += response.SuccessCount;
            for (var index = 0; index < response.Responses.Count; index++)
            {
                if (!response.Responses[index].IsSuccess)
                {
                    failureCount++;
                    var errorCode = response.Responses[index].Exception?.MessagingErrorCode;
                    if (errorCode is MessagingErrorCode.Unregistered or
                        MessagingErrorCode.InvalidArgument or
                        MessagingErrorCode.SenderIdMismatch)
                    {
                        permanentlyFailedTokens.Add(tokens[index]);
                    }
                    _logger.LogWarning(
                        "Firebase rejected one push target. ErrorCode={ErrorCode}",
                        errorCode);
                }
            }
        }

        return new FirebaseSendResult(successCount, failureCount, permanentlyFailedTokens);
    }
}

public sealed record FirebaseSendResult(
    int SuccessCount,
    int FailureCount,
    IReadOnlyList<string> PermanentlyFailedTokens);
