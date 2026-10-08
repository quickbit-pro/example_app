using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Documents;
using NeoBanking.Application.Security;
namespace NeoBanking.Api.Controllers;
[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/documents")]
public sealed class MobileDocumentsController(DocumentService documents) : ApiControllerBase
{
    [HttpPost]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(DocumentService.MaxBytes + 64 * 1024)]
    [RequestFormLimits(MemoryBufferThreshold = DocumentService.MaxBytes, MultipartBodyLengthLimit = DocumentService.MaxBytes)]
    public async Task<ActionResult<DocumentDto>> Upload([FromForm(Name="file")] IFormFile? file, CancellationToken ct) =>
        Scope(out var company, out var owner) ? ToActionResult(await documents.UploadAsync(company, owner, file, ct)) : MissingIdentity<DocumentDto>();
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<DocumentDto>>> List(CancellationToken ct) =>
        Scope(out var company, out var owner) ? Ok(await documents.ListAsync(company, owner, ct)) : MissingIdentity<IReadOnlyList<DocumentDto>>();
    [HttpGet("{id:guid}/content")]
    public async Task<IActionResult> Download(Guid id, CancellationToken ct)
    {
        if (!Scope(out var company, out var owner)) return Unauthorized();
        var document = await documents.FindAsync(company, owner, id, ct);
        if (document is null) return NotFound();
        Response.Headers.CacheControl = "private, no-store";
        Response.Headers.XContentTypeOptions = "nosniff";
        try { return File(await documents.ReadAsync(document, ct), document.ContentType, document.FileName); }
        catch (Azure.RequestFailedException e) when (e.Status == 404) { return NotFound(); }
    }
    private bool Scope(out Guid company, out Guid owner)
    { owner = Guid.Empty; return TryGetCompanyInstallationId(out company) && company != Guid.Empty && TryGetLocalUserId(out var raw) && Guid.TryParse(raw, out owner) && owner != Guid.Empty; }
}
