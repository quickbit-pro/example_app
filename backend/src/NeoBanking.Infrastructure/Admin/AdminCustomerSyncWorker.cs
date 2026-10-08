using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Infrastructure.Admin;

public sealed class AdminCustomerSyncWorker(
    IServiceScopeFactory scopeFactory,
    ILogger<AdminCustomerSyncWorker> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromMinutes(5);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromSeconds(2), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var scope = scopeFactory.CreateAsyncScope();
                var dbContext = scope.ServiceProvider.GetRequiredService<NeoBankingDbContext>();
                var syncService = scope.ServiceProvider.GetRequiredService<IAdminCustomerSyncService>();
                var companyIds = await dbContext.CompanyInstallations
                    .AsNoTracking()
                    .Where(company => company.Status != "disabled")
                    .Select(company => company.Id)
                    .ToListAsync(stoppingToken);

                foreach (var companyId in companyIds)
                {
                    await syncService.SyncCompanyAsync(companyId, stoppingToken);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "Customer operations reconciliation failed.");
            }

            await Task.Delay(Interval, stoppingToken);
        }
    }
}
