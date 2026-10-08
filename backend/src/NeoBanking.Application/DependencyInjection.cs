using Microsoft.Extensions.DependencyInjection;
using NeoBanking.Application.Company;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Application.UseCases.Kyc;

namespace NeoBanking.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddNeoBankingApplication(this IServiceCollection services)
    {
        services.AddScoped<ICompanyContextAccessor, CompanyContextAccessor>();
        services.AddScoped<IProxyHoppaRequestUseCase, ProxyHoppaRequestUseCase>();
        services.AddScoped<ICreateSumSubAccessTokenUseCase, CreateSumSubAccessTokenUseCase>();

        return services;
    }
}
