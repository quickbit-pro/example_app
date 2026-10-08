using System.Globalization;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace NeoBanking.Api.Auth;

public sealed class JwtBearerAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    IOptions<JwtOptions> jwtOptions,
    ILoggerFactory logger,
    UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    private readonly JwtOptions _jwtOptions = jwtOptions.Value;

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue("Authorization", out var authorizationHeaders))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var authorization = authorizationHeaders.ToString();
        if (!authorization.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var token = authorization["Bearer ".Length..].Trim();
        if (string.IsNullOrWhiteSpace(token))
        {
            return Task.FromResult(AuthenticateResult.Fail("Bearer token is empty."));
        }

        try
        {
            var principal = ValidateToken(token);
            var ticket = new AuthenticationTicket(principal, AuthenticationSchemeNames.Bearer);

            return Task.FromResult(AuthenticateResult.Success(ticket));
        }
        catch (Exception ex) when (ex is JsonException or FormatException or CryptographicException
            or InvalidOperationException or KeyNotFoundException)
        {
            Logger.LogDebug(ex, "JWT bearer authentication failed.");
            return Task.FromResult(AuthenticateResult.Fail("Bearer token is invalid."));
        }
    }

    private ClaimsPrincipal ValidateToken(string token)
    {
        if (string.IsNullOrWhiteSpace(_jwtOptions.SigningKey))
        {
            throw new InvalidOperationException("JWT signing key is not configured.");
        }

        var parts = token.Split('.');
        if (parts.Length != 3)
        {
            throw new FormatException("JWT must have three sections.");
        }

        using var headerDocument = JsonDocument.Parse(Base64UrlDecode(parts[0]));
        var algorithm = headerDocument.RootElement.GetProperty("alg").GetString();
        if (!string.Equals(algorithm, "HS256", StringComparison.Ordinal))
        {
            throw new InvalidOperationException("Only HS256 JWTs are supported by the foundation handler.");
        }

        VerifySignature(parts[0], parts[1], parts[2]);

        using var payloadDocument = JsonDocument.Parse(Base64UrlDecode(parts[1]));
        var payload = payloadDocument.RootElement;
        ValidateIssuer(payload);
        ValidateAudience(payload);
        ValidateLifetime(payload);

        var identity = new ClaimsIdentity(AuthenticationSchemeNames.Bearer, ClaimTypes.Name, ClaimTypes.Role);
        AddClaims(identity, payload);

        return new ClaimsPrincipal(identity);
    }

    private void VerifySignature(string encodedHeader, string encodedPayload, string encodedSignature)
    {
        var keyBytes = Encoding.UTF8.GetBytes(_jwtOptions.SigningKey);
        var signedData = Encoding.ASCII.GetBytes($"{encodedHeader}.{encodedPayload}");

        using var hmac = new HMACSHA256(keyBytes);
        var expectedSignature = hmac.ComputeHash(signedData);
        var actualSignature = Base64UrlDecode(encodedSignature);

        if (expectedSignature.Length != actualSignature.Length ||
            !CryptographicOperations.FixedTimeEquals(expectedSignature, actualSignature))
        {
            throw new CryptographicException("JWT signature verification failed.");
        }
    }

    private void ValidateIssuer(JsonElement payload)
    {
        if (string.IsNullOrWhiteSpace(_jwtOptions.Issuer))
        {
            return;
        }

        var issuer = GetString(payload, "iss");
        if (!string.Equals(issuer, _jwtOptions.Issuer, StringComparison.Ordinal))
        {
            throw new InvalidOperationException("JWT issuer is invalid.");
        }
    }

    private void ValidateAudience(JsonElement payload)
    {
        if (string.IsNullOrWhiteSpace(_jwtOptions.Audience))
        {
            return;
        }

        if (!AudienceMatches(payload, _jwtOptions.Audience))
        {
            throw new InvalidOperationException("JWT audience is invalid.");
        }
    }

    private void ValidateLifetime(JsonElement payload)
    {
        var now = DateTimeOffset.UtcNow;
        var skew = TimeSpan.FromSeconds(Math.Max(0, _jwtOptions.ClockSkewSeconds));

        if (TryGetUnixTime(payload, "nbf", out var notBefore) && now.Add(skew) < notBefore)
        {
            throw new InvalidOperationException("JWT is not active yet.");
        }

        if (!TryGetUnixTime(payload, "exp", out var expires))
        {
            throw new InvalidOperationException("JWT expiration is required.");
        }

        if (now.Subtract(skew) >= expires)
        {
            throw new InvalidOperationException("JWT has expired.");
        }
    }

    private static bool AudienceMatches(JsonElement payload, string expectedAudience)
    {
        if (!payload.TryGetProperty("aud", out var audienceElement))
        {
            return false;
        }

        if (audienceElement.ValueKind == JsonValueKind.String)
        {
            return string.Equals(audienceElement.GetString(), expectedAudience, StringComparison.Ordinal);
        }

        if (audienceElement.ValueKind != JsonValueKind.Array)
        {
            return false;
        }

        return audienceElement.EnumerateArray().Any(audience =>
            audience.ValueKind == JsonValueKind.String &&
            string.Equals(audience.GetString(), expectedAudience, StringComparison.Ordinal));
    }

    private static void AddClaims(ClaimsIdentity identity, JsonElement payload)
    {
        foreach (var property in payload.EnumerateObject())
        {
            AddClaim(identity, property.Name, property.Value);
        }

        AddMappedClaim(identity, payload, "sub", ClaimTypes.NameIdentifier);
        AddMappedClaim(identity, payload, "name", ClaimTypes.Name);
        AddRolesFromClaim(identity, payload, "role");
        AddRolesFromClaim(identity, payload, "roles");
    }

    private static void AddClaim(ClaimsIdentity identity, string type, JsonElement value)
    {
        switch (value.ValueKind)
        {
            case JsonValueKind.String:
                identity.AddClaim(new Claim(type, value.GetString() ?? string.Empty));
                break;
            case JsonValueKind.Number:
            case JsonValueKind.True:
            case JsonValueKind.False:
                identity.AddClaim(new Claim(type, value.ToString()));
                break;
            case JsonValueKind.Array:
                foreach (var item in value.EnumerateArray())
                {
                    AddClaim(identity, type, item);
                }

                break;
        }
    }

    private static void AddMappedClaim(ClaimsIdentity identity, JsonElement payload, string sourceType, string targetType)
    {
        var value = GetString(payload, sourceType);
        if (!string.IsNullOrWhiteSpace(value) && !identity.HasClaim(targetType, value))
        {
            identity.AddClaim(new Claim(targetType, value));
        }
    }

    private static void AddRolesFromClaim(ClaimsIdentity identity, JsonElement payload, string sourceType)
    {
        if (!payload.TryGetProperty(sourceType, out var roleElement))
        {
            return;
        }

        if (roleElement.ValueKind == JsonValueKind.String)
        {
            AddRole(identity, roleElement.GetString());
            return;
        }

        if (roleElement.ValueKind != JsonValueKind.Array)
        {
            return;
        }

        foreach (var role in roleElement.EnumerateArray())
        {
            if (role.ValueKind == JsonValueKind.String)
            {
                AddRole(identity, role.GetString());
            }
        }
    }

    private static void AddRole(ClaimsIdentity identity, string? role)
    {
        if (!string.IsNullOrWhiteSpace(role) && !identity.HasClaim(ClaimTypes.Role, role))
        {
            identity.AddClaim(new Claim(ClaimTypes.Role, role));
        }
    }

    private static string? GetString(JsonElement payload, string propertyName)
    {
        return payload.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
    }

    private static bool TryGetUnixTime(JsonElement payload, string propertyName, out DateTimeOffset value)
    {
        value = default;
        if (!payload.TryGetProperty(propertyName, out var property))
        {
            return false;
        }

        if (property.ValueKind == JsonValueKind.Number && property.TryGetInt64(out var seconds))
        {
            value = DateTimeOffset.FromUnixTimeSeconds(seconds);
            return true;
        }

        if (property.ValueKind == JsonValueKind.String &&
            long.TryParse(property.GetString(), CultureInfo.InvariantCulture, out seconds))
        {
            value = DateTimeOffset.FromUnixTimeSeconds(seconds);
            return true;
        }

        return false;
    }

    private static byte[] Base64UrlDecode(string input)
    {
        var output = input.Replace('-', '+').Replace('_', '/');
        output = output.PadRight(output.Length + ((4 - output.Length % 4) % 4), '=');

        return Convert.FromBase64String(output);
    }
}
