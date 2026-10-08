using System.Linq;
using System.Globalization;
using System.Net;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.Common;

namespace NeoBanking.Api.Controllers;

[ApiController]
public abstract class ApiControllerBase : ControllerBase
{
    protected bool TryGetCompanyInstallationId(out Guid companyInstallationId)
    {
        return Guid.TryParse(User.FindFirstValue("company_installation_id"), out companyInstallationId);
    }

    protected bool TryGetCurrentUserId(out string userId)
    {
        userId = User.FindFirstValue("hoppa_user_id") ?? string.Empty;

        return !string.IsNullOrWhiteSpace(userId);
    }

    protected ActionResult<T> MissingHoppaUser<T>()
    {
        return ToProblemResult<T>(
            new ApplicationError(
                "identity.hoppa_user_missing",
                "Authenticated user is not linked to a Hoppa user. Sign in again or recreate the account so the backend can store the Hoppa user mapping.",
                StatusCodes.Status401Unauthorized));
    }

    protected bool TryGetLocalUserId(out string userId)
    {
        userId = User.FindFirstValue("local_user_id")
            ?? User.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? User.FindFirstValue("sub")
            ?? User.FindFirstValue("user_id")
            ?? User.FindFirstValue("uid")
            ?? string.Empty;

        return !string.IsNullOrWhiteSpace(userId);
    }

    protected string? GetClientIpAddress()
    {
        var forwardedFor = Request.Headers["X-Forwarded-For"].FirstOrDefault();
        var forwardedAddress = forwardedFor?.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        if (IsUsableIpAddress(forwardedAddress))
        {
            return forwardedAddress;
        }

        var realIp = Request.Headers["X-Real-IP"].FirstOrDefault();
        if (IsUsableIpAddress(realIp))
        {
            return realIp;
        }

        return HttpContext.Connection.RemoteIpAddress?.ToString();
    }

    protected static string Segment(string value)
    {
        return Uri.EscapeDataString(value);
    }

    protected static IReadOnlyDictionary<string, string?> Query(params (string Key, object? Value)[] values)
    {
        return values.ToDictionary(
            value => value.Key,
            value => ConvertQueryValue(value.Value));
    }

    protected static IReadOnlyDictionary<string, string?> QueryFromRequest(IQueryCollection query)
    {
        return query.ToDictionary(
            pair => pair.Key,
            pair => pair.Value.Count == 0 ? null : pair.Value.ToString());
    }

    protected static object WithUserId(JsonElement request, string userId)
    {
        var payload = JsonElementToObject(request);
        var normalizedUserId = int.TryParse(userId, out var numericUserId) ? numericUserId : (object)userId;

        if (payload is Dictionary<string, object?> dictionary)
        {
            dictionary.Remove("UserId");
            dictionary.Remove("userId");
            dictionary["UserId"] = normalizedUserId;

            return dictionary;
        }

        return new Dictionary<string, object?>
        {
            ["UserId"] = normalizedUserId,
            ["Payload"] = payload
        };
    }

    protected ActionResult<T> ToActionResult<T>(ApplicationResult<T> result)
    {
        if (result.IsSuccess)
        {
            return Ok(result.Value);
        }

        return ToProblemResult<T>(result.Error!);
    }

    protected ActionResult<T> MissingIdentity<T>()
    {
        return ToProblemResult<T>(
            new ApplicationError(
                "identity.missing",
                "Authenticated user identity is required.",
                StatusCodes.Status401Unauthorized));
    }

    private static bool IsUsableIpAddress(string? value)
    {
        return !string.IsNullOrWhiteSpace(value) && IPAddress.TryParse(value, out _);
    }

    private static string? ConvertQueryValue(object? value)
    {
        return value switch
        {
            null => null,
            DateOnly date => date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            DateTimeOffset dateTime => dateTime.ToString("O", CultureInfo.InvariantCulture),
            IFormattable formattable => formattable.ToString(null, CultureInfo.InvariantCulture),
            _ => value.ToString()
        };
    }

    private static object? JsonElementToObject(JsonElement element)
    {
        return element.ValueKind switch
        {
            JsonValueKind.Object => element.EnumerateObject()
                .ToDictionary(property => ToPascalCase(property.Name), property => JsonElementToObject(property.Value)),
            JsonValueKind.Array => element.EnumerateArray()
                .Select(JsonElementToObject)
                .ToArray(),
            JsonValueKind.String => element.TryGetDateTimeOffset(out var dateTimeOffset)
                ? dateTimeOffset
                : element.GetString(),
            JsonValueKind.Number => element.TryGetInt64(out var integer)
                ? integer
                : element.TryGetDecimal(out var number) ? number : element.GetDouble(),
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.Null => null,
            _ => element.GetRawText()
        };
    }

    private static string ToPascalCase(string value)
    {
        return string.IsNullOrWhiteSpace(value) || char.IsUpper(value[0])
            ? value
            : string.Concat(char.ToUpperInvariant(value[0]), value[1..]);
    }

    protected ObjectResult NotImplementedProblem(string code, string title)
    {
        return ProblemResult(
            new ApplicationError(
                code,
                title,
                StatusCodes.Status501NotImplemented));
    }

    private ActionResult<T> ToProblemResult<T>(ApplicationError error)
    {
        return ProblemResult(error);
    }

    private static readonly System.Text.RegularExpressions.Regex ProviderNamePattern =
        new(@"\bHoppa(?:card)?\b", System.Text.RegularExpressions.RegexOptions.Compiled);

    /// <summary>
    /// Customers never see the provider's name: on mobile routes any leftover
    /// mention is replaced. Admin routes keep it because operators need it.
    /// </summary>
    private string CustomerFacing(string? text)
    {
        if (string.IsNullOrEmpty(text) ||
            !HttpContext.Request.Path.StartsWithSegments("/api/v1/mobile"))
        {
            return text ?? string.Empty;
        }

        return ProviderNamePattern.Replace(text, "the provider");
    }

    private ObjectResult ProblemResult(ApplicationError error)
    {
        if (error.ValidationErrors is not null)
        {
            var validationProblem = new ValidationProblemDetails(
                error.ValidationErrors.ToDictionary(pair => pair.Key, pair => pair.Value))
            {
                Title = CustomerFacing(error.Message),
                Detail = error.Detail is null ? null : CustomerFacing(error.Detail),
                Status = error.StatusCode,
                Instance = HttpContext.Request.Path
            };

            validationProblem.Extensions["code"] = error.Code;
            validationProblem.Extensions["traceId"] = HttpContext.TraceIdentifier;

            return StatusCode(error.StatusCode, validationProblem);
        }

        var problem = new ProblemDetails
        {
            Title = CustomerFacing(error.Message),
            Detail = error.Detail is null ? null : CustomerFacing(error.Detail),
            Status = error.StatusCode,
            Type = $"https://api.neobanking.local/problems/{error.Code}",
            Instance = HttpContext.Request.Path
        };

        problem.Extensions["code"] = error.Code;
        problem.Extensions["traceId"] = HttpContext.TraceIdentifier;

        return StatusCode(error.StatusCode, problem);
    }
}
