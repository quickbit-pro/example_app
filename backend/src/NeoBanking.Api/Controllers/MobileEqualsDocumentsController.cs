using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Auth;
using NeoBanking.Api.Company;

namespace NeoBanking.Api.Controllers;

// Registration must work before authentication. Only the server-configured
// documents can be requested; this is not a general-purpose URL proxy.
[AllowAnonymous]
[Route("api/v1/mobile/agreements/equals/documents")]
public sealed class MobileEqualsDocumentsController(EqualsDocumentReader reader, DashboardLegalSettings legalSettings) : ApiControllerBase
{
    [HttpGet("{kind}")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> Get(string kind, CancellationToken ct)
    {
        var documents = EqualsConsentService.Documents(await legalSettings.GetAsync(ct));
        var url = kind switch { "terms" => documents.TermsUrl, "privacy" => documents.PrivacyUrl, _ => null };
        if (url is null) return NotFound();
        try { return Ok(await reader.ReadAsync(url, ct, documents.Version)); }
        catch (Exception error) when (error is HttpRequestException or InvalidDataException or OperationCanceledException)
        {
            return StatusCode(503, new { code = "equals.document_unavailable",
                message = "The document could not be loaded. Please try again or contact support." });
        }
    }
}
