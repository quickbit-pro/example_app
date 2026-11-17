using Microsoft.AspNetCore.Cors.Infrastructure;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Options;

namespace NeoBanking.Api.Auth;

/// <summary>
/// Refuses sign-up and sign-in calls that do not come from one of this installation's
/// apps. Browsers always name the page a POST comes from, so a request with no Origin,
/// or one from a site that is not in Cors:AllowedOrigins, is a script. Off unless
/// AppOrigin:RequireOnAuth is true, so test installations stay open to tooling.
/// A script can forge the header: this stops casual automation, not a determined caller.
/// </summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class)]
public sealed class RequireAppOriginAttribute : Attribute, IResourceFilter
{
    public const string CorsPolicyName = "BrowserApps";

    public void OnResourceExecuting(ResourceExecutingContext context)
    {
        var http = context.HttpContext;
        var configuration = http.RequestServices.GetRequiredService<IConfiguration>();
        if (!configuration.GetValue("AppOrigin:RequireOnAuth", false)) return;

        var policy = http.RequestServices.GetService<IOptions<CorsOptions>>()?.Value.GetPolicy(CorsPolicyName);
        var allowed = AppOriginCheck.Allows(
            http.Request.Headers.Origin,
            http.Request.Headers.Referer,
            http.Request.Headers.UserAgent,
            http.Request.Host.Value,
            configuration.GetValue("AppOrigin:AllowNativeApps", true),
            origin => policy?.IsOriginAllowed(origin) ?? false);
        if (allowed) return;

        http.RequestServices.GetRequiredService<ILogger<RequireAppOriginAttribute>>().LogInformation(
            "Rejected {Path}: the request did not come from an app origin.", http.Request.Path.Value);
        context.Result = new ObjectResult(new
        {
            code = "auth.app_origin_required",
            message = "This request can only be made from the app."
        })
        { StatusCode = StatusCodes.Status403Forbidden };
    }

    public void OnResourceExecuted(ResourceExecutedContext context)
    {
    }
}

public static class AppOriginCheck
{
    /// <summary>What the Flutter mobile and desktop builds send; they have no page, so no Origin.</summary>
    private const string NativeUserAgentPrefix = "Dart/";

    public static bool Allows(
        string? origin,
        string? referer,
        string? userAgent,
        string? requestHost,
        bool allowNativeApps,
        Func<string, bool> isAllowedOrigin)
    {
        var source = Normalize(origin) ?? Normalize(referer);
        if (source is null)
        {
            return allowNativeApps &&
                userAgent?.StartsWith(NativeUserAgentPrefix, StringComparison.Ordinal) == true;
        }

        // A page served by this API itself (the same host) is one of ours too.
        return isAllowedOrigin(source) ||
            (!string.IsNullOrEmpty(requestHost) &&
             string.Equals(new Uri(source).Authority, requestHost, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>Reduces an Origin or Referer value to scheme://host[:port], or null when it names no site.</summary>
    private static string? Normalize(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            !Uri.TryCreate(value.Trim(), UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp))
        {
            return null;
        }

        return uri.GetLeftPart(UriPartial.Authority);
    }
}
