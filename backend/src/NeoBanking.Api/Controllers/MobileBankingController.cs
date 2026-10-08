using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Banking;
using NeoBanking.Application.Security;
using NeoBanking.Application.UseCases.Hoppa;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.User)]
[Route("api/v1/mobile/banking")]
public sealed class MobileBankingController : ApiControllerBase
{
    private readonly IProxyHoppaRequestUseCase _proxyHoppa;

    public MobileBankingController(IProxyHoppaRequestUseCase proxyHoppa)
    {
        _proxyHoppa = proxyHoppa;
    }

    [HttpGet("accounts")]
    public async Task<ActionResult<JsonElement?>> ListAccounts(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "banking/accounts",
            null,
            "mobile.banking.accounts.list.failed",
            "We could not list accounts.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpGet("receiving-accounts")]
    public async Task<ActionResult<JsonElement?>> ListReceivingAccounts(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        // This account roster preserves the provider's exact budget identity
        // and linked bank details. Scope it only to the authenticated user.
        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "baas/accounts",
            null,
            "mobile.banking.receiving_accounts.list.failed",
            "We could not load receiving account details.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpGet("providers")]
    public async Task<ActionResult<JsonElement?>> ListProviders(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "banking/providers",
            null,
            "mobile.banking.providers.list.failed",
            "We could not list banking providers.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("equalsmoney-onboarding")]
    public async Task<ActionResult<JsonElement?>> SubmitEqualsMoneyOnboarding(
        [FromForm] EqualsMoneyOnboardingFormDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var validationError = ValidateEqualsMoneyOnboarding(request);
        if (validationError is not null)
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(validationError));
        }

        // Use the authenticated user's live identity decision, never a caller flag.
        var identity = await _proxyHoppa.ExecuteAsync(new ProxyHoppaRequestCommand<object?>
        {
            Method = HttpMethod.Get,
            UpstreamPath = $"/api/v2/users/{Segment(userId)}/kyc/detailed-status",
            FailureCode = "mobile.banking.identity_status.failed",
            FailureMessage = "We could not verify your identity status. Please try again."
        }, cancellationToken);
        if (!identity.IsSuccess)
        {
            return ToActionResult(identity);
        }
        if (!HasApprovedIdentity(identity.Value))
        {
            return ToActionResult(ApplicationResult<JsonElement?>.Failure(new ApplicationError(
                "mobile.banking.identity_verification.required",
                "Complete identity verification and wait for approval before starting EqualsMoney onboarding.",
                StatusCodes.Status403Forbidden)));
        }

        using var form = BuildEqualsMoneyOnboardingForm(request);

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/equalsmoney-onboarding",
            form,
            "mobile.banking.equalsmoney_onboarding.failed",
            "We could not submit EqualsMoney onboarding.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpGet("equals-banking-info")]
    public async Task<ActionResult<JsonElement?>> GetEqualsBankingInfo(
        [FromQuery] string? currency,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"banking/users/{Segment(userId)}/equals-banking-info",
            null,
            "mobile.banking.equals_banking_info.failed",
            "We could not load EqualsMoney banking info.",
            cancellationToken,
            Query(("currency", currency))));
    }

