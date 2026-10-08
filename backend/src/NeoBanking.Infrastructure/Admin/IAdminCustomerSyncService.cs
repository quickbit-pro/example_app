namespace NeoBanking.Infrastructure.Admin;

public interface IAdminCustomerSyncService
{
    Task SyncCompanyAsync(Guid companyInstallationId, CancellationToken cancellationToken);

    Task<bool> SyncCustomerAsync(
        Guid companyInstallationId,
        Guid userId,
        CancellationToken cancellationToken);
}
