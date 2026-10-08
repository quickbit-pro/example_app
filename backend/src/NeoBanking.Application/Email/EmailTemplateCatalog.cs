namespace NeoBanking.Application.Email;

public sealed record EmailPlaceholderDefinition(string Name, string Description, string Sample, bool Required = false);

public sealed record EmailTemplateDefinition(
    string Key,
    string Name,
    string Description,
    string DefaultSubject,
    string DefaultHtmlBody,
    string DefaultTextBody,
    IReadOnlyList<EmailPlaceholderDefinition> Placeholders)
{
    public IReadOnlyDictionary<string, string> SampleValues()
    {
        return Placeholders.ToDictionary(
            placeholder => placeholder.Name,
            placeholder => placeholder.Sample,
            StringComparer.OrdinalIgnoreCase);
    }
}

/// <summary>
/// Built-in transactional emails. Admins can override subject and bodies per
/// installation; the catalog defines the placeholders each template may use
/// and the defaults that apply until an override is saved.
/// </summary>
public static class EmailTemplateCatalog
{
    public const string PasswordReset = "password_reset";
    public const string EmailVerification = "email_verification";
    public const string AccountConnected = "account_connected";
    public const string ReminderFinishSignup = "reminder_finish_signup";
    public const string ReminderAddMoney = "reminder_add_money";
    public const string ReminderGetCard = "reminder_get_card";
    public const string ReminderUseCard = "reminder_use_card";
    public const string ReminderComeBack = "reminder_come_back";

    private static readonly EmailPlaceholderDefinition[] CommonPlaceholders =
    [
        new("appName", "Customer-facing app name from company branding.", "NeoBanking"),
        new("companyName", "Legal company name.", "NeoBanking Demo Company"),
        new("supportEmail", "Support mailbox from company branding.", "support@example.com"),
        new("brandColor", "Primary brand color as a CSS hex value.", "#2563EB"),
        new("userName", "Display name of the recipient, or their email when no name is set.", "Alex Rivera"),
        new("email", "Recipient email address.", "alex@example.com"),
        new("year", "Current year, for footers.", DateTime.UtcNow.Year.ToString())
    ];

