#nullable enable

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NeoBanking.Application.MarketData;

namespace NeoBanking.Infrastructure.MarketData;

internal sealed class MarketRateRefreshWorker(
    IServiceScopeFactory scopeFactory,
    IOptions<MarketDataOptions> options,
    TimeProvider timeProvider,
    ILogger<MarketRateRefreshWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!options.Value.Enabled)
        {
            logger.LogInformation("Hourly market-rate refresh is disabled.");
            return;
        }

        await RefreshAsync(stoppingToken);

        var interval = TimeSpan.FromMinutes(Math.Clamp(options.Value.RefreshMinutes, 5, 1440));
        using var timer = new PeriodicTimer(interval, timeProvider);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            await RefreshAsync(stoppingToken);
        }
    }

    private async Task RefreshAsync(CancellationToken cancellationToken)
    {
        try
        {
            await using var scope = scopeFactory.CreateAsyncScope();
            var service = scope.ServiceProvider.GetRequiredService<IMarketRateService>();
            var batch = await service.RefreshAsync(
                options.Value.DefaultBaseCurrency,
                cancellationToken);

            logger.LogInformation(
                "Market rates refreshed for {BaseCurrency}: {RateCount} rates, {MissingCount} missing.",
                batch.BaseCurrency,
                batch.Rates.Count,
                batch.MissingSymbols.Count);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            logger.LogError(exception, "Hourly market-rate refresh failed; the last stored snapshot remains available.");
        }
    }
}
