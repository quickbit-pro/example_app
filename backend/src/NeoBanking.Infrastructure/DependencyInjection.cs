using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Identity;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Hoppa;
using NeoBanking.Infrastructure.Admin;
using NeoBanking.Infrastructure.Persistence;
using NeoBanking.Infrastructure.MarketData;
using NeoBanking.Infrastructure.Email;

namespace NeoBanking.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddNeoBankingInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var connectionString =
            configuration.GetConnectionString("NeoBankingDb") ??
            configuration["Database:ConnectionString"];

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException(
                "Database connection string is missing. Configure ConnectionStrings:NeoBankingDb or Database:ConnectionString.");
        }

        services.AddDbContext<NeoBankingDbContext>(options =>
            options.UseNpgsql(DatabaseConnectionString.Normalize(connectionString)));

        services.Configure<NeoBanking.Infrastructure.Persistence.Seeders.AdminSeedOptions>(
            configuration.GetSection(NeoBanking.Infrastructure.Persistence.Seeders.AdminSeedOptions.SectionName));
        services.AddScoped<PasswordHasher<ApplicationUser>>();
        services.AddHoppaIntegration(configuration);
        services.AddMarketData(configuration);
        services.AddTransactionalEmail(configuration);
        services.Configure<AdminCustomerSyncOptions>(configuration.GetSection(AdminCustomerSyncOptions.SectionName));
        services.AddSingleton(TimeProvider.System);
        services.AddScoped<IAdminCustomerSyncService, AdminCustomerSyncService>();

        return services;
    }
}
