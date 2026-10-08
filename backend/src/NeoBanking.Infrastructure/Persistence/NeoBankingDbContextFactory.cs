#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace NeoBanking.Infrastructure.Persistence;

public sealed class NeoBankingDbContextFactory : IDesignTimeDbContextFactory<NeoBankingDbContext>
{
    public NeoBankingDbContext CreateDbContext(string[] args)
    {
        var connectionString =
            Environment.GetEnvironmentVariable("ConnectionStrings__NeoBankingDb") ??
            Environment.GetEnvironmentVariable("Database__ConnectionString") ??
            "Host=localhost;Database=neobanking;Username=postgres";

        var optionsBuilder = new DbContextOptionsBuilder<NeoBankingDbContext>();
        optionsBuilder.UseNpgsql(DatabaseConnectionString.Normalize(connectionString));

        return new NeoBankingDbContext(optionsBuilder.Options);
    }
}
