using System.Net.Mail;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Application.DTOs.Branding;
using NeoBanking.Application.Security;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin/mobile-design")]
public sealed partial class AdminMobileDesignController(
    NeoBankingDbContext dbContext,
    IOptions<CompanyOptions> companyOptions) : ApiControllerBase
{
    private const string SettingsKey = "mobileDesign";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [HttpGet]
    public async Task<ActionResult<MobileDesignDto>> Get(CancellationToken cancellationToken)
    {
        var company = await TenantCompany(cancellationToken);
        return company is null ? Unauthorized() : Ok(ReadDesign(company));
    }

    [HttpPut]
    public async Task<ActionResult<MobileDesignDto>> Update(
        [FromBody] UpdateMobileDesignRequestDto request,
        CancellationToken cancellationToken)
    {
        var company = await TenantCompany(cancellationToken);
        if (company is null)
        {
            return Unauthorized();
        }

        var errors = Validate(request);
        if (errors.Count > 0)
        {
            return BadRequest(new ValidationProblemDetails(errors)
            {
                Title = "Check the mobile design fields and try again.",
                Status = StatusCodes.Status400BadRequest
            });
        }

        var before = ReadDesign(company);
        var updated = Normalize(request, company);
        var settings = ReadSettings(company.SettingsJson);
        settings[SettingsKey] = JsonSerializer.SerializeToElement(updated, JsonOptions);
        company.SettingsJson = JsonSerializer.Serialize(settings, JsonOptions);

        dbContext.AuditLogEntries.Add(new AuditLogEntry
        {
            CompanyInstallationId = company.Id,
            ActorUserId = TryGetLocalUserId(out var actorId) && Guid.TryParse(actorId, out var parsedActorId)
                ? parsedActorId
                : null,
            Action = "mobile_design.updated",
            EntityType = "company_mobile_design",
            EntityId = company.Id,
            TraceId = HttpContext.TraceIdentifier,
            IpAddress = GetClientIpAddress(),
            UserAgent = Request.Headers.UserAgent.ToString(),
            BeforeJson = JsonSerializer.Serialize(before, JsonOptions),
            AfterJson = JsonSerializer.Serialize(updated, JsonOptions),
            MetadataJson = "{\"source\":\"wl_admin\"}"
        });

        await dbContext.SaveChangesAsync(cancellationToken);
        return Ok(updated);
    }

    [HttpGet("export")]
    public async Task<IActionResult> Export(CancellationToken cancellationToken)
    {
        var company = await TenantCompany(cancellationToken);
        if (company is null)
        {
            return Unauthorized();
        }

        var design = ReadDesign(company);
        var buildDefinitions = new SortedDictionary<string, string>(StringComparer.Ordinal)
        {
            ["APP_ACCENT_COLOR"] = design.AccentColor,
            ["APP_FONT_FAMILY"] = design.FontFamily,
            ["APP_LOGO_ASSET"] = design.LogoAsset,
            ["APP_LOGIN_BACKGROUND_COLOR"] = design.LoginBackgroundColor,
            ["APP_NAME"] = design.AppName,
            ["APP_PRIMARY_COLOR"] = design.PrimaryColor,
            ["APP_THEME_MODE"] = design.ThemeMode,
            ["LEGAL_ENTITY"] = design.LegalEntity,
            ["SUPPORT_EMAIL"] = design.SupportEmail,
            ["SUPPORT_PHONE"] = design.SupportPhone
        };
        var bytes = JsonSerializer.SerializeToUtf8Bytes(buildDefinitions, new JsonSerializerOptions
        {
            WriteIndented = true
        });

        return File(bytes, "application/json", $"{SafeFileName(company.Slug)}-flutter-design.json");
    }

    private async Task<CompanyInstallation?> TenantCompany(CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return null;
        }

        return await dbContext.CompanyInstallations
            .SingleOrDefaultAsync(company => company.Id == companyId, cancellationToken);
    }

    private MobileDesignDto ReadDesign(CompanyInstallation company)
    {
        var settings = ReadSettings(company.SettingsJson);
        if (settings.TryGetValue(SettingsKey, out var stored))
        {
            try
            {
                var design = stored.Deserialize<MobileDesignDto>(JsonOptions);
                if (design is not null)
                {
                    return design;
                }
            }
            catch (JsonException)
            {
                // Invalid legacy settings fall back to safe company defaults.
            }
        }

        var branding = companyOptions.Value.Branding;
        return new MobileDesignDto
        {
            AppName = First(companyOptions.Value.BrandName, company.DisplayName, company.LegalName, "Mobile Banking"),
            PrimaryColor = NormalizeHex(branding.PrimaryColor, "7C5CFF"),
            AccentColor = "B6FF6E",
            LoginBackgroundColor = string.Empty,
            ThemeMode = "dark",
            SupportEmail = branding.SupportEmail?.Trim() ?? string.Empty,
            LegalEntity = company.LegalName
        };
    }

    private static MobileDesignDto Normalize(UpdateMobileDesignRequestDto request, CompanyInstallation company) =>
        new()
        {
            AppName = request.AppName!.Trim(),
            PrimaryColor = NormalizeHex(request.PrimaryColor, "7C5CFF"),
            AccentColor = NormalizeHex(request.AccentColor, "B6FF6E"),
            LoginBackgroundColor = NormalizeOptionalHex(request.LoginBackgroundColor),
            ThemeMode = request.ThemeMode!.Trim().ToLowerInvariant(),
            FontFamily = request.FontFamily?.Trim() ?? string.Empty,
            LogoAsset = request.LogoAsset?.Trim() ?? string.Empty,
            SupportEmail = request.SupportEmail?.Trim() ?? string.Empty,
            SupportPhone = request.SupportPhone?.Trim() ?? string.Empty,
            LegalEntity = First(request.LegalEntity, company.LegalName, company.DisplayName),
            UpdatedAt = DateTimeOffset.UtcNow
        };

    private static Dictionary<string, JsonElement> ReadSettings(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind == JsonValueKind.Object)
            {
                return document.RootElement.EnumerateObject()
                    .ToDictionary(property => property.Name, property => property.Value.Clone(), StringComparer.Ordinal);
            }
        }
        catch (JsonException)
        {
            // Preserve availability even if a legacy settings document is malformed.
        }

        return new Dictionary<string, JsonElement>(StringComparer.Ordinal);
    }

    internal static Dictionary<string, string[]> Validate(UpdateMobileDesignRequestDto request)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        AddRequired(errors, "appName", request.AppName, 80, "App name");
        AddHex(errors, "primaryColor", request.PrimaryColor, "Primary color");
        AddHex(errors, "accentColor", request.AccentColor, "Accent color");
        AddOptionalHex(errors, "loginBackgroundColor", request.LoginBackgroundColor, "Login background color");

        if (request.ThemeMode?.Trim().ToLowerInvariant() is not ("light" or "dark" or "system"))
        {
            errors["themeMode"] = ["Theme mode must be light, dark, or system."];
        }

        AddMaximum(errors, "fontFamily", request.FontFamily, 80, "Font family");
        AddMaximum(errors, "logoAsset", request.LogoAsset, 240, "Logo asset path");
        AddMaximum(errors, "supportEmail", request.SupportEmail, 320, "Support email");
        AddMaximum(errors, "supportPhone", request.SupportPhone, 40, "Support phone");
        AddMaximum(errors, "legalEntity", request.LegalEntity, 160, "Legal entity");

        var logoAsset = request.LogoAsset?.Trim();
        if (!string.IsNullOrWhiteSpace(logoAsset) &&
            (!logoAsset.StartsWith("assets/", StringComparison.Ordinal) || logoAsset.Contains("..", StringComparison.Ordinal)))
        {
            errors["logoAsset"] = ["Logo asset must be a safe relative path beginning with assets/."];
        }

        var email = request.SupportEmail?.Trim();
        if (!string.IsNullOrWhiteSpace(email) && !MailAddress.TryCreate(email, out _))
        {
            errors["supportEmail"] = ["Enter a valid support email address."];
        }

        return errors;
    }

    private static void AddRequired(
        IDictionary<string, string[]> errors,
        string key,
        string? value,
        int maximum,
        string label)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            errors[key] = [$"{label} is required."];
        }
        else if (value.Trim().Length > maximum)
        {
            errors[key] = [$"{label} must be {maximum} characters or fewer."];
        }
    }

    private static void AddMaximum(
        IDictionary<string, string[]> errors,
        string key,
        string? value,
        int maximum,
        string label)
    {
        if (value?.Trim().Length > maximum)
        {
            errors[key] = [$"{label} must be {maximum} characters or fewer."];
        }
    }

    private static void AddHex(
        IDictionary<string, string[]> errors,
        string key,
        string? value,
        string label)
    {
        var normalized = value?.Trim().TrimStart('#') ?? string.Empty;
        if (!HexColor().IsMatch(normalized))
        {
            errors[key] = [$"{label} must be a six-digit hexadecimal color."];
        }
    }

    private static void AddOptionalHex(
        IDictionary<string, string[]> errors,
        string key,
        string? value,
        string label)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return;
        }

        AddHex(errors, key, value, label);
    }

    private static string NormalizeOptionalHex(string? value) =>
        string.IsNullOrWhiteSpace(value) ? string.Empty : NormalizeHex(value, string.Empty);

    internal static string NormalizeHex(string? value, string fallback)
    {
        var normalized = value?.Trim().TrimStart('#').ToUpperInvariant();
        return normalized is not null && HexColor().IsMatch(normalized) ? normalized : fallback;
    }

    private static string First(params string?[] values) =>
        values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value))?.Trim() ?? string.Empty;

    private static string SafeFileName(string value)
    {
        var safe = Regex.Replace(value.ToLowerInvariant(), "[^a-z0-9-]+", "-").Trim('-');
        return string.IsNullOrWhiteSpace(safe) ? "wl" : safe;
    }

    [GeneratedRegex("^[0-9A-Fa-f]{6}$", RegexOptions.CultureInvariant)]
    private static partial Regex HexColor();
}
