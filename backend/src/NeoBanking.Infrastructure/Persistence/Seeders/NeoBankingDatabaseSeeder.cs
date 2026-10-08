#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Identity;
using NeoBanking.Domain.Entities;
using NeoBanking.Domain.Security;

namespace NeoBanking.Infrastructure.Persistence.Seeders;

public static class NeoBankingDatabaseSeeder
{
    public static async Task SeedAsync(
        NeoBankingDbContext dbContext,
        PasswordHasher<ApplicationUser> passwordHasher,
        AdminSeedOptions adminOptions,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(dbContext);
        ArgumentNullException.ThrowIfNull(passwordHasher);
        ArgumentNullException.ThrowIfNull(adminOptions);

        // Deployments drop SeedAdmin:Password after the first run; a later
        // --migrate-and-seed must then keep the existing admin instead of
        // failing the release.
        if (string.IsNullOrWhiteSpace(adminOptions.Password) &&
            await dbContext.Users.AsNoTracking().AnyAsync(user => user.AdminProfile != null, cancellationToken))
        {
            return;
        }

        ValidateAdminOptions(adminOptions);

        var now = DateTimeOffset.UtcNow;
        var normalizedEmail = adminOptions.Email.Trim().ToUpperInvariant();
        var defaultCompanyInstallation = await dbContext.CompanyInstallations
            .SingleOrDefaultAsync(
                company => company.Id == DefaultSeedData.CompanyInstallationId &&
                           company.Slug == DefaultSeedData.CompanySlug,
                cancellationToken);

        if (defaultCompanyInstallation is null)
        {
            var existingAdminCompanyId = await dbContext.Users
                .AsNoTracking()
                .Where(user => user.EmailNormalized == normalizedEmail && user.AdminProfile != null)
                .Select(user => (Guid?)user.CompanyInstallationId)
                .FirstOrDefaultAsync(cancellationToken);

            if (existingAdminCompanyId.HasValue)
            {
                defaultCompanyInstallation = await dbContext.CompanyInstallations
                    .SingleOrDefaultAsync(company => company.Id == existingAdminCompanyId.Value, cancellationToken);
            }
        }

        if (defaultCompanyInstallation is null)
        {
            var activeCompanies = await dbContext.CompanyInstallations
                .Where(company => company.Status == "active")
                .OrderBy(company => company.CreatedAt)
                .Take(2)
                .ToListAsync(cancellationToken);
            defaultCompanyInstallation = activeCompanies.Count == 1 ? activeCompanies[0] : null;
        }

        if (defaultCompanyInstallation is null)
        {
            throw new InvalidOperationException(
                "Admin seed company could not be resolved. Configure a default company or retain the existing admin account.");
        }

        var admin = await dbContext.Users
            .Include(user => user.Identities)
            .Include(user => user.AdminProfile)
            .SingleOrDefaultAsync(
                user => user.CompanyInstallationId == defaultCompanyInstallation.Id &&
                        user.EmailNormalized == normalizedEmail,
                cancellationToken);

        if (admin is null)
        {
            admin = new ApplicationUser
            {
                CompanyInstallationId = defaultCompanyInstallation.Id,
                Email = adminOptions.Email.Trim(),
                EmailNormalized = normalizedEmail,
                DisplayName = GetDisplayName(adminOptions, normalizedEmail),
                Status = "active",
                Locale = "en-US",
                CreatedAt = now,
                UpdatedAt = now
            };

            admin.Identities.Add(new UserIdentity
            {
                CompanyInstallationId = defaultCompanyInstallation.Id,
                Provider = "local",
                Subject = normalizedEmail,
                EmailAtProvider = admin.Email,
                IsPrimary = true,
                ClaimsJson = """{"role":"Admin"}""",
                CreatedAt = now,
                UpdatedAt = now
            });

            admin.AdminProfile = new AdminProfile
            {
                CompanyInstallationId = defaultCompanyInstallation.Id,
                Role = ApplicationRoles.Admin,
                PermissionsJson = """["*"]""",
                IsBreakGlass = true,
                ApprovedAt = now,
                CreatedAt = now,
                UpdatedAt = now
            };

            dbContext.Users.Add(admin);
        }
        else
        {
            admin.Status = "active";
            admin.DisplayName = string.IsNullOrWhiteSpace(admin.DisplayName)
                ? GetDisplayName(adminOptions, normalizedEmail)
                : admin.DisplayName;

            if (admin.AdminProfile is null)
            {
                admin.AdminProfile = new AdminProfile
                {
                    CompanyInstallationId = defaultCompanyInstallation.Id,
                    Role = ApplicationRoles.Admin,
                    PermissionsJson = """["*"]""",
                    IsBreakGlass = true,
                    ApprovedAt = now,
                    CreatedAt = now,
                    UpdatedAt = now
                };
            }
        }

        var localIdentity = admin.Identities.SingleOrDefault(identity => identity.Provider == "local");
        if (localIdentity is null)
        {
            localIdentity = new UserIdentity
            {
                CompanyInstallationId = defaultCompanyInstallation.Id,
                Provider = "local",
                Subject = normalizedEmail,
                EmailAtProvider = admin.Email,
                IsPrimary = true,
                ClaimsJson = """{"role":"Admin"}""",
                CreatedAt = now,
                UpdatedAt = now
            };

            admin.Identities.Add(localIdentity);
        }

        localIdentity.Subject = normalizedEmail;
        localIdentity.EmailAtProvider = admin.Email;
        localIdentity.IsPrimary = true;
        localIdentity.PasswordHash = passwordHasher.HashPassword(admin, adminOptions.Password);

        await dbContext.SaveChangesAsync(cancellationToken);
    }

    private static void ValidateAdminOptions(AdminSeedOptions adminOptions)
    {
        if (string.IsNullOrWhiteSpace(adminOptions.Email))
        {
            throw new InvalidOperationException("SeedAdmin__Email must be set to seed the admin account.");
        }

        if (string.IsNullOrWhiteSpace(adminOptions.Password))
        {
            throw new InvalidOperationException("SeedAdmin__Password must be set to seed the admin account.");
        }
    }

    private static string GetDisplayName(AdminSeedOptions adminOptions, string normalizedEmail)
    {
        return string.IsNullOrWhiteSpace(adminOptions.DisplayName)
            ? normalizedEmail
            : adminOptions.DisplayName.Trim();
    }
}
