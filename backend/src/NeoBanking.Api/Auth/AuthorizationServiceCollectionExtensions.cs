using Microsoft.AspNetCore.Authorization;
using NeoBanking.Api.Mor;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Security;

namespace NeoBanking.Api.Auth;

public static class AuthorizationServiceCollectionExtensions
{
    public static IServiceCollection AddNeoBankingAuthorization(this IServiceCollection services)
    {
        services.AddScoped<MorIdentityResolver>();
        services.AddScoped<IMorCardRevealVerifier, MorCardRevealVerifier>();
        services.AddScoped<IAuthorizationHandler, MorRoleHandler>();
        services.AddAuthorization(options =>
        {
            options.AddPolicy(AuthorizationPolicyNames.AuthenticatedUser, policy =>
                policy.RequireAuthenticatedUser());

            options.AddPolicy(AuthorizationPolicyNames.User, policy =>
                policy.RequireAuthenticatedUser()
                    .RequireRole(ApplicationRoles.User));

            options.AddPolicy(AuthorizationPolicyNames.MorAdmin, policy => policy.RequireAuthenticatedUser().RequireClaim("company_installation_id").AddRequirements(new MorRoleRequirement(MorIdentityResolver.AdminRole)));
            options.AddPolicy(AuthorizationPolicyNames.MorUser, policy => policy.RequireAuthenticatedUser().RequireClaim("company_installation_id").AddRequirements(new MorRoleRequirement(MorIdentityResolver.UserRole)));

            options.AddPolicy(AuthorizationPolicyNames.Admin, policy =>
                policy.RequireAuthenticatedUser()
                    .RequireRole(ApplicationRoles.Admin)
                    .RequireClaim("company_installation_id"));
        });

        return services;
    }
}
