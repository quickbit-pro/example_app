#nullable enable

using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using NeoBanking.Application.MarketData;

namespace NeoBanking.Infrastructure.MarketData;

internal static class MarketDataServiceCollectionExtensions
{
    internal static IServiceCollection AddMarketData(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.Configure<MarketDataOptions>(configuration.GetSection(MarketDataOptions.SectionName));
        services.AddSingleton(TimeProvider.System);

        services.AddHttpClient<IFiatMarketRateProvider, WiseFiatMarketRateProvider>((serviceProvider, client) =>
        {
            var options = serviceProvider.GetRequiredService<IOptions<MarketDataOptions>>().Value.Wise;
            client.BaseAddress = options.BaseUrl;
            client.Timeout = TimeSpan.FromSeconds(Math.Clamp(options.TimeoutSeconds, 5, 120));
        });

        services.AddHttpClient<ICryptoMarketRateProvider, CoinGeckoCryptoMarketRateProvider>((serviceProvider, client) =>
        {
            var options = serviceProvider.GetRequiredService<IOptions<MarketDataOptions>>().Value.CoinGecko;
            client.BaseAddress = options.BaseUrl;
            client.Timeout = TimeSpan.FromSeconds(Math.Clamp(options.TimeoutSeconds, 5, 120));
        });

        services.AddScoped<IMarketRateService, MarketRateService>();
        services.AddHostedService<MarketRateRefreshWorker>();

        return services;
    }
}
