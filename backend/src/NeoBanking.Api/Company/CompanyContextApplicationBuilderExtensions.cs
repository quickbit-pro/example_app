namespace NeoBanking.Api.Company;

public static class CompanyContextApplicationBuilderExtensions
{
    public static IApplicationBuilder UseCompanyContext(this IApplicationBuilder app)
    {
        return app.UseMiddleware<CompanyContextMiddleware>();
    }
}
