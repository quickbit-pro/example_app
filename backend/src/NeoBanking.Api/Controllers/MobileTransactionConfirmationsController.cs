using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.Interfaces;
using NeoBanking.Application.Security;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/transactions")]
public sealed class MobileTransactionConfirmationsController(IHoppaClient client) : ApiControllerBase
{
    [HttpGet("{transactionId:int:min(1)}/equals-money/payment-confirmation")]
    public async Task<IActionResult> Download(int transactionId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId) || !int.TryParse(userId, out var numericUserId) || numericUserId <= 0)
            return MissingHoppaUser<JsonElement?>().Result!;
        if (transactionId <= 0) return BadRequest();

        // Identity comes exclusively from the authenticated session. The upstream
        // endpoint checks ownership, provider and payment ID before fetching the PDF.
        var result = await client.DownloadAsync(new HoppaRequest<object?>
        {
            Path = $"/api/v2/transactions/{transactionId.ToString(CultureInfo.InvariantCulture)}/equals-money/payment-confirmation",
            Query = Query(("userId", numericUserId)),
            SuppressPayloadLogging = true,
            FailureCode = "mobile.transactions.confirmation.failed",
            FailureMessage = "Could not download the payment confirmation. Please try again."
        }, cancellationToken);
        Response.Headers.CacheControl = "no-store";
        if (!result.IsSuccess) return ToActionResult(result).Result!;
        Response.RegisterForDispose(result.Value!);
        return File(result.Value!.Content, "application/pdf", $"equals-payment-confirmation-{transactionId}.pdf");
    }
}
