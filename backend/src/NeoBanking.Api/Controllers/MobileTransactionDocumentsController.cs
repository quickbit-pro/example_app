using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Api.Documents;
using NeoBanking.Application.Security;
namespace NeoBanking.Api.Controllers;
[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/transaction-documents")]
public sealed class MobileTransactionDocumentsController(TransactionDocumentService documents) : ApiControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<TransactionDocumentDto>>> List([FromQuery] string transactionId, CancellationToken ct) =>
        Scope(out var company, out var owner) ? ToActionResult(await documents.ListAsync(company, owner, transactionId, ct)) : MissingIdentity<IReadOnlyList<TransactionDocumentDto>>();
    [HttpPost]
    public async Task<ActionResult<TransactionDocumentDto>> Attach([FromBody] AttachTransactionDocumentDto input, CancellationToken ct) =>
        Scope(out var company, out var owner) ? ToActionResult(await documents.AttachAsync(company, owner, input, ct)) : MissingIdentity<TransactionDocumentDto>();
    [HttpDelete("{id:guid}")]
    public async Task<ActionResult<bool>> Remove(Guid id, CancellationToken ct) =>
        Scope(out var company, out var owner) ? ToActionResult(await documents.RemoveAsync(company, owner, id, ct)) : MissingIdentity<bool>();
    private bool Scope(out Guid company, out Guid owner)
    { owner = Guid.Empty; return TryGetCompanyInstallationId(out company) && company != Guid.Empty && TryGetLocalUserId(out var raw) && Guid.TryParse(raw, out owner) && owner != Guid.Empty; }
}
