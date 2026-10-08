using Microsoft.AspNetCore.Mvc;

namespace NeoBanking.Api.Middleware;

public sealed class ApiExceptionHandlingMiddleware(
    RequestDelegate next,
    ILogger<ApiExceptionHandlingMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context).ConfigureAwait(false);
        }
        catch (Exception exception) when (!context.Response.HasStarted)
        {
            logger.LogError(
                exception,
                "Unhandled API exception for {Method} {Path}.",
                context.Request.Method,
                context.Request.Path);

            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
            context.Response.ContentType = "application/problem+json";

            await context.Response.WriteAsJsonAsync(
                new ProblemDetails
                {
                    Title = "Internal server error",
                    Detail = "The API hit an unexpected error. Check backend logs with the returned trace ID.",
                    Status = StatusCodes.Status500InternalServerError,
                    Instance = context.Request.Path
                },
                context.RequestAborted).ConfigureAwait(false);
        }
    }
}