    private static readonly IReadOnlyList<EmailTemplateDefinition> Definitions =
    [
        new(
            PasswordReset,
            "Password reset",
            "Sent when a customer asks to reset a forgotten password. Contains the one-time code they enter in the app.",
            "{{appName}}: your password reset code",
            Layout(
                "Reset your password",
                """
                <p>Hi {{userName}},</p>
                <p>We received a request to reset the password for your {{appName}} account. Enter this code in the app to choose a new password:</p>
                <h1>{{code}}</h1>
                <p>The code expires in {{expiresMinutes}} minutes and can only be used once.</p>
                <p>If you didn’t ask for a reset, you can ignore this email. Your password will stay the same.</p>
                """),
            """
            Hi {{userName}},

            We received a request to reset the password for your {{appName}} account.
            Enter this code in the app to choose a new password: {{code}}

            The code expires in {{expiresMinutes}} minutes and can only be used once.
            If you didn't ask for a reset, ignore this email. Your password will stay the same.

            Need help? Contact {{supportEmail}}.
            """,
            [
                .. CommonPlaceholders,
                new("code", "Six-digit one-time code.", "482913", Required: true),
                new("expiresMinutes", "Minutes until the code expires.", "15")
            ]),
        new(
            EmailVerification,
            "Confirm email address",
            "Sent right after registration so the customer can confirm they own the email address.",
            "Confirm your email for {{appName}}",
            Layout(
                "Confirm your email",
                """
                <p>Hi {{userName}},</p>
                <p>Welcome to {{appName}}! Confirm that {{email}} belongs to you by entering this code in the app:</p>
                <h1>{{code}}</h1>
                <p>The code expires in {{expiresMinutes}} minutes.</p>
                <p>If you didn’t create an account, you can safely ignore this email.</p>
                """),
            """
            Hi {{userName}},

            Welcome to {{appName}}! Confirm that {{email}} belongs to you by entering this code in the app: {{code}}

            The code expires in {{expiresMinutes}} minutes.
            If you didn't create an account, you can safely ignore this email.

            Need help? Contact {{supportEmail}}.
            """,
            [
                .. CommonPlaceholders,
                new("code", "Six-digit one-time code.", "735204", Required: true),
                new("expiresMinutes", "Minutes until the code expires.", "15")
            ]),
        new(
            AccountConnected,
            "Existing account connected",
            "Sent after a customer connects an existing account to this app, so they know a new login was created.",
            "Your account is now connected to {{appName}}",
            Layout(
                "Account connected",
                """
                <p>Hi {{userName}},</p>
                <p>Your existing account was connected to {{appName}} on {{connectedAt}} using {{method}}. You can now sign in with {{email}} and the app-specific password you just created.</p>
                <p>If this wasn’t you, contact us right away at {{supportEmail}} so we can secure your account.</p>
                """),
            """
            Hi {{userName}},

            Your existing account was connected to {{appName}} on {{connectedAt}} using {{method}}.
            You can now sign in with {{email}} and the app-specific password you just created.

            If this wasn't you, contact us right away at {{supportEmail}} so we can secure your account.
            """,
            [
                .. CommonPlaceholders,
                new("connectedAt", "Date and time the account was connected (UTC).", "2 Sep 2026, 09:41 UTC"),
                new("method", "How the account was verified: email code or QR transfer.", "an email verification code")
            ]),

        Reminder(ReminderFinishSignup, "Reminder: finish signing up",
            "Sent from the admin panel to customers who signed up but have not finished onboarding or verification.",
            "Finish setting up your {{appName}} account", "You’re almost there",
            "You started opening your {{appName}} account but haven’t finished yet. It takes a few minutes to complete your details and verify your identity.",
            "Continue setting up", "If you’ve changed your mind, you can ignore this email."),
        Reminder(ReminderAddMoney, "Reminder: add money",
            "Sent from the admin panel to approved customers who have not added money yet.",
            "Your {{appName}} account is ready", "Your account is ready",
            "Your identity has been verified. Add money to your {{appName}} account to start paying online and in stores.",
            "Add money", "Questions? Just reply to this email or contact {{supportEmail}}."),
        Reminder(ReminderGetCard, "Reminder: get a card",
            "Sent from the admin panel to customers who added money but have no card yet.",
            "Get your {{appName}} card", "Your card is one step away",
            "You’ve added money to your {{appName}} account. Create your card in the app to pay online, in stores and with Apple Pay or Google Pay.",
            "Get my card", "Questions? Contact {{supportEmail}}."),
        Reminder(ReminderUseCard, "Reminder: use your card",
            "Sent from the admin panel to customers who have a card but have never used it.",
            "Your {{appName}} card is ready to use", "Start using your card",
            "Your {{appName}} card is ready. Add it to Apple Pay or Google Pay, or use the card details in the app to pay online.",
            "Open {{appName}}", "Questions? Contact {{supportEmail}}."),
        Reminder(ReminderComeBack, "Reminder: come back",
            "Sent from the admin panel to customers who used their card before but not in the last 30 days.",
            "Your {{appName}} account is waiting for you", "It’s been a while",
            "We haven’t seen you in {{appName}} for a while. Your account and card are still here whenever you need them.",
            "Open {{appName}}", "Questions? Contact {{supportEmail}}."),
    ];

    public static IReadOnlyList<EmailTemplateDefinition> All => Definitions;

    public static EmailTemplateDefinition? Find(string? key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            return null;
        }

