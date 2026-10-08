using System.Globalization;
using System.Net.Http;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NeoBanking.Application.Interfaces;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Infrastructure.Admin;

public sealed class AdminCustomerSyncService(
    NeoBankingDbContext dbContext,
    IHoppaClient hoppaClient,
    ILogger<AdminCustomerSyncService> logger,
    IOptions<AdminCustomerSyncOptions>? options = null,
    TimeProvider? timeProvider = null) : IAdminCustomerSyncService
{
    private readonly AdminCustomerSyncOptions settings = options?.Value ?? new();
    private readonly TimeProvider clock = timeProvider ?? TimeProvider.System;
    // Bounded lock storage; worker and admin refresh share a gate for each customer.
    private static readonly SemaphoreSlim[] CustomerGates = Enumerable.Range(0, 256)
        .Select(_ => new SemaphoreSlim(1, 1)).ToArray();

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task SyncCompanyAsync(Guid companyInstallationId, CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        var userIds = await dbContext.Users
            .AsNoTracking()
            .Where(user => user.CompanyInstallationId == companyInstallationId && user.AdminProfile == null)
            .Where(user => !dbContext.AdminCustomerSnapshots.Any(snapshot =>
                snapshot.CompanyInstallationId == companyInstallationId && snapshot.UserId == user.Id &&
                snapshot.NextSyncAt > now &&
                (snapshot.ConsecutiveSyncFailures > 0 ||
                    (snapshot.LastSyncAttemptAt != null &&
                     (snapshot.SyncRequestedAt == null || snapshot.SyncRequestedAt <= snapshot.LastSyncAttemptAt) &&
                     user.UpdatedAt <= snapshot.LastSyncAttemptAt))))
            .OrderBy(user => user.CreatedAt)
            .Select(user => user.Id)
            .ToListAsync(cancellationToken);

        foreach (var userId in userIds)
        {
            try
            {
                await SyncCustomerCoreAsync(companyInstallationId, userId, force: false, cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Could not reconcile admin snapshot for customer {UserId}.", userId);
            }
        }
    }

    public Task<bool> SyncCustomerAsync(Guid companyInstallationId, Guid userId, CancellationToken cancellationToken) =>
        SyncCustomerCoreAsync(companyInstallationId, userId, force: true, cancellationToken);

    private async Task<bool> SyncCustomerCoreAsync(
        Guid companyInstallationId, Guid userId, bool force, CancellationToken cancellationToken)
    {
        var requestedAt = clock.GetUtcNow();
        var gate = CustomerGates[(uint)HashCode.Combine(companyInstallationId, userId) % CustomerGates.Length];
        await gate.WaitAsync(cancellationToken);
        try
        {
            return await SyncCustomerLockedAsync(companyInstallationId, userId, force, requestedAt, cancellationToken);
        }
        finally { gate.Release(); }
    }

    private async Task<bool> SyncCustomerLockedAsync(
        Guid companyInstallationId, Guid userId, bool force, DateTimeOffset requestedAt, CancellationToken cancellationToken)
    {
        var user = await dbContext.Users
            .Include(candidate => candidate.AdminProfile)
            .SingleOrDefaultAsync(candidate =>
                candidate.CompanyInstallationId == companyInstallationId && candidate.Id == userId,
                cancellationToken);

        if (user is null || user.AdminProfile is not null)
        {
            return false;
        }

        var providerUserId = await dbContext.ProviderMappings
            .AsNoTracking()
            .Where(mapping =>
                mapping.CompanyInstallationId == companyInstallationId &&
                mapping.InternalEntityType == "user" &&
                mapping.InternalEntityId == userId &&
                mapping.Provider == "hoppa" &&
                mapping.ProviderEntityType == "user")
            .OrderByDescending(mapping => mapping.UpdatedAt)
            .Select(mapping => mapping.ProviderEntityId)
            .FirstOrDefaultAsync(cancellationToken);

        var onboarding = await dbContext.OnboardingApplications
            .AsNoTracking()
            .Where(application =>
                application.CompanyInstallationId == companyInstallationId &&
                application.ApplicantUserId == userId)
            .OrderByDescending(application => application.UpdatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        var localKyc = await dbContext.KycVerifications
            .AsNoTracking()
            .Where(verification =>
                verification.CompanyInstallationId == companyInstallationId &&
                verification.UserId == userId)
            .OrderByDescending(verification => verification.UpdatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        var localKyb = onboarding is null
            ? null
            : await dbContext.KybVerifications
                .AsNoTracking()
                .Where(verification =>
                    verification.CompanyInstallationId == companyInstallationId &&
                    verification.OnboardingApplicationId == onboarding.Id)
                .OrderByDescending(verification => verification.UpdatedAt)
                .FirstOrDefaultAsync(cancellationToken);

        var snapshot = await dbContext.AdminCustomerSnapshots
            .SingleOrDefaultAsync(candidate =>
                candidate.CompanyInstallationId == companyInstallationId && candidate.UserId == userId,
                cancellationToken) ?? new AdminCustomerSnapshot
            {
                CompanyInstallationId = companyInstallationId,
                UserId = userId
            };

        if (snapshot.Id == default || dbContext.Entry(snapshot).State == EntityState.Detached)
        {
            dbContext.AdminCustomerSnapshots.Add(snapshot);
        }

        // A scoped context may already track an old snapshot when waiting for another refresh.
        if (dbContext.Entry(snapshot).State != EntityState.Added)
            await dbContext.Entry(snapshot).ReloadAsync(cancellationToken);
        var now = clock.GetUtcNow();
        if (snapshot.NextSyncAt > now &&
            (snapshot.ConsecutiveSyncFailures > 0 ||
             snapshot.LastSyncedAt >= requestedAt ||
             (!force && snapshot.LastSyncAttemptAt != null &&
              (snapshot.SyncRequestedAt == null || snapshot.SyncRequestedAt <= snapshot.LastSyncAttemptAt) &&
              user.UpdatedAt <= snapshot.LastSyncAttemptAt && snapshot.ProviderUserId == providerUserId)))
            return true;

        snapshot.LastSyncAttemptAt = now;
        ApplyLocalState(snapshot, user, onboarding, localKyc, localKyb);
        snapshot.ProviderUserId = providerUserId;

        if (string.IsNullOrWhiteSpace(providerUserId))
        {
            snapshot.LastSyncedAt = now;
            snapshot.NextSyncAt = now + settings.RefreshInterval;
            snapshot.ConsecutiveSyncFailures = 0;
            snapshot.LastSyncError = "Customer is not yet connected to the banking provider.";
            await dbContext.SaveChangesAsync(cancellationToken);
            return true;
        }

        var userTask = FetchAsync(
            $"/api/v2/users/{Uri.EscapeDataString(providerUserId)}",
            cancellationToken);
        var verificationTask = FetchAsync(
            $"/api/v2/users/{Uri.EscapeDataString(providerUserId)}/kyc/detailed-status",
            cancellationToken);
        var accountsTask = FetchAsync(
            "/api/v2/banking/accounts",
            cancellationToken,
            ("userId", providerUserId), ("limit", "100"));
        var assetsTask = FetchAsync(
            $"/api/v2/users/{Uri.EscapeDataString(providerUserId)}/assets",
            cancellationToken);
        var budgetsTask = FetchAsync(
            $"/api/v2/banking/users/{Uri.EscapeDataString(providerUserId)}/budgets",
            cancellationToken);
        var cardsTask = FetchAsync(
            "/api/v2/cards",
            cancellationToken,
            ("userId", providerUserId), ("limit", "100"));
        var transactionsTask = FetchTransactionPageAsync(providerUserId, 1, cancellationToken);

        await Task.WhenAll(userTask, verificationTask, accountsTask, assetsTask, budgetsTask, cardsTask, transactionsTask);

        var providerUser = await userTask;
        var verification = await verificationTask;
        var accounts = await accountsTask;
        var assets = await assetsTask;
        var budgets = await budgetsTask;
        var cards = await cardsTask;
        var transactions = await transactionsTask;

        ApplyVerification(snapshot, verification.Value);
        ApplyProviderState(snapshot, providerUser.Value);
        var providerAccountRows = NormalizeAccounts(accounts.Value);
        var budgetRows = NormalizeBudgets(budgets.Value);
        var accountRows = budgetRows.Count > 0 ? budgetRows : providerAccountRows;
        var assetBalances = NormalizeBalances(assets.Value);
        var fiatBalances = accountRows
            .Where(account => account.Balance.HasValue && !string.IsNullOrWhiteSpace(account.Currency))
            .GroupBy(account => account.Currency!, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key.ToUpperInvariant(), group => group.Sum(account => account.Balance!.Value));
        var balances = MergeCurrencyTotals(assetBalances, fiatBalances);
        var cardRows = NormalizeCards(cards.Value);

        // Never replace good cached data with empty lists when an upstream request fails.
        if (CanProjectOptional(accounts) && CanProjectOptional(budgets))
        {
            snapshot.AccountSummaryJson = JsonSerializer.Serialize(accountRows, JsonOptions);
            snapshot.AccountCount = accountRows.Count;
            if (CanProjectOptional(assets))
                snapshot.BalanceSummaryJson = JsonSerializer.Serialize(balances, JsonOptions);
        }
        if (cards.Error is null)
        {
            snapshot.CardSummaryJson = JsonSerializer.Serialize(cardRows, JsonOptions);
            snapshot.TotalCardCount = cardRows.Count;
            snapshot.ActiveCardCount = cardRows.Count(card => IsActive(card.Status));
        }

        if (transactions.Error is null)
        {
            await SyncLedgerAsync(companyInstallationId, userId, providerUserId, transactions.Value, now, cancellationToken);
            await ApplyLedgerSummaryAsync(snapshot, now, cancellationToken);
        }

        snapshot.LastActivityAt = Max(user.LastLoginAt, snapshot.LastTransactionAt, snapshot.OnboardingUpdatedAt);
        snapshot.LastSyncError = JoinErrors(
            providerUser,
            verification, accounts, assets, budgets, cards, transactions);
        snapshot.ConsecutiveSyncFailures = snapshot.LastSyncError is null
            ? 0 : Math.Min(snapshot.ConsecutiveSyncFailures + 1, 30);
        snapshot.NextSyncAt = clock.GetUtcNow() + (snapshot.ConsecutiveSyncFailures == 0
            ? settings.RefreshInterval : settings.Backoff(snapshot.ConsecutiveSyncFailures));
        if (snapshot.LastSyncError is null) snapshot.LastSyncedAt = clock.GetUtcNow();
        await dbContext.SaveChangesAsync(cancellationToken);
        return true;
    }

    private static void ApplyLocalState(
        AdminCustomerSnapshot snapshot,
        ApplicationUser user,
        OnboardingApplication? onboarding,
        KycVerification? kyc,
        KybVerification? kyb)
    {
        snapshot.CustomerType = onboarding?.Kind?.Equals("business", StringComparison.OrdinalIgnoreCase) == true
            ? "business"
            : "individual";
        snapshot.OnboardingStatus = NormalizeStatus(onboarding?.Status, "not_started");
        snapshot.OnboardingStep = NormalizeStatus(onboarding?.CurrentStep, "start");
        snapshot.OnboardingStartedAt = onboarding?.CreatedAt;
        snapshot.OnboardingCompletedAt = onboarding?.CompletedAt;
        snapshot.OnboardingUpdatedAt = onboarding?.UpdatedAt;

        if (snapshot.CustomerType == "business" && kyb is not null)
        {
            snapshot.VerificationStatus = NormalizeStatus(kyb.Status, "pending");
            snapshot.VerificationSubmittedAt = kyb.SubmittedAt;
            snapshot.VerificationReviewedAt = kyb.ReviewedAt;
            snapshot.VerificationDetailsJson = JsonSerializer.Serialize(new
            {
                type = "kyb",
                businessName = kyb.BusinessName,
                countryCode = kyb.CountryCode,
                status = snapshot.VerificationStatus,
                submittedAt = kyb.SubmittedAt,
                reviewedAt = kyb.ReviewedAt
            }, JsonOptions);
        }
        else if (kyc is not null)
        {
            snapshot.VerificationStatus = NormalizeStatus(kyc.Status, "pending");
            snapshot.VerificationLevel = kyc.Level;
            snapshot.VerificationSubmittedAt = kyc.SubmittedAt;
            snapshot.VerificationReviewedAt = kyc.ReviewedAt;
            snapshot.VerificationDetailsJson = JsonSerializer.Serialize(new
            {
                type = "kyc",
                countryCode = kyc.CountryCode,
                level = kyc.Level,
                status = snapshot.VerificationStatus,
                submittedAt = kyc.SubmittedAt,
                reviewedAt = kyc.ReviewedAt
            }, JsonOptions);
        }

        snapshot.LastActivityAt = Max(user.LastLoginAt, onboarding?.UpdatedAt);
    }

    private static void ApplyVerification(AdminCustomerSnapshot snapshot, JsonElement? document)
    {
        if (document is null)
        {
            return;
        }

        var root = document.Value;
        var status = Text(root, "status", "kycStatus", "verificationStatus", "reviewStatus");
        var level = Text(root, "level", "kycLevel", "verificationLevel");
        var submittedAt = Date(root, "submittedAt", "createdAt", "startedAt");
        var reviewedAt = Date(root, "reviewedAt", "completedAt", "updatedAt", "lastUpdated");
        var countryCode = Text(root, "countryCode", "country");

        if (!string.IsNullOrWhiteSpace(status))
        {
            snapshot.VerificationStatus = NormalizeStatus(status, snapshot.VerificationStatus);
        }

        snapshot.VerificationLevel = level ?? snapshot.VerificationLevel;
        snapshot.VerificationSubmittedAt = submittedAt ?? snapshot.VerificationSubmittedAt;
        snapshot.VerificationReviewedAt = reviewedAt ?? snapshot.VerificationReviewedAt;
        snapshot.VerificationDetailsJson = JsonSerializer.Serialize(new
        {
            type = snapshot.CustomerType == "business" ? "kyb" : "kyc",
            status = snapshot.VerificationStatus,
            level = snapshot.VerificationLevel,
            countryCode,
            submittedAt = snapshot.VerificationSubmittedAt,
            reviewedAt = snapshot.VerificationReviewedAt
        }, JsonOptions);
    }

    internal static void ApplyProviderState(AdminCustomerSnapshot snapshot, JsonElement? document)
    {
        if (document is null)
        {
            return;
        }

        var root = document.Value;
        var providerStatus = NormalizeStatus(Text(root, "status", "state"), "unknown");
        var providerKycStatus = NormalizeStatus(Text(root, "kycStatus"), snapshot.VerificationStatus);
        var providerCreatedAt = Date(root, "createdAt");
        var providerUpdatedAt = Date(root, "updatedAt");
        var providerCompletedAt = Date(root, "kycCompletedAt", "kycVerificationDate");

        if (!string.IsNullOrWhiteSpace(providerKycStatus) && providerKycStatus != "unknown")
        {
            snapshot.VerificationStatus = providerKycStatus;
        }

        snapshot.VerificationReviewedAt ??= providerCompletedAt;

        var providerIsActive = providerStatus is "active" or "approved" or "completed";
        var verificationIsApproved = snapshot.VerificationStatus is "approved" or "complete" or "completed" or "verified";
        if (!providerIsActive || !verificationIsApproved)
        {
            return;
        }

        snapshot.OnboardingStatus = "completed";
        snapshot.OnboardingStep = "account_ready";
        snapshot.OnboardingStartedAt ??= providerCreatedAt;
        snapshot.OnboardingCompletedAt ??= providerCompletedAt ?? providerUpdatedAt;
        snapshot.OnboardingUpdatedAt = Max(snapshot.OnboardingUpdatedAt, providerUpdatedAt, providerCompletedAt);
    }

    private const int TransactionPageSize = 500;
    private const int MaxTransactionPages = 40;
    // Recent rows still change (pending → closed, reversals), so each sync re-reads this window.
    private static readonly TimeSpan LedgerLookback = TimeSpan.FromDays(7);

    private Task<RemoteResult> FetchTransactionPageAsync(string providerUserId, int page, CancellationToken cancellationToken) =>
        FetchAsync(
            "/api/v2/transactions",
            cancellationToken,
            ("userId", providerUserId),
            ("page", page.ToString(CultureInfo.InvariantCulture)),
            ("pageSize", TransactionPageSize.ToString(CultureInfo.InvariantCulture)),
            ("sortBy", "date"),
            ("sortOrder", "desc"));

    /// <summary>
    /// Upserts the customer's provider ledger into admin_transactions. The first sync
    /// backfills every page; later syncs stop once a page reaches rows older than the
    /// lookback before the newest stored row.
    /// </summary>
    private async Task SyncLedgerAsync(
        Guid companyInstallationId,
        Guid userId,
        string providerUserId,
        JsonElement? firstPage,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var newestStored = await dbContext.AdminTransactions
            .Where(row => row.CompanyInstallationId == companyInstallationId && row.UserId == userId)
            .MaxAsync(row => (DateTimeOffset?)row.OccurredAt, cancellationToken);
        var stopBefore = newestStored - LedgerLookback;

        var fetched = new List<AdminTransaction>();
        var page = firstPage;
        for (var number = 1; page is not null; number++)
        {
            var items = Items(page).ToArray();
            fetched.AddRange(items
                .Where(item => IsOwnedBy(item, providerUserId))
                .Select(AdminTransactionClassifier.Classify)
                .OfType<AdminTransaction>());
            if (items.Length < TransactionPageSize || number >= MaxTransactionPages || !HasNextPage(page.Value) ||
                (stopBefore is { } stop && fetched.Count > 0 && fetched.Min(row => row.OccurredAt) < stop))
            {
                break;
            }

            var next = await FetchTransactionPageAsync(providerUserId, number + 1, cancellationToken);
            if (next.Error is not null)
            {
                // Keep what was read; the next sync continues from the stored rows.
                logger.LogWarning("Transaction page {Page} for customer {UserId} could not be read: {Error}", number + 1, userId, next.Error);
                break;
            }

            page = next.Value;
        }

        var rows = fetched
            .GroupBy(row => row.ProviderTransactionId, StringComparer.Ordinal)
            .Select(group => group.First())
            .ToList();
        if (rows.Count == 0)
        {
            return;
        }

        var ids = rows.Select(row => row.ProviderTransactionId).ToList();
        var stored = await dbContext.AdminTransactions
            .Where(row => row.CompanyInstallationId == companyInstallationId && ids.Contains(row.ProviderTransactionId))
            .ToDictionaryAsync(row => row.ProviderTransactionId, StringComparer.Ordinal, cancellationToken);
        var batch = new List<AdminTransaction>(rows.Count);
        foreach (var row in rows)
        {
            if (stored.TryGetValue(row.ProviderTransactionId, out var current))
            {
                CopyLedgerFields(row, current);
                current.UserId = userId;
                current.LastSeenAt = now;
                batch.Add(current);
                continue;
            }

            row.CompanyInstallationId = companyInstallationId;
            row.UserId = userId;
            row.LastSeenAt = now;
            dbContext.AdminTransactions.Add(row);
            batch.Add(row);
        }

        // Duplicates are judged over the batch and the stored rows booked around it.
        var from = batch.Min(row => row.OccurredAt).AddDays(-2);
        var to = batch.Max(row => row.OccurredAt).AddDays(2);
        var neighbours = await dbContext.AdminTransactions
            .Where(row =>
                row.CompanyInstallationId == companyInstallationId &&
                row.UserId == userId &&
                row.OccurredAt >= from &&
                row.OccurredAt <= to)
            .ToListAsync(cancellationToken);
        AdminTransactionClassifier.MarkDuplicates(neighbours.Concat(batch).Distinct().ToList());
        await dbContext.SaveChangesAsync(cancellationToken);
    }

    /// <summary>Per-customer 30-day totals for the support panel, from the classified ledger.</summary>
    private async Task ApplyLedgerSummaryAsync(AdminCustomerSnapshot snapshot, DateTimeOffset now, CancellationToken cancellationToken)
    {
        var ledger = dbContext.AdminTransactions.AsNoTracking().Where(row =>
            row.CompanyInstallationId == snapshot.CompanyInstallationId && row.UserId == snapshot.UserId);
        var cutoff = now.AddDays(-30);
        var recent = await ledger
            .Where(row =>
                row.OccurredAt >= cutoff &&
                row.IsPrimary &&
                !row.IsDuplicate &&
                row.Status == AdminTransactionStatuses.Completed &&
                (row.Direction == AdminTransactionDirections.In || row.Direction == AdminTransactionDirections.Out))
            .Select(row => new { row.Direction, row.Currency, row.Amount })
            .ToListAsync(cancellationToken);

        Dictionary<string, decimal> Totals(string direction) => recent
            .Where(row => row.Direction == direction)
            .GroupBy(row => row.Currency.ToUpperInvariant())
            .ToDictionary(group => group.Key, group => group.Sum(row => row.Amount));

        snapshot.CompletedTransactionCount30d = recent.Count;
        snapshot.TransactionInflow30dJson = JsonSerializer.Serialize(Totals(AdminTransactionDirections.In), JsonOptions);
        snapshot.TransactionOutflow30dJson = JsonSerializer.Serialize(Totals(AdminTransactionDirections.Out), JsonOptions);
        snapshot.LastTransactionAt = await ledger
            .Where(row => row.Kind != AdminTransactionKinds.CardEvent)
            .MaxAsync(row => (DateTimeOffset?)row.OccurredAt, cancellationToken);
        // Retired: the ledger replaced the per-customer copy of the latest 500 rows.
        snapshot.RecentTransactionsJson = "[]";
    }

    private static void CopyLedgerFields(AdminTransaction source, AdminTransaction target)
    {
        target.OccurredAt = source.OccurredAt;
        target.RawType = source.RawType;
        target.RawStatus = source.RawStatus;
        target.Status = source.Status;
        target.StatusReason = source.StatusReason;
        target.Kind = source.Kind;
        target.FeeType = source.FeeType;
        target.Direction = source.Direction;
        target.Amount = source.Amount;
        target.Currency = source.Currency;
        target.Description = source.Description;
        target.Merchant = source.Merchant;
        target.MerchantCategory = source.MerchantCategory;
        target.CardReference = source.CardReference;
        target.WalletReference = source.WalletReference;
        target.BudgetReference = source.BudgetReference;
        target.AccountReference = source.AccountReference;
        target.ExternalReference = source.ExternalReference;
        target.RelatedReference = source.RelatedReference;
        target.ClientReference = source.ClientReference;
        target.FeeAmount = source.FeeAmount;
        target.FeeCurrency = source.FeeCurrency;
        target.IsPrimary = source.IsPrimary;
    }

    /// <summary>The feed is queried by owner; a row naming another user never enters this customer's ledger.</summary>
    private static bool IsOwnedBy(JsonElement item, string providerUserId) =>
        !TryProperty(item, "userId", out var owner) ||
        owner.ValueKind is not (JsonValueKind.String or JsonValueKind.Number) ||
        string.Equals(owner.ToString().Trim(), providerUserId.Trim(), StringComparison.Ordinal);

    private static bool HasNextPage(JsonElement document)
    {
        if (!TryProperty(document, "pagination", out var pagination) || pagination.ValueKind != JsonValueKind.Object)
        {
            return true;
        }

        if (TryProperty(pagination, "hasNext", out var hasNext) && hasNext.ValueKind is JsonValueKind.True or JsonValueKind.False)
        {
            return hasNext.ValueKind == JsonValueKind.True;
        }

        return !(Amount(pagination, "page") is { } current && Amount(pagination, "totalPages") is { } total && current >= total);
    }

    /// <summary>Classified rows of one transactions page, for tests and diagnostics.</summary>
    internal static IReadOnlyList<AdminTransaction> ClassifyTransactions(JsonElement? document) =>
        Items(document).Select(AdminTransactionClassifier.Classify).OfType<AdminTransaction>().ToList();

    private async Task<RemoteResult> FetchAsync(
        string path,
        CancellationToken cancellationToken,
        params (string Key, string? Value)[] query)
    {
        try
        {
            var result = await hoppaClient.SendAsync<object?, JsonElement?>(new HoppaRequest<object?>
            {
                Method = HttpMethod.Get,
                Path = path,
                Query = query.ToDictionary(item => item.Key, item => item.Value),
                FailureCode = "admin.sync.failed",
                FailureMessage = "Customer data could not be refreshed."
            }, cancellationToken);

            return result.IsSuccess
                ? new RemoteResult(result.Value, null, null)
                : new RemoteResult(
                    null,
                    result.Error?.Message ?? "Refresh failed.",
                    result.Error?.StatusCode);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return new RemoteResult(null, "Customer refresh timed out.", 504);
        }
        catch (HttpRequestException)
        {
            return new RemoteResult(null, "Customer refresh provider is unavailable.", 502);
        }
    }

    internal static List<NormalizedAccount> NormalizeAccounts(JsonElement? document)
    {
        return Items(document)
            .Select(item => new NormalizedAccount(
                Text(item, "budgetId", "accountId", "id", "reference") ?? string.Empty,
                Text(item, "displayName", "name", "accountName", "type", "accountType") ?? "Account",
                NormalizeStatus(Text(item, "status", "state"), "unknown"),
                NormalizeCurrency(Text(item, "currency", "currencyCode") ?? FirstArrayText(item, "supportedCurrencies", "currencies")),
                Amount(item, "availableBalance", "currentBalance", "balance", "amount"),
                Text(item, "iban", "accountNumber", "maskedAccountNumber"),
                NormalizeStatus(Text(item, "accountType", "type"), "account"),
                Text(item, "budgetId", "accountId", "id", "reference"),
                Text(item, "accountId")))
            .GroupBy(account => StableKey(account.Reference, account.Currency, account.MaskedNumber, account.Balance))
            .Select(group => group.First())
            .ToList();
    }

    internal static List<NormalizedAccount> NormalizeBudgets(JsonElement? document)
    {
        var rows = new List<NormalizedAccount>();

        foreach (var budget in Items(document))
        {
            var reference = Text(budget, "budgetId", "id", "reference") ?? string.Empty;
            var name = Text(budget, "name", "displayName") ?? "Budget";
            var status = NormalizeStatus(Text(budget, "status", "state"), "unknown");
            var balanceRows = ArrayItems(budget, "balances").ToArray();

            if (balanceRows.Length > 0)
            {
                foreach (var balance in balanceRows)
                {
                    var currency = NormalizeCurrency(Text(balance, "currency", "currencyCode"));
                    rows.Add(new NormalizedAccount(
                        BudgetRowReference(reference, currency),
                        name,
                        status,
                        currency,
                        Amount(balance, "availableBalance", "currentBalance", "balance", "remaining", "ledgerBalance"),
                        null,
                        NormalizeStatus(Text(budget, "type"), "budget"),
                        reference,
                        Text(budget, "accountId", "parentId")));
                }

                continue;
            }

            var currencies = ArrayItems(budget, "currencies")
                .Select(item => NormalizeCurrency(item.ToString()))
                .Where(currency => !string.IsNullOrWhiteSpace(currency))
                .Cast<string>()
                .DefaultIfEmpty(NormalizeCurrency(Text(budget, "currency", "currencyCode")) ?? string.Empty)
                .Where(currency => !string.IsNullOrWhiteSpace(currency));

            foreach (var currency in currencies)
            {
                rows.Add(new NormalizedAccount(
                    BudgetRowReference(reference, currency),
                    name,
                    status,
                    currency,
                    Amount(budget, "availableBalance", "currentBalance", "balance", "remaining"),
                    null,
                    NormalizeStatus(Text(budget, "type"), "budget"),
                    reference,
                    Text(budget, "accountId", "parentId")));
            }
        }

        return rows
            .GroupBy(row => StableKey(row.Reference, row.Currency, row.Name, row.Balance))
            .Select(group => group.First())
            .ToList();
    }

    /// <summary>
    /// Provider asset listings include chains the product does not offer
    /// (BTC, ETH). The admin panel hides them from every balance summary.
    /// </summary>
    internal static readonly IReadOnlySet<string> HiddenBalanceCurrencies =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "BTC", "ETH" };

    public static bool IsVisibleBalanceCurrency(string? currency) =>
        !string.IsNullOrWhiteSpace(currency) && !HiddenBalanceCurrencies.Contains(currency.Trim());

    internal static Dictionary<string, decimal> NormalizeBalances(JsonElement? document)
    {
        var rows = Items(document)
            .Select(item => new
            {
                Reference = Text(item, "balanceId", "assetId", "walletId", "accountId", "reference", "id"),
                Currency = NormalizeCurrency(Text(item, "currency", "asset", "symbol", "code")),
                Amount = Amount(item, "availableBalance", "currentBalance", "balance", "total", "amount", "available")
            })
            .Where(item => IsVisibleBalanceCurrency(item.Currency) && item.Amount.HasValue)
            .GroupBy(item => StableKey(item.Reference, item.Currency, null, item.Amount))
            .Select(group => group.First());

        return rows
            .GroupBy(item => item.Currency!, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key.ToUpperInvariant(), group => group.Sum(item => item.Amount!.Value));
    }

    internal static Dictionary<string, decimal> MergeCurrencyTotals(
        params IReadOnlyDictionary<string, decimal>[] sources)
    {
        var totals = sources
            .SelectMany(source => source)
            .GroupBy(item => item.Key, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key.ToUpperInvariant(), group => group.Sum(item => item.Value));

        var funded = totals
            .Where(item => item.Value != 0m)
            .ToDictionary(item => item.Key, item => item.Value, StringComparer.OrdinalIgnoreCase);
        return funded.Count > 0 ? funded : totals;
    }

    internal static List<NormalizedCard> NormalizeCards(JsonElement? document)
    {
        return Items(document)
            .Select(item => new NormalizedCard(
                Text(item, "id", "cardId", "providerCardId") ?? string.Empty,
                LastFour(Text(item, "lastFour", "last4", "maskedPan", "cardNumber")),
                NormalizeStatus(Text(item, "status", "state"), "unknown"),
                Text(item, "cardType", "type", "formFactor") ?? "card",
                NormalizeCurrency(Text(item, "currency", "currencyCode")),
                Amount(item, "availableAmount", "available", "availableBalance"),
                Text(item, "budgetId"),
                Date(item, "issuedAt", "createdAt"),
                Date(item, "activatedAt")))
            .GroupBy(card => StableKey(card.Reference, card.LastFour, card.Type, null))
            .Select(group => group.First())
            .ToList();
    }

    private static IEnumerable<JsonElement> Items(JsonElement? document)
    {
        if (document is null)
        {
            return [];
        }

        var root = document.Value;
        if (root.ValueKind == JsonValueKind.Array)
        {
            return root.EnumerateArray().ToArray();
        }

        foreach (var key in new[] { "items", "data", "results", "accounts", "assets", "balances", "budgets", "wallets", "cards", "transactions" })
        {
            if (!TryProperty(root, key, out var value))
            {
                continue;
            }

            if (value.ValueKind == JsonValueKind.Array)
            {
                return value.EnumerateArray().ToArray();
            }

            if (value.ValueKind == JsonValueKind.Object)
            {
                var nested = Items(value).ToArray();
                if (nested.Length > 0)
                {
                    return nested;
                }
            }
        }

        return [];
    }

    private static IEnumerable<JsonElement> ArrayItems(JsonElement element, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (TryProperty(element, key, out var value) && value.ValueKind == JsonValueKind.Array)
            {
                return value.EnumerateArray().ToArray();
            }
        }

        return [];
    }

    private static string? FirstArrayText(JsonElement element, params string[] keys)
    {
        return ArrayItems(element, keys)
            .Select(item => item.ToString().Trim())
            .FirstOrDefault(item => !string.IsNullOrWhiteSpace(item));
    }

    private static string? Text(JsonElement element, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (Find(element, key, 0, out var value) && value.ValueKind is JsonValueKind.String or JsonValueKind.Number)
            {
                var text = value.ToString().Trim();
                if (!string.IsNullOrWhiteSpace(text))
                {
                    return text;
                }
            }
        }

        return null;
    }

    private static decimal? Amount(JsonElement element, params string[] keys)
    {
        var text = Text(element, keys);
        return decimal.TryParse(text, NumberStyles.Any, CultureInfo.InvariantCulture, out var value) ? value : null;
    }

    private static decimal? AmountMinor(JsonElement element)
    {
        var minor = Amount(element, "amountMinor", "balanceMinor", "valueMinor");
        return minor / 100m;
    }

    private static DateTimeOffset? Date(JsonElement element, params string[] keys)
    {
        var text = Text(element, keys);
        if (DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var value))
        {
            return value;
        }

        if (long.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var unix))
        {
            return unix > 99_999_999_999
                ? DateTimeOffset.FromUnixTimeMilliseconds(unix)
                : DateTimeOffset.FromUnixTimeSeconds(unix);
        }

        return null;
    }

    private static bool Find(JsonElement element, string key, int depth, out JsonElement value)
    {
        value = default;
        if (depth > 3 || element.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        if (TryProperty(element, key, out value) &&
            value.ValueKind is JsonValueKind.String or JsonValueKind.Number &&
            !string.IsNullOrWhiteSpace(value.ToString()))
        {
            return true;
        }

        foreach (var property in element.EnumerateObject())
        {
            if (property.Value.ValueKind == JsonValueKind.Object && Find(property.Value, key, depth + 1, out value))
            {
                return true;
            }
        }

        return false;
    }

    private static bool TryProperty(JsonElement element, string name, out JsonElement value)
    {
        value = default;
        if (element.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        foreach (var property in element.EnumerateObject())
        {
            if (property.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
            {
                value = property.Value;
                return true;
            }
        }

        return false;
    }

    private static string NormalizeStatus(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value)
            ? fallback
            : value.Trim().Replace(' ', '_').Replace('-', '_').ToLowerInvariant();

    private static string? NormalizeCurrency(string? value)
    {
        var currency = value?.Trim().ToUpperInvariant();
        return currency?.Length is >= 2 and <= 8 ? currency : null;
    }

    private static bool IsActive(string status) =>
        status.Equals("active", StringComparison.OrdinalIgnoreCase) ||
        status.Equals("activated", StringComparison.OrdinalIgnoreCase);

    private static string LastFour(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var normalized = new string(value.Where(char.IsLetterOrDigit).ToArray());
        return normalized.Length <= 4 ? normalized : normalized[^4..];
    }

    private static string BudgetRowReference(string reference, string? currency) =>
        string.IsNullOrWhiteSpace(currency) ? reference : $"{reference}:{currency.ToUpperInvariant()}";

    private static string StableKey(string? reference, string? first, string? second, decimal? amount) =>
        IsUsefulReference(reference)
            ? reference!.Trim().ToLowerInvariant()
            : $"{first}|{second}|{amount?.ToString(CultureInfo.InvariantCulture)}".ToLowerInvariant();

    private static bool IsUsefulReference(string? reference) =>
        !string.IsNullOrWhiteSpace(reference) &&
        reference.Trim() is not "0" and not "00000000-0000-0000-0000-000000000000";

    private static DateTimeOffset? Max(params DateTimeOffset?[] values) =>
        values.Where(value => value.HasValue).Select(value => value!.Value).DefaultIfEmpty().Max() is var max && max != default
            ? max
            : null;

    private static string? JoinErrors(RemoteResult required, params RemoteResult[] optional)
    {
        var results = new[] { required }
            .Concat(optional.Where(result => IsActionableOptionalFailure(result.StatusCode)));
        var errors = results
            .Select(result => result.Error)
            .Where(error => !string.IsNullOrWhiteSpace(error))
            .Distinct()
            .ToArray();
        return errors.Length == 0 ? null : string.Join(" ", errors);
    }

    // Some customers have no banking/budget capability; preserve the existing account fallback.
    private static bool CanProjectOptional(RemoteResult result) => result.Error is null || result.StatusCode is 404 or 405;

    private static bool IsActionableOptionalFailure(int? statusCode) =>
        statusCode is null or 401 or 403 or 429 or >= 500;

    private sealed record RemoteResult(JsonElement? Value, string? Error, int? StatusCode);

    internal sealed record NormalizedAccount(
        string Reference,
        string Name,
        string Status,
        string? Currency,
        decimal? Balance,
        string? MaskedNumber,
        string ResourceType,
        string? TransactionReference,
        string? AccountReference);

    internal sealed record NormalizedCard(
        string Reference,
        string LastFour,
        string Status,
        string Type,
        string? Currency,
        decimal? Balance,
        string? BudgetReference,
        DateTimeOffset? IssuedAt,
        DateTimeOffset? ActivatedAt);
}