    [HttpGet("balance")]
    public async Task<ActionResult<JsonElement?>> GetBalance(
        [FromQuery] string? currency,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "banking/balance",
            null,
            "mobile.banking.balance.failed",
            "We could not load banking balance.",
            cancellationToken,
            Query(("userId", userId), ("currency", currency))));
    }

    [HttpGet("wallets")]
    public async Task<ActionResult<JsonElement?>> ListWallets(
        [FromQuery] string? id,
        [FromQuery] string? nickname,
        [FromQuery] string? currency,
        [FromQuery] bool? master,
        [FromQuery] string? referenceId,
        [FromQuery] int? limit,
        [FromQuery] int? page,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        var wallets = await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"users/{Segment(userId)}/wallets",
            null,
            "mobile.banking.wallets.list.failed",
            "We could not list wallets.",
            cancellationToken,
            Query(
                ("id", id),
                ("nickname", nickname),
                ("currency", currency),
                ("master", master),
                ("referenceId", referenceId),
                ("limit", limit),
                ("page", page)));

        if (wallets.IsSuccess || wallets.Error!.StatusCode < 500)
        {
            return ToActionResult(wallets);
        }

        var assets = await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"users/{Segment(userId)}/assets",
            null,
            "mobile.banking.wallets.assets_fallback.failed",
            "We could not list wallet assets.",
            cancellationToken);

        return ToActionResult(assets.IsSuccess ? assets : wallets);
    }

    [HttpGet("assets")]
    public async Task<ActionResult<JsonElement?>> ListAssets(
        [FromQuery] string? interlaceAccountId,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"users/{Segment(userId)}/assets",
            null,
            "mobile.banking.assets.list.failed",
            "We could not list assets.",
            cancellationToken,
            Query(("interlaceAccountId", interlaceAccountId))));
    }

    [HttpGet("crypto-addresses")]
    [HttpGet("deposit-addresses")]
    public async Task<ActionResult<JsonElement?>> ListCryptoAddresses(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"users/{Segment(userId)}/crypto-addresses",
            null,
            "mobile.banking.crypto_addresses.list.failed",
            "We could not list crypto deposit addresses.",
            cancellationToken));
    }

    [HttpGet("accounts/{accountId}")]
    public async Task<ActionResult<JsonElement?>> GetAccount(string accountId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "banking/accounts",
            null,
            "mobile.banking.accounts.get.failed",
            "We could not load account.",
            cancellationToken,
            Query(("userId", userId), ("accountId", accountId))));
    }

    [HttpGet("accounts/{accountId}/balances")]
    public async Task<ActionResult<JsonElement?>> GetBalances(string accountId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "banking/balance",
            null,
            "mobile.banking.balances.failed",
            "We could not load balances.",
            cancellationToken,
            Query(("userId", userId), ("accountId", accountId))));
    }

    [HttpPost("accounts/fund-test")]
    public async Task<ActionResult<JsonElement?>> FundTestAccount(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/accounts/fund-test",
            NormalizeFundTestAccountRequest(request),
            "mobile.banking.accounts.fund_test.failed",
            "We could not fund the sandbox account.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpGet("accounts/{accountId}/transactions")]
    public async Task<ActionResult<JsonElement?>> ListAccountTransactions(
        string accountId,
        [FromQuery] DateOnly? from,
        [FromQuery] DateOnly? to,
        [FromQuery] int? limit,
        [FromQuery] string? cursor,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "banking/transactions",
            null,
            "mobile.banking.transactions.list.failed",
            "We could not list account transactions.",
            cancellationToken,
            Query(("userId", userId), ("From", from), ("To", to), ("PageSize", limit), ("accountId", accountId), ("cursor", cursor))));
    }

    [HttpGet("transactions")]
    public async Task<ActionResult<JsonElement?>> ListBankingTransactions(
        [FromQuery] string? currency,
        [FromQuery] DateOnly? from,
        [FromQuery] DateOnly? to,
        [FromQuery] int? page,
        [FromQuery] int? pageSize,
        [FromQuery] string? provider,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "banking/transactions",
            null,
            "mobile.banking.transactions.list.failed",
            "We could not list banking transactions.",
            cancellationToken,
            Query(
                ("userId", userId),
                ("Currency", currency),
                ("From", from),
                ("To", to),
                ("Page", page),
                ("PageSize", pageSize),
                ("Provider", provider))));
    }

    [HttpPost("quotes")]
    [HttpPost("quotations")]
    public async Task<ActionResult<JsonElement?>> CreateQuote(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/quotations",
            WithQuotationUserId(request, userId),
            "mobile.banking.quotations.create.failed",
            "We could not create quote.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("payouts/check")]
    public async Task<ActionResult<JsonElement?>> CheckPayout(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/payouts/check",
            WithUpstreamUserId(request, userId),
            "mobile.banking.payouts.check.failed",
            "We could not check payout.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("payouts/initiate")]
    public async Task<ActionResult<JsonElement?>> InitiatePayout(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/payouts/initiate",
            WithUpstreamUserId(request, userId),
            "mobile.banking.payouts.initiate.failed",
            "We could not initiate payout verification.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("payouts")]
    public async Task<ActionResult<JsonElement?>> CreatePayout(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/payouts",
            WithUpstreamUserId(request, userId),
            "mobile.banking.payouts.create.failed",
            "We could not create payout.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("otp/verify")]
    public async Task<ActionResult<JsonElement?>> VerifyBankingOtp(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/otp/verify",
            WithUpstreamUserId(request, userId),
            "mobile.banking.otp.verify.failed",
            "We could not verify the payout code.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("otp/resend")]
    public async Task<ActionResult<JsonElement?>> ResendBankingOtp(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/otp/resend",
            WithUpstreamUserId(request, userId),
            "mobile.banking.otp.resend.failed",
            "We could not resend the payout code.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("orders/quote")]
    public async Task<ActionResult<JsonElement?>> CreateOrderQuote(
        [FromBody] JsonElement request,
        [FromQuery] string accountId,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        if (string.IsNullOrWhiteSpace(accountId))
        {
            return BadRequest(new { message = "accountId is required" });
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/orders/quote",
            request,
            "mobile.banking.orders.quote.failed",
            "We could not create order quote.",
            cancellationToken,
            Query(("accountId", accountId.Trim()), ("userId", userId))));
    }

    [HttpPost("orders/trade")]
    public async Task<ActionResult<JsonElement?>> CreateOrderTrade(
        [FromBody] JsonElement request,
        [FromQuery] string accountId,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        if (string.IsNullOrWhiteSpace(accountId))
        {
            return BadRequest(new { message = "accountId is required" });
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/orders/trade",
            request,
            "mobile.banking.orders.trade.failed",
            "We could not create order trade.",
            cancellationToken,
            Query(("accountId", accountId.Trim()), ("userId", userId))));
    }

    [HttpPost("accounts/link")]
    public async Task<ActionResult<JsonElement?>> CreateLinkSession(
        [FromBody] LinkBankAccountRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "mobile.banking.accounts.link.unsupported",
            "This action is not available yet.");
    }

    [HttpGet("budgets")]
    public async Task<ActionResult<JsonElement?>> ListBudgets(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"banking/users/{Segment(userId)}/budgets",
            null,
            "mobile.banking.budgets.list.failed",
            "We could not list budgets.",
            cancellationToken));
    }

    [HttpPost("budgets")]
    public async Task<ActionResult<JsonElement?>> CreateBudget(
        [FromBody] CreateBudgetRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            $"banking/users/{Segment(userId)}/budgets",
            CreateBudgetUpstreamRequestDto.From(request),
            "mobile.banking.budgets.create.failed",
            "We could not create a budget.",
            cancellationToken));
    }

    [HttpGet("budgets/{budgetId}")]
    public async Task<ActionResult<JsonElement?>> GetBudget(string budgetId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"banking/users/{Segment(userId)}/budgets/{Segment(budgetId)}",
            null,
            "mobile.banking.budgets.get.failed",
            "We could not load a budget.",
            cancellationToken));
    }

    [HttpPatch("budgets/{budgetId}")]
    public async Task<ActionResult<JsonElement?>> UpdateBudget(
        string budgetId,
        [FromBody] UpdateBudgetRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Put,
            $"banking/users/{Segment(userId)}/budgets/{Segment(budgetId)}",
            request,
            "mobile.banking.budgets.update.failed",
            "We could not update a budget.",
            cancellationToken));
    }

    [HttpPost("budgets/{budgetId}/transfer")]
    public async Task<ActionResult<JsonElement?>> TransferBudget(
        string budgetId,
        [FromBody] TransferBudgetRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            $"banking/users/{Segment(userId)}/budgets/{Segment(budgetId)}/transfer",
            TransferBudgetUpstreamRequestDto.From(request),
            "mobile.banking.budgets.transfer.failed",
            "We could not transfer between budgets.",
            cancellationToken));
    }

    [HttpDelete("budgets/{budgetId}")]
    public async Task<ActionResult<JsonElement?>> DeleteBudget(string budgetId, CancellationToken cancellationToken)
    {
        _ = budgetId;
        _ = cancellationToken;

        return NotImplementedProblem(
            "mobile.banking.budgets.delete.unsupported",
            "This action is not available yet.");
    }

    [HttpGet("payees")]
    public async Task<ActionResult<JsonElement?>> ListPayees(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "banking/payees",
            null,
            "mobile.banking.payees.list.failed",
            "We could not list payees.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpGet("payees/required-fields")]
    public async Task<ActionResult<JsonElement?>> GetPayeeRequiredFields(
        [FromQuery] string? paymentType,
        [FromQuery] string? currency,
        [FromQuery] string? country,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out _))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            string.Empty,
            HttpMethod.Get,
            "banking/payees/required-fields",
            null,
            "mobile.banking.payees.required_fields.failed",
            "We could not load payee required fields.",
            cancellationToken,
            Query(("PaymentType", paymentType), ("Currency", currency), ("Country", country))));
    }

    [HttpPost("payees")]
    public async Task<ActionResult<JsonElement?>> CreatePayee(
        [FromBody] CreatePayeeRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/payees",
            CreatePayeeUpstreamRequestDto.From(request, userId),
            "mobile.banking.payees.create.failed",
            "We could not create a payee.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("payees/confirm")]
    public async Task<ActionResult<JsonElement?>> ConfirmPayee(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/payees/confirm",
            WithUpstreamUserId(request, userId),
            "mobile.banking.payees.confirm.failed",
            "We could not confirm the payee.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPatch("payees/{payeeId}")]
    public async Task<ActionResult<JsonElement?>> UpdatePayee(
        string payeeId,
        [FromBody] UpdatePayeeRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = payeeId;
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "mobile.banking.payees.update.unsupported",
            "This action is not available yet.");
    }

    [HttpDelete("payees/{payeeId}")]
    public async Task<ActionResult<JsonElement?>> DeletePayee(string payeeId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Delete,
            $"banking/payees/{Segment(payeeId)}",
            null,
            "mobile.banking.payees.delete.failed",
            "We could not delete a payee.",
            cancellationToken));
    }

    [HttpGet("transfers")]
    public async Task<ActionResult<JsonElement?>> ListTransfers(
        [FromQuery] string? status,
        [FromQuery] int? limit,
        [FromQuery] string? cursor,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "banking/transactions",
            null,
            "mobile.banking.transfers.list.failed",
            "We could not list transfers.",
            cancellationToken,
            Query(("userId", userId), ("statuses", status), ("pageSize", limit), ("cursor", cursor))));
    }

    [HttpGet("transfers/{transferId}")]
    public async Task<ActionResult<JsonElement?>> GetTransfer(string transferId, CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            $"transfers/{Segment(transferId)}",
            null,
            "mobile.banking.transfers.get.failed",
            "We could not load transfer.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("transfers")]
    public async Task<ActionResult<JsonElement?>> CreateTransfer(
        [FromBody] CreateTransferRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/transfers",
            CreateTransferUpstreamRequestDto.From(request, userId),
            "mobile.banking.transfers.create.failed",
            "We could not create transfer.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("transfers/internal")]
    public async Task<ActionResult<JsonElement?>> CreateInternalTransfer(
        [FromBody] CreateInternalTransferRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "banking/transfers/internal",
            CreateInternalTransferRequestDto.From(request, userId),
            "mobile.banking.transfers.internal.create.failed",
            "We could not create internal transfer.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpGet("transfers/withdrawals/available-balance")]
    public async Task<ActionResult<JsonElement?>> GetWithdrawalAvailableBalance(CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync<object?>(
            userId,
            HttpMethod.Get,
            "transfers/withdrawals/available-balance",
            null,
            "mobile.banking.withdrawals.available_balance.failed",
            "We could not load withdrawal available balance.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("transfers/wallet-topup")]
    public async Task<ActionResult<JsonElement?>> TopUpWallet(
        [FromBody] WalletTopUpRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "transfers/wallet-topup",
            WalletTopUpUpstreamRequestDto.From(request),
            "mobile.banking.wallets.topup.failed",
            "We could not top up wallet.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("transfers/crypto-to-quantum-transfer")]
    public async Task<ActionResult<JsonElement?>> CreateCryptoToQuantumTransfer(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "transfers/crypto-to-quantum-transfer",
            request,
            "mobile.banking.transfers.crypto_to_quantum.failed",
            "We could not transfer crypto to Quantum.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("transfers/quantum-usd-to-crypto-exchange")]
    public async Task<ActionResult<JsonElement?>> CreateQuantumToCryptoExchange(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "transfers/quantum-usd-to-crypto-exchange",
            request,
            "mobile.banking.transfers.quantum_to_crypto.failed",
            "We could not exchange Quantum USD to crypto.",
            cancellationToken,
            UserIdQuery(userId)));
    }

    [HttpPost("transfers/withdrawals/crypto")]
    public async Task<ActionResult<JsonElement?>> CreateCryptoWithdrawal(
        [FromBody] JsonElement request,
        CancellationToken cancellationToken)
    {
        if (!TryGetCurrentUserId(out var userId))
        {
            return MissingIdentity<JsonElement?>();
        }

        return ToActionResult(await SendUserRequestAsync(
            userId,
            HttpMethod.Post,
            "transfers/withdrawals/crypto",
            WithUserId(request, userId),
            "mobile.banking.withdrawals.crypto.failed",
            "We could not create crypto withdrawal.",
            cancellationToken));
    }

    [HttpPost("transfers/{transferId}/cancel")]
    public async Task<ActionResult<JsonElement?>> CancelTransfer(
        string transferId,
        [FromBody] CancelTransferRequestDto request,
        CancellationToken cancellationToken)
    {
        _ = transferId;
        _ = request;
        _ = cancellationToken;

        return NotImplementedProblem(
            "mobile.banking.transfers.cancel.unsupported",
            "This action is not available yet.");
    }

    private Task<NeoBanking.Application.Common.ApplicationResult<JsonElement?>> SendUserRequestAsync<TRequest>(
        string userId,
        HttpMethod method,
        string userRelativePath,
        TRequest? request,
        string failureCode,
        string failureMessage,
        CancellationToken cancellationToken,
        IReadOnlyDictionary<string, string?>? query = null)
    {
        return _proxyHoppa.ExecuteAsync(
            new ProxyHoppaRequestCommand<TRequest>
            {
                Method = method,
                UpstreamPath = $"/api/v2/{userRelativePath}",
                Query = query ?? new Dictionary<string, string?>(),
                Request = request,
                FailureCode = failureCode,
                FailureMessage = failureMessage
            },
            cancellationToken);
    }

    private static IReadOnlyDictionary<string, string?> UserIdQuery(string userId)
    {
        return new Dictionary<string, string?> { ["userId"] = userId };
    }

    private static object WithUpstreamUserId(JsonElement request, string userId)
    {
        var normalizedUserId = int.TryParse(userId, out var numericUserId)
            ? numericUserId
            : (object)userId;

        if (request.ValueKind == JsonValueKind.Object)
        {
            var payload = JsonSerializer.Deserialize<Dictionary<string, object?>>(request.GetRawText())
                ?? new Dictionary<string, object?>();
            payload.Remove("UserId");
            payload.Remove("userId");
            payload["userId"] = normalizedUserId;
            return payload;
        }

        return new Dictionary<string, object?>
        {
            ["userId"] = normalizedUserId,
            ["payload"] = JsonSerializer.Deserialize<object?>(request.GetRawText())
        };
    }

    private static object NormalizeFundTestAccountRequest(JsonElement request)
    {
        if (request.ValueKind != JsonValueKind.Object)
        {
            return new Dictionary<string, object?>();
        }

        var payload = JsonSerializer.Deserialize<Dictionary<string, object?>>(request.GetRawText())
            ?? new Dictionary<string, object?>();
        payload.Remove("userId");
        payload.Remove("UserId");
        CopyIfMissing(payload, "AccountId", "accountId");
        CopyIfMissing(payload, "Amount", "amount");
        CopyIfMissing(payload, "BalanceId", "balanceId");
        CopyIfMissing(payload, "Currency", "currency");

        return payload;
    }

    private static object WithQuotationUserId(JsonElement request, string userId)
    {
        var payload = WithUpstreamUserId(request, userId);
        if (payload is not Dictionary<string, object?> dictionary)
        {
            return payload;
        }

        CopyIfMissing(dictionary, "FromCurrency", "sourceCurrency", "SourceCurrency", "fromCurrency");
        CopyIfMissing(dictionary, "PayeeId", "payeeId");
        CopyIfMissing(dictionary, "Amount", "amount");
        CopyIfMissing(dictionary, "BalanceId", "balanceId");

        return dictionary;
    }

    private static void CopyIfMissing(Dictionary<string, object?> dictionary, string targetKey, params string[] sourceKeys)
    {
        if (dictionary.ContainsKey(targetKey))
        {
            return;
        }

        foreach (var sourceKey in sourceKeys)
        {
            if (dictionary.TryGetValue(sourceKey, out var value))
            {
                dictionary[targetKey] = value;
                return;
            }
        }
    }

    private static MultipartFormDataContent BuildEqualsMoneyOnboardingForm(EqualsMoneyOnboardingFormDto request)
    {
        var form = new MultipartFormDataContent();

        AddValues(form, "RequestedFeatures", request.RequestedFeatures);
        AddValues(form, "MainPurpose", request.MainPurpose);
        AddValues(form, "SourceOfFunds", request.SourceOfFunds);
        AddValues(form, "DestinationOfFunds", request.DestinationOfFunds);
        AddValues(form, "CurrenciesRequired", request.CurrenciesRequired);
        AddValue(form, "AnnualVolume", request.AnnualVolume);
        AddValue(form, "NumberOfPayments", request.NumberOfPayments);
        AddValues(form, "CardPurposes", request.CardPurposes);
        AddValue(form, "CardAnnualSpend", request.CardAnnualSpend);
        AddValue(form, "NumberOfCardsRequired", request.NumberOfCardsRequired);
        AddValue(form, "AtmWithdrawalsRequired", request.AtmWithdrawalsRequired);
        AddValue(form, "ProofOfAddressImage", request.ProofOfAddressImage);
        AddFile(form, "ProofOfAddress", request.ProofOfAddress);

        return form;
    }

    private static bool HasApprovedIdentity(JsonElement? payload)
    {
        if (payload is not { ValueKind: JsonValueKind.Object } value) return false;
        // Bank or card-issuer approval is not an identity decision.
        foreach (var key in new[] { "HoppaCardKycApproved", "hoppaCardKycApproved" })
        {
            if (!value.TryGetProperty(key, out var approval)) continue;
            return approval.ValueKind == JsonValueKind.True ||
                (approval.ValueKind == JsonValueKind.String &&
                 bool.TryParse(approval.GetString(), out var approved) && approved);
        }
        foreach (var key in new[] { "hoppaStatus", "hoppacardStatus", "HoppaCardStatus" })
        {
            if (!value.TryGetProperty(key, out var status) || status.ValueKind != JsonValueKind.String) continue;
            return status.GetString()?.Trim().ToLowerInvariant() is
                "approved" or "verified" or "complete" or "completed" or "active" or "ready";
        }
        return false;
    }

    private static ApplicationError? ValidateEqualsMoneyOnboarding(EqualsMoneyOnboardingFormDto request)
    {
        var errors = new Dictionary<string, string[]>();

        AddRequiredArrayError(errors, nameof(request.RequestedFeatures), request.RequestedFeatures);
        AddRequiredArrayError(errors, nameof(request.MainPurpose), request.MainPurpose);
        AddRequiredArrayError(errors, nameof(request.SourceOfFunds), request.SourceOfFunds);
        AddRequiredArrayError(errors, nameof(request.DestinationOfFunds), request.DestinationOfFunds);
        AddRequiredArrayError(errors, nameof(request.CurrenciesRequired), request.CurrenciesRequired);
        AddRequiredError(errors, nameof(request.AnnualVolume), request.AnnualVolume);
        AddRequiredError(errors, nameof(request.NumberOfPayments), request.NumberOfPayments);

        if (!request.RequestedFeatures.Any(feature =>
                string.Equals(feature, "PAYMENTS", StringComparison.OrdinalIgnoreCase)))
        {
            errors[nameof(request.RequestedFeatures)] = ["PAYMENTS is required."];
        }

        if (request.ProofOfAddress is null && string.IsNullOrWhiteSpace(request.ProofOfAddressImage))
        {
            errors[nameof(request.ProofOfAddress)] = ["Proof of address is required."];
        }

        var requestsCards = request.RequestedFeatures.Any(feature =>
            string.Equals(feature, "CARDS", StringComparison.OrdinalIgnoreCase));
        if (requestsCards)
        {
            AddRequiredArrayError(errors, nameof(request.CardPurposes), request.CardPurposes);
            AddRequiredError(errors, nameof(request.CardAnnualSpend), request.CardAnnualSpend);
            AddRequiredError(errors, nameof(request.NumberOfCardsRequired), request.NumberOfCardsRequired);
            if (request.AtmWithdrawalsRequired is null)
            {
                errors[nameof(request.AtmWithdrawalsRequired)] = ["ATM withdrawal preference is required."];
            }
        }

        return errors.Count == 0
            ? null
            : new ApplicationError(
                "mobile.banking.equalsmoney_onboarding.required_fields",
                "EqualsMoney onboarding is missing required questionnaire fields.",
                StatusCodes.Status400BadRequest,
                validationErrors: errors);
    }

    private static void AddRequiredArrayError(
        Dictionary<string, string[]> errors,
        string key,
        string[] values)
    {
        if (values.Length == 0 || values.All(string.IsNullOrWhiteSpace))
        {
            errors[key] = [$"{key} is required."];
        }
    }

    private static void AddRequiredError(
        Dictionary<string, string[]> errors,
        string key,
        string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            errors[key] = [$"{key} is required."];
        }
    }

    private static void AddValues(MultipartFormDataContent form, string name, IEnumerable<string>? values)
    {
        if (values is null)
        {
            return;
        }

        foreach (var value in values.Where(value => !string.IsNullOrWhiteSpace(value)))
        {
            form.Add(new StringContent(value), name);
        }
    }

    private static void AddValue(MultipartFormDataContent form, string name, object? value)
    {
        if (value is null)
        {
            return;
        }

        form.Add(new StringContent(value.ToString()!), name);
    }

    private static void AddFile(MultipartFormDataContent form, string name, IFormFile? file)
    {
        if (file is null)
        {
            return;
        }

        var content = new StreamContent(file.OpenReadStream());
        if (!string.IsNullOrWhiteSpace(file.ContentType))
        {
            content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue(file.ContentType);
        }

        form.Add(content, name, file.FileName);
    }
}

public sealed class EqualsMoneyOnboardingFormDto
{
    public string[] RequestedFeatures { get; init; } = Array.Empty<string>();

    public string[] MainPurpose { get; init; } = Array.Empty<string>();

    public string[] SourceOfFunds { get; init; } = Array.Empty<string>();

    public string[] DestinationOfFunds { get; init; } = Array.Empty<string>();

    public string[] CurrenciesRequired { get; init; } = Array.Empty<string>();

    public string? AnnualVolume { get; init; }

    public string? NumberOfPayments { get; init; }

    public string[] CardPurposes { get; init; } = Array.Empty<string>();

    public string? CardAnnualSpend { get; init; }

    public string? NumberOfCardsRequired { get; init; }

    public bool? AtmWithdrawalsRequired { get; init; }

    public IFormFile? ProofOfAddress { get; init; }

    public string? ProofOfAddressImage { get; init; }
}