        return Definitions.FirstOrDefault(definition =>
            string.Equals(definition.Key, key.Trim(), StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Validates an edited template against its definition. Returns field →
    /// messages, empty when the template is acceptable.
    /// </summary>
    public static Dictionary<string, string[]> Validate(
        EmailTemplateDefinition definition,
        string? subject,
        string? htmlBody,
        string? textBody)
    {
        var errors = new Dictionary<string, List<string>>(StringComparer.Ordinal);

        void Add(string field, string message)
        {
            if (!errors.TryGetValue(field, out var list))
            {
                errors[field] = list = [];
            }

            list.Add(message);
        }

        if (string.IsNullOrWhiteSpace(subject))
        {
            Add("subject", "Subject is required.");
        }
        else if (subject.Length > 200)
        {
            Add("subject", "Subject must be 200 characters or fewer.");
        }
        else if (subject.Contains('\n') || subject.Contains('\r'))
        {
            Add("subject", "Subject must be a single line.");
        }

        if (string.IsNullOrWhiteSpace(htmlBody))
        {
            Add("htmlBody", "HTML body is required.");
        }
        else if (htmlBody.Length > 200_000)
        {
            Add("htmlBody", "HTML body must be 200,000 characters or fewer.");
        }

        if (textBody is { Length: > 50_000 })
        {
            Add("textBody", "Plain-text body must be 50,000 characters or fewer.");
        }

        var allowed = new HashSet<string>(definition.Placeholders.Select(placeholder => placeholder.Name), StringComparer.OrdinalIgnoreCase);
        var used = EmailTemplateRenderer.FindPlaceholders(subject, htmlBody, textBody);
        var unknown = used.Where(name => !allowed.Contains(name)).ToList();
        if (unknown.Count > 0)
        {
            Add("placeholders", $"Unknown placeholder(s): {string.Join(", ", unknown.Select(name => "{{" + name + "}}"))}.");
        }

        foreach (var required in definition.Placeholders.Where(placeholder => placeholder.Required))
        {
            var htmlUses = EmailTemplateRenderer.FindPlaceholders(htmlBody).Contains(required.Name);
            var textUses = string.IsNullOrWhiteSpace(textBody) || EmailTemplateRenderer.FindPlaceholders(textBody).Contains(required.Name);
            if (!htmlUses || !textUses)
            {
                Add("placeholders", $"{{{{{required.Name}}}}} must appear in the HTML body and in the plain-text body when one is provided.");
            }
        }

        return errors.ToDictionary(pair => pair.Key, pair => pair.Value.ToArray());
    }

    /// <summary>Lifecycle reminder: one paragraph, a button that opens the app, and a closing line.</summary>
    private static EmailTemplateDefinition Reminder(
        string key, string name, string description, string subject, string heading, string message, string button, string closing) =>
        new(key, name, description, subject,
            Layout(heading, """
                <p>Hi {{userName}},</p>
                <p>__MESSAGE__</p>
                <p><a href="{{appUrl}}" style="display:inline-block;background:{{brandColor}};color:#ffffff;padding:14px 22px;border-radius:12px;text-decoration:none;font-weight:bold">__BUTTON__</a></p>
                <p>__CLOSING__</p>
                """.Replace("__MESSAGE__", message, StringComparison.Ordinal)
                   .Replace("__BUTTON__", button, StringComparison.Ordinal)
                   .Replace("__CLOSING__", closing, StringComparison.Ordinal)),
            """
            Hi {{userName}},

            __MESSAGE__

            __BUTTON__: {{appUrl}}

            __CLOSING__
            """.Replace("__MESSAGE__", message.Replace('’', '\''), StringComparison.Ordinal)
               .Replace("__BUTTON__", button, StringComparison.Ordinal)
               .Replace("__CLOSING__", closing.Replace('’', '\''), StringComparison.Ordinal),
            [.. CommonPlaceholders, new("appUrl", "Link that opens the app.", "https://app.example.com")]);

    /// <summary>
    /// Wraps a template's heading and content in the shared email layout. The
    /// heading and content are bracketed by HTML comment markers
    /// (<c>&lt;!--heading:start--&gt;</c> … <c>&lt;!--content:end--&gt;</c>) that the
    /// admin panel's visual editor uses to edit just those parts while the
    /// surrounding layout stays intact. Styling for the editable content comes
    /// from the <c>.email-content</c> rules in the head, so rich-text output
    /// (plain <c>&lt;p&gt;</c>, <c>&lt;h1&gt;</c> for the large code line,
    /// <c>&lt;h2&gt;</c>, lists, links) needs no inline styles.
    /// </summary>
    private static string Layout(string heading, string content)
    {
        return """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>{{appName}}</title>
              <style>
                .email-content p, .email-content ul, .email-content ol { margin: 0 0 16px; }
                .email-content p:last-child { margin-bottom: 0; }
                .email-content h1 { margin: 0 0 16px; font-size: 32px; line-height: 40px; font-weight: 700; letter-spacing: 8px; color: #0f172a; }
                .email-content h2 { margin: 0 0 12px; font-size: 18px; line-height: 26px; font-weight: 700; color: #0f172a; }
                .email-content a { color: #2563eb; }
              </style>
            </head>
            <body style="margin:0;padding:0;background:#f4f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#334155;font-size:16px;line-height:24px">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;padding:32px 16px">
                <tr>
                  <td align="center">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:16px;overflow:hidden">
                      <tr>
                        <td style="background:{{brandColor}};padding:24px 32px;color:#ffffff;font-size:20px;font-weight:700">{{appName}}</td>
                      </tr>
                      <tr>
                        <td style="padding:32px">
                          <h1 style="margin:0 0 20px;font-size:24px;line-height:32px;color:#0f172a"><!--heading:start-->__HEADING__<!--heading:end--></h1>
                          <div class="email-content"><!--content:start-->
            __CONTENT__
            <!--content:end--></div>
                        </td>
                      </tr>
                      <tr>
                        <td style="padding:20px 32px;border-top:1px solid #e2e8f0;color:#64748b;font-size:12px;line-height:18px">
                          Need help? Contact <a href="mailto:{{supportEmail}}" style="color:#2563eb">{{supportEmail}}</a>.<br>
                          © {{year}} {{companyName}}. This email was sent to {{email}}.
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
            </body>
            </html>
            """.Replace("__HEADING__", heading, StringComparison.Ordinal)
               .Replace("__CONTENT__", content.Trim(), StringComparison.Ordinal);
    }
}
