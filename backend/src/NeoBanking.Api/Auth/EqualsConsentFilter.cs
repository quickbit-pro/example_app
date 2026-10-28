using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Auth;

/// <summary>Old clients cannot bypass reacceptance by calling banking mutations directly.</summary>
public sealed class EqualsConsentFilter(NeoBankingDbContext db, EqualsConsentService consent) : IAsyncActionFilter
{
    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var request = context.HttpContext.Request;
        // Keep reads and risk-reducing cancellations/removals accessible.
        if (HttpMethods.IsGet(request.Method) || HttpMethods.IsHead(request.Method) ||
            HttpMethods.IsDelete(request.Method) || request.Path.Value?.EndsWith("/cancel", StringComparison.OrdinalIgnoreCase) == true)
        {
            await next(); return;
        }
        var principal = context.HttpContext.User;
        if (!Guid.TryParse(principal.FindFirstValue("local_user_id"), out var userId) ||
            !Guid.TryParse(principal.FindFirstValue("company_installation_id"), out var companyId))
        {
            context.Result = new UnauthorizedResult(); return;
        }
        var user = await db.Users.AsNoTracking().SingleOrDefaultAsync(x => x.Id == userId &&
            x.CompanyInstallationId == companyId, context.HttpContext.RequestAborted);
        if (user is null) { context.Result = new UnauthorizedResult(); return; }
        var status = await consent.StatusAsync(user, context.HttpContext.RequestAborted);
        if (status.RequiresAcceptance)
        {
            context.Result = new ObjectResult(new { code = "equals.consent_required",
                message = "Review and accept the current Equals Money agreements before continuing." }) { StatusCode = 428 };
            return;
        }
        await next();
    }
}
