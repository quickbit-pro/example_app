using System;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using NeoBanking.Application.Interfaces;

namespace NeoBanking.Infrastructure.Hoppa;

public static class HoppaServiceCollectionExtensions
{
    public static IServiceCollection AddHoppaIntegration(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.AddHttpContextAccessor();
        services.AddTransient<HoppaClientAddressHandler>();
        services.Configure<HoppaOptions>(configuration.GetSection(HoppaOptions.SectionName));

        services.AddHttpClient<IHoppaClient, HoppaClient>((serviceProvider, httpClient) =>
        {
            var options = serviceProvider.GetRequiredService<IOptions<HoppaOptions>>().Value;

            if (options.BaseUrl is not null)
            {
                httpClient.BaseAddress = options.BaseUrl;
            }

            httpClient.Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds > 0 ? options.TimeoutSeconds : 30);
        }).AddHttpMessageHandler<HoppaClientAddressHandler>();

        services.AddHttpClient<IHoppaKycClient, HoppaKycClient>((serviceProvider, httpClient) =>
        {
            var options = serviceProvider.GetRequiredService<IOptions<HoppaOptions>>().Value;

            if (options.BaseUrl is not null)
            {
                httpClient.BaseAddress = options.BaseUrl;
            }

            httpClient.Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds > 0 ? options.TimeoutSeconds : 30);
        }).AddHttpMessageHandler<HoppaClientAddressHandler>();

        return services;
    }
}
