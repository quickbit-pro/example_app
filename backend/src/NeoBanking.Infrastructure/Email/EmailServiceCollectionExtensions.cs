#nullable enable

using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using NeoBanking.Application.Email;
using NeoBanking.Infrastructure.Security;

namespace NeoBanking.Infrastructure.Email;

public static class EmailServiceCollectionExtensions
{
    public static IServiceCollection AddTransactionalEmail(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.Configure<EmailOptions>(configuration.GetSection(EmailOptions.SectionName));
        services.AddSingleton<IEmailSender>(serviceProvider =>
        {
            var options = serviceProvider.GetRequiredService<IOptions<EmailOptions>>();
            return options.Value.IsSendGrid
                ? ActivatorUtilities.CreateInstance<SendGridEmailSender>(serviceProvider)
                : ActivatorUtilities.CreateInstance<LoggingEmailSender>(serviceProvider);
        });
        services.AddScoped<EmailTemplateStore>();
        services.AddScoped<EmailOutbox>();
        services.AddScoped<UserVerificationCodeService>();

        return services;
    }

    /// <summary>Registers the background delivery loop. Call from exactly one host.</summary>
    public static IServiceCollection AddTransactionalEmailDispatcher(this IServiceCollection services)
    {
        services.AddHostedService<EmailDispatcher>();
        return services;
    }
}
