using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Application.Security;
using NeoBanking.Api.Admin;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Admin;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Controllers;

[Authorize(Policy = AuthorizationPolicyNames.Admin)]
[Route("api/v1/admin")]
public sealed class AdminOperationsController(
    NeoBankingDbContext dbContext,
    IAdminCustomerSyncService syncService,
    AdminKpiService kpiService) : ApiControllerBase
{
    private static readonly HashSet<string> PendingStatuses = new(StringComparer.OrdinalIgnoreCase)
    {
        "pending", "submitted", "reviewing", "manual_review", "in_review"
    };

    [HttpGet("overview")]
    public async Task<IActionResult> GetOverview([FromQuery] int? range, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return MissingCompany();
        }

        var rangeDays = range is 7 or 30 or 90 ? range.Value : 30;
        return Ok(await kpiService.GetOverviewAsync(companyId, rangeDays, cancellationToken));
    }

    [HttpGet("customers")]
    public async Task<IActionResult> GetCustomers(
        [FromQuery] string? q,
        [FromQuery] string? type,
        [FromQuery] string? onboarding,
        [FromQuery] string? verification,
        [FromQuery] bool? attention,
        [FromQuery] string? testAccounts,
        [FromQuery] string? stage,
        [FromQuery] DateTimeOffset? since,
        [FromQuery] int? offset,
        [FromQuery] int? limit,
        CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return MissingCompany();
        }

        var testUsers = await TestAccountIds(companyId, cancellationToken);
        var query = CustomerSnapshots(companyId);
        if (testAccounts == "exclude")
        {
            query = query.Where(snapshot => !testUsers.Contains(snapshot.UserId));
        }
        else if (testAccounts == "only")
        {
            query = query.Where(snapshot => testUsers.Contains(snapshot.UserId));
        }
        var search = q?.Trim();
        if (!string.IsNullOrWhiteSpace(search))
        {
            var normalized = search.ToLower();
            query = query.Where(snapshot =>
                (snapshot.User!.DisplayName != null && snapshot.User.DisplayName.ToLower().Contains(normalized)) ||
                snapshot.User.Email.ToLower().Contains(normalized) ||
                (snapshot.User.PhoneNumber != null && snapshot.User.PhoneNumber.Contains(search)));
        }

        if (!string.IsNullOrWhiteSpace(type))
        {
            query = query.Where(snapshot => snapshot.CustomerType == type);
        }

        if (!string.IsNullOrWhiteSpace(onboarding))
        {
            query = query.Where(snapshot => snapshot.OnboardingStatus == onboarding);
        }

        if (!string.IsNullOrWhiteSpace(verification))
        {
            query = query.Where(snapshot => snapshot.VerificationStatus == verification);
        }

        if (since is { } signedUpSince)
        {
            query = query.Where(snapshot => snapshot.User!.CreatedAt >= signedUpSince);
        }

        var snapshots = await query
            .OrderByDescending(snapshot => snapshot.LastActivityAt ?? snapshot.User!.CreatedAt)
            .ToListAsync(cancellationToken);
        var now = DateTimeOffset.UtcNow;
        var facts = await AdminCustomerStages.LoadFactsAsync(dbContext, companyId, cancellationToken);
        var rows = snapshots.Select(snapshot => ToCustomerRow(snapshot, now, testUsers.Contains(snapshot.UserId),
            AdminCustomerStages.Of(snapshot, facts.GetValueOrDefault(snapshot.UserId), now)));
        if (attention == true)
        {
            rows = rows.Where(row => row.attentionReason is not null);
        }

        var materialized = rows.ToList();
        // Chip counts follow every other filter, so each chip says what selecting it would show.
        var stageCounts = AdminCustomerStages.Ordered
            .Select(value => new { stage = value, count = materialized.Count(row => row.stage == value) })
            .ToList();
        if (!string.IsNullOrWhiteSpace(stage))
        {
            materialized = materialized.Where(row => row.stage == stage).ToList();
        }

        var pageSize = Math.Clamp(limit ?? 25, 1, 100);
        var skip = Math.Max(0, offset ?? 0);

        return Ok(new
        {
            totalCount = materialized.Count,
            attentionCount = materialized.Count(row => row.attentionReason is not null),
            stageCounts,
            items = materialized.Skip(skip).Take(pageSize)
        });
    }

    [HttpGet("customers/{userId:guid}")]
    public async Task<IActionResult> GetCustomer(Guid userId, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return MissingCompany();
        }

        var snapshot = await CustomerSnapshots(companyId)
            .SingleOrDefaultAsync(candidate => candidate.UserId == userId, cancellationToken);
        if (snapshot is null)
        {
            return NotFound(new { message = "Customer was not found." });
        }

        var testUsers = await TestAccountIds(companyId, cancellationToken);
        var facts = await AdminCustomerStages.LoadFactsAsync(dbContext, companyId, cancellationToken);
        var now = DateTimeOffset.UtcNow;
        var row = ToCustomerRow(snapshot, now, testUsers.Contains(snapshot.UserId),
            AdminCustomerStages.Of(snapshot, facts.GetValueOrDefault(snapshot.UserId), now));
        var recentTransactions = await LedgerRows(dbContext.AdminTransactions
                .AsNoTracking()
                .Where(transaction => transaction.CompanyInstallationId == companyId && transaction.UserId == userId)
                .OrderByDescending(transaction => transaction.OccurredAt)
                .Take(50))
            .ToListAsync(cancellationToken);
        return Ok(new
        {
            customer = row,
            onboarding = new
            {
                status = snapshot.OnboardingStatus,
                currentStep = snapshot.OnboardingStep,
                startedAt = snapshot.OnboardingStartedAt,
                updatedAt = snapshot.OnboardingUpdatedAt,
                completedAt = snapshot.OnboardingCompletedAt
            },
            verification = ParseJson(snapshot.VerificationDetailsJson, new { }),
            balances = CurrencyRows(snapshot.BalanceSummaryJson),
            accounts = ParseJson(snapshot.AccountSummaryJson, Array.Empty<object>()),
            cards = ParseJson(snapshot.CardSummaryJson, Array.Empty<object>()),
            recentTransactions,
            support = new
            {
                attentionReason = row.attentionReason,
                lastSyncedAt = snapshot.LastSyncedAt,
                dataState = HasActionableSyncError(snapshot.LastSyncError) ? "needs_retry" : "current",
                dataMessage = FriendlySyncMessage(snapshot.LastSyncError)
            },
            referenceDetails = new
            {
                localCustomerId = snapshot.UserId,
                providerCustomerId = snapshot.ProviderUserId
            }
        });
    }

    [HttpPost("customers/{userId:guid}/refresh")]
    public async Task<IActionResult> RefreshCustomer(Guid userId, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return MissingCompany();
        }

        var refreshed = await syncService.SyncCustomerAsync(companyId, userId, cancellationToken);
        return refreshed
            ? Accepted(new { message = "Customer data has been refreshed.", refreshedAt = DateTimeOffset.UtcNow })
            : NotFound(new { message = "Customer was not found." });
    }

    /// <summary>
    /// Re-syncs card holders so the portfolio shows current balances. One customer when <paramref name="customerId"/>
    /// is given; otherwise the card holders whose snapshot is oldest, in batches, so the caller can loop until
    /// <c>remaining</c> is zero without hitting the proxy timeout.
    /// </summary>
    /// <summary>Marks an internal or test account; KPIs leave these customers out.</summary>
    [HttpPut("customers/{userId:guid}/test-account")]
    public async Task<IActionResult> SetTestAccount(Guid userId, [FromBody] TestAccountRequest request, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return MissingCompany();
        }

        if (!await CustomerSnapshots(companyId).AnyAsync(snapshot => snapshot.UserId == userId, cancellationToken))
        {
            return NotFound(new { message = "Customer was not found." });
        }

        Guid? actorId = TryGetLocalUserId(out var actor) && Guid.TryParse(actor, out var parsedActor) ? parsedActor : null;
        var flag = await dbContext.AdminCustomerFlags
            .SingleOrDefaultAsync(candidate => candidate.CompanyInstallationId == companyId && candidate.UserId == userId, cancellationToken);
        var before = flag?.IsTestAccount ?? false;
        if (flag is null)
        {
            flag = new AdminCustomerFlag { CompanyInstallationId = companyId, UserId = userId };
            dbContext.AdminCustomerFlags.Add(flag);
        }

        flag.IsTestAccount = request.IsTestAccount;
        flag.UpdatedByUserId = actorId;
        if (before != request.IsTestAccount)
        {
            dbContext.AuditLogEntries.Add(new AuditLogEntry
            {
                CompanyInstallationId = companyId,
                ActorUserId = actorId,
                Action = request.IsTestAccount ? "customer.marked_test_account" : "customer.unmarked_test_account",
                EntityType = "user",
                EntityId = userId,
                TraceId = HttpContext.TraceIdentifier,
                IpAddress = GetClientIpAddress(),
                UserAgent = Request.Headers.UserAgent.ToString(),
                BeforeJson = JsonSerializer.Serialize(new { isTestAccount = before }),
                AfterJson = JsonSerializer.Serialize(new { isTestAccount = request.IsTestAccount }),
                MetadataJson = "{\"source\":\"wl_admin\"}"
            });
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        return Ok(new { customerId = userId, isTestAccount = flag.IsTestAccount });
    }

    [HttpPost("card-portfolio/refresh")]
    public async Task<IActionResult> RefreshCards([FromQuery] Guid? customerId, [FromQuery] int? limit, CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return MissingCompany();
        }

        var startedAt = DateTimeOffset.UtcNow;
        if (customerId is { } single)
        {
            var refreshedOne = await syncService.SyncCustomerAsync(companyId, single, cancellationToken);
            return refreshedOne
                ? Ok(new { refreshed = 1, failed = 0, remaining = 0, refreshedAt = DateTimeOffset.UtcNow })
                : NotFound(new { message = "Customer was not found." });
        }

        var batch = Math.Clamp(limit ?? 40, 1, 200);
        var holders = await CustomerSnapshots(companyId)
            .Where(snapshot => snapshot.TotalCardCount > 0)
            .OrderBy(snapshot => snapshot.LastSyncedAt ?? DateTimeOffset.MinValue)
            .Select(snapshot => new { snapshot.UserId, snapshot.LastSyncedAt })
            .ToListAsync(cancellationToken);
        var due = holders.Where(holder => holder.LastSyncedAt == null || holder.LastSyncedAt < startedAt).ToList();
        var refreshed = 0;
        var failed = 0;
        foreach (var holder in due.Take(batch))
        {
            try
            {
                if (await syncService.SyncCustomerAsync(companyId, holder.UserId, cancellationToken)) refreshed++;
                else failed++;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception)
            {
                failed++;
            }
        }

        return Ok(new
        {
            refreshed,
            failed,
            remaining = Math.Max(0, due.Count - batch),
            total = holders.Count,
            refreshedAt = DateTimeOffset.UtcNow
        });
    }

    [HttpGet("verifications")]
    public async Task<IActionResult> GetVerifications(
        [FromQuery] string? type,
        [FromQuery] string? status,
        CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return MissingCompany();
        }

        var query = CustomerSnapshots(companyId);
        if (!string.IsNullOrWhiteSpace(type))
        {
            query = query.Where(snapshot => snapshot.CustomerType == type);
        }

        if (!string.IsNullOrWhiteSpace(status))
        {
            query = query.Where(snapshot => snapshot.VerificationStatus == status);
        }

        var now = DateTimeOffset.UtcNow;
        var items = await query
            .OrderBy(snapshot => snapshot.VerificationSubmittedAt ?? snapshot.OnboardingStartedAt)
            .Select(snapshot => new
            {
                customerId = snapshot.UserId,
                customerName = snapshot.User!.DisplayName ?? snapshot.User.Email,
                email = snapshot.User.Email,
                customerType = snapshot.CustomerType,
                verificationType = snapshot.CustomerType == "business" ? "KYB" : "KYC",
                status = snapshot.VerificationStatus,
                level = snapshot.VerificationLevel,
                submittedAt = snapshot.VerificationSubmittedAt,
                reviewedAt = snapshot.VerificationReviewedAt
            })
            .ToListAsync(cancellationToken);

        return Ok(new
        {
            totalCount = items.Count,
            pendingCount = items.Count(item => PendingStatuses.Contains(item.status)),
            over24Hours = items.Count(item =>
                PendingStatuses.Contains(item.status) && item.submittedAt < now.AddHours(-24)),
            items
        });
    }

    [HttpGet("money")]
    public async Task<IActionResult> GetMoney(
        [FromQuery] int? range,
        [FromQuery] string? q,
        [FromQuery] Guid? customerId,
        [FromQuery] string? status,
        [FromQuery] string? direction,
        [FromQuery] string? currency,
        [FromQuery] string? kind,
        [FromQuery] string? cardId,
        [FromQuery] string? budgetId,
        [FromQuery] string? sortBy,
        [FromQuery] string? sortDirection,
        [FromQuery] int? offset,
        [FromQuery] int? limit,
        CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return MissingCompany();
        }

        var rangeDays = range is 0 or 7 or 30 or 90 ? range.Value : 30;
        var since = rangeDays == 0 ? DateTimeOffset.MinValue : DateTimeOffset.UtcNow.AddDays(-rangeDays);
        var snapshots = await CustomerSnapshots(companyId).ToListAsync(cancellationToken);
        var scopedSnapshots = customerId.HasValue
            ? snapshots.Where(snapshot => snapshot.UserId == customerId.Value).ToList()
            : snapshots;

        var scoped = dbContext.AdminTransactions
            .AsNoTracking()
            .Where(row => row.CompanyInstallationId == companyId && row.OccurredAt >= since);
        if (customerId.HasValue)
        {
            scoped = scoped.Where(row => row.UserId == customerId.Value);
        }

        if (!string.IsNullOrWhiteSpace(cardId))
        {
            scoped = scoped.Where(row => row.CardReference == cardId);
        }

        if (!string.IsNullOrWhiteSpace(budgetId))
        {
            // An account-balance budget holds the account's own movements as well.
            var accountReferences = scopedSnapshots
                .SelectMany(ReadAccounts)
                .Where(account =>
                    string.Equals(account.TransactionReference, budgetId, StringComparison.OrdinalIgnoreCase) &&
                    account.ResourceType is not null &&
                    account.ResourceType.Replace("_", string.Empty).Equals("accountbalance", StringComparison.OrdinalIgnoreCase) &&
                    !string.IsNullOrWhiteSpace(account.AccountReference))
                .Select(account => account.AccountReference!)
                .Distinct()
                .ToList();
            scoped = scoped.Where(row =>
                row.BudgetReference == budgetId ||
                (row.AccountReference != null && accountReferences.Contains(row.AccountReference)));
        }

        var filterOptions = new
        {
            statuses = await scoped.Select(row => row.Status).Distinct().OrderBy(value => value).ToListAsync(cancellationToken),
            currencies = await scoped.Select(row => row.Currency).Distinct().OrderBy(value => value).ToListAsync(cancellationToken),
            kinds = await scoped.Select(row => row.Kind).Distinct().OrderBy(value => value).ToListAsync(cancellationToken)
        };

        var filtered = scoped;
        var search = q?.Trim().ToLower();
        if (!string.IsNullOrWhiteSpace(search))
        {
            filtered = filtered.Where(row =>
                row.Description.ToLower().Contains(search) ||
                (row.Merchant != null && row.Merchant.ToLower().Contains(search)) ||
                (row.User!.DisplayName != null && row.User.DisplayName.ToLower().Contains(search)) ||
                row.User!.Email.ToLower().Contains(search));
        }

        if (!string.IsNullOrWhiteSpace(status))
        {
            filtered = filtered.Where(row => row.Status == status);
        }

        if (!string.IsNullOrWhiteSpace(direction))
        {
            filtered = filtered.Where(row => row.Direction == direction);
        }

        if (!string.IsNullOrWhiteSpace(currency))
        {
            filtered = filtered.Where(row => row.Currency == currency.ToUpper());
        }

        if (!string.IsNullOrWhiteSpace(kind))
        {
            filtered = filtered.Where(row => row.Kind == kind);
        }

        // Summaries count each movement once: related legs and duplicate views are listed, never summed.
        var reportable = filtered.Where(row =>
            row.IsPrimary && !row.IsDuplicate && row.Status == AdminTransactionStatuses.Completed);
        var activity = await reportable
            .GroupBy(row => row.Currency)
            .Select(group => new
            {
                currency = group.Key,
                transactionCount = group.Count(),
                inflow = group.Sum(row => row.Direction == AdminTransactionDirections.In ? row.Amount : 0m),
                outflow = group.Sum(row => row.Direction == AdminTransactionDirections.Out ? row.Amount : 0m),
                @internal = group.Sum(row => row.Direction == AdminTransactionDirections.Internal ? row.Amount : 0m)
            })
            .OrderBy(row => row.currency)
            .ToListAsync(cancellationToken);
        var kinds = await reportable
            .GroupBy(row => new { row.Kind, row.Currency })
            .Select(group => new { group.Key.Kind, group.Key.Currency, Count = group.Count(), Amount = group.Sum(row => row.Amount) })
            .ToListAsync(cancellationToken);

        var totalCount = await filtered.CountAsync(cancellationToken);
        var pageSize = Math.Clamp(limit ?? 25, 1, 100);
        var skip = Math.Max(0, offset ?? 0);
        var rows = await LedgerRows(SortTransactions(filtered, sortBy, sortDirection).Skip(skip).Take(pageSize))
            .ToListAsync(cancellationToken);
        var names = snapshots.ToDictionary(snapshot => snapshot.UserId, snapshot => snapshot.User!.DisplayName ?? snapshot.User.Email);

        return Ok(new
        {
            rangeDays,
            totalCount,
            offset = skip,
            limit = pageSize,
            customers = CustomerOptions(snapshots),
            filterOptions,
            balances = AdminKpiService.SumCurrencies(scopedSnapshots.Select(snapshot => snapshot.BalanceSummaryJson))
                .Select(pair => new { currency = pair.Key, amount = pair.Value }),
            activity,
            kinds = kinds
                .GroupBy(row => row.Kind)
                .Select(group => new
                {
                    kind = group.Key,
                    count = group.Sum(row => row.Count),
                    amounts = group.OrderBy(row => row.Currency).Select(row => new { currency = row.Currency, amount = row.Amount })
                })
                .OrderByDescending(row => row.count),
            recentTransactions = rows.Select(row => new
            {
                customerId = row.UserId,
                customerName = names.GetValueOrDefault(row.UserId, "Customer"),
                row.reference,
                row.description,
                row.merchant,
                row.kind,
                row.feeType,
                row.status,
                row.rawStatus,
                row.direction,
                row.amount,
                row.currency,
                row.occurredAt,
                row.cardReference,
                row.budgetReference,
                row.accountReference,
                row.isPrimary,
                row.isDuplicate
            })
        });
    }

    [HttpGet("card-portfolio")]
    public async Task<IActionResult> GetCards(
        [FromQuery] string? q,
        [FromQuery] Guid? customerId,
        [FromQuery] string? status,
        [FromQuery] string? currency,
        [FromQuery] string? sortBy,
        [FromQuery] string? sortDirection,
        [FromQuery] int? offset,
        [FromQuery] int? limit,
        CancellationToken cancellationToken)
    {
        if (!TryGetCompanyInstallationId(out var companyId))
        {
            return MissingCompany();
        }

        var snapshots = await CustomerSnapshots(companyId).ToListAsync(cancellationToken);
        var cards = snapshots
            .Where(snapshot => !customerId.HasValue || snapshot.UserId == customerId.Value)
            .SelectMany(snapshot => ReadCards(snapshot).Select(card => new PortfolioCardRow(
                snapshot.UserId,
                snapshot.User!.DisplayName ?? snapshot.User.Email,
                card.Reference,
                card.LastFour,
                card.Status,
                card.Type,
                card.Currency,
                card.Balance,
                card.BudgetReference,
                card.IssuedAt,
                card.ActivatedAt)))
            .ToList();

        var availableCardStatuses = cards.Select(card => card.Status)
            .Distinct(StringComparer.OrdinalIgnoreCase).Order().ToArray();
        var availableCardCurrencies = cards.Where(card => !string.IsNullOrWhiteSpace(card.Currency))
            .Select(card => card.Currency!).Distinct(StringComparer.OrdinalIgnoreCase).Order().ToArray();

        var search = q?.Trim();
        if (!string.IsNullOrWhiteSpace(search))
        {
            cards = cards.Where(card =>
                    card.CustomerName.Contains(search, StringComparison.OrdinalIgnoreCase) ||
                    card.LastFour.Contains(search, StringComparison.OrdinalIgnoreCase) ||
                    card.Type.Contains(search, StringComparison.OrdinalIgnoreCase))
                .ToList();
        }

        if (!string.IsNullOrWhiteSpace(status))
        {
            cards = cards.Where(card => string.Equals(card.Status, status, StringComparison.OrdinalIgnoreCase)).ToList();
        }

        if (!string.IsNullOrWhiteSpace(currency))
        {
            cards = cards.Where(card => string.Equals(card.Currency, currency, StringComparison.OrdinalIgnoreCase)).ToList();
        }

        var totalCount = cards.Count;
        var activeCount = cards.Count(card => card.Status is "active" or "activated");
        var pageSize = Math.Clamp(limit ?? 25, 1, 100);
        var skip = Math.Max(0, offset ?? 0);
        var items = SortCards(cards, sortBy, sortDirection).Skip(skip).Take(pageSize).ToList();

        return Ok(new
        {
            totalCount,
            activeCount,
            offset = skip,
            limit = pageSize,
            customers = CustomerOptions(snapshots),
            filterOptions = new
            {
                statuses = availableCardStatuses,
                currencies = availableCardCurrencies
            },
            items
        });
    }

    private IQueryable<AdminCustomerSnapshot> CustomerSnapshots(Guid companyId) =>
        dbContext.AdminCustomerSnapshots
            .AsNoTracking()
            .Include(snapshot => snapshot.User)
            .Where(snapshot =>
                snapshot.CompanyInstallationId == companyId &&
                snapshot.User != null &&
                snapshot.User.AdminProfile == null);

    private async Task<HashSet<Guid>> TestAccountIds(Guid companyId, CancellationToken cancellationToken) =>
        (await dbContext.AdminCustomerFlags
            .AsNoTracking()
            .Where(flag => flag.CompanyInstallationId == companyId && flag.IsTestAccount)
            .Select(flag => flag.UserId)
            .ToListAsync(cancellationToken))
        .ToHashSet();

    private static IQueryable<LedgerTransactionRow> LedgerRows(IQueryable<AdminTransaction> rows) =>
        rows.Select(row => new LedgerTransactionRow(
            row.UserId,
            row.ProviderTransactionId,
            row.Description,
            row.Merchant,
            row.Kind,
            row.FeeType,
            row.Status,
            row.RawStatus,
            row.Direction,
            row.Amount,
            row.Currency,
            row.OccurredAt,
            row.CardReference,
            row.BudgetReference,
            row.AccountReference,
            row.IsPrimary,
            row.IsDuplicate));

    private static CustomerRow ToCustomerRow(AdminCustomerSnapshot snapshot, DateTimeOffset now, bool isTestAccount, string stage)
    {
        var attention = ToAttention(snapshot, now);
        return new CustomerRow(
            snapshot.UserId,
            snapshot.User!.DisplayName ?? snapshot.User.Email,
            snapshot.User.Email,
            snapshot.User.PhoneNumber,
            snapshot.CustomerType,
            snapshot.User.Status,
            snapshot.OnboardingStatus,
            snapshot.OnboardingStep,
            snapshot.VerificationStatus,
            CurrencyRows(snapshot.BalanceSummaryJson),
            snapshot.ActiveCardCount,
            snapshot.TotalCardCount,
            snapshot.LastActivityAt,
            attention?.reason,
            attention?.tone,
            snapshot.LastSyncedAt,
            isTestAccount,
            stage);
    }

    private static AttentionRow? ToAttention(AdminCustomerSnapshot snapshot, DateTimeOffset now)
    {
        var evaluation = AdminAttentionPolicy.Evaluate(snapshot, now);
        return evaluation is null
            ? null
            : new AttentionRow(
                snapshot.UserId,
                snapshot.User!.DisplayName ?? snapshot.User.Email,
                snapshot.CustomerType,
                evaluation.Reason,
                evaluation.Tone,
                evaluation.Priority,
                evaluation.AgeHours);
    }

    // Snapshots synced before a currency was hidden still carry it; filter on
    // read as well so the panel never shows it.
    private static IReadOnlyList<CurrencyRow> CurrencyRows(string json) =>
        ReadCurrencyJson(json)
            .Where(pair => AdminCustomerSyncService.IsVisibleBalanceCurrency(pair.Key))
            .Select(pair => new CurrencyRow(pair.Key, pair.Value))
            .ToArray();

    private static Dictionary<string, decimal> ReadCurrencyJson(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<Dictionary<string, decimal>>(json) ?? [];
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private static IEnumerable<AccountProjectionRow> ReadAccounts(AdminCustomerSnapshot snapshot)
    {
        try
        {
            return JsonSerializer.Deserialize<AccountProjectionRow[]>(snapshot.AccountSummaryJson,
                new JsonSerializerOptions(JsonSerializerDefaults.Web)) ?? [];
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private static IEnumerable<CardRow> ReadCards(AdminCustomerSnapshot snapshot)
    {
        try
        {
            return JsonSerializer.Deserialize<CardRow[]>(snapshot.CardSummaryJson,
                new JsonSerializerOptions(JsonSerializerDefaults.Web)) ?? [];
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private static IReadOnlyList<CustomerOptionRow> CustomerOptions(IEnumerable<AdminCustomerSnapshot> snapshots) =>
        snapshots
            .Select(snapshot => new CustomerOptionRow(
                snapshot.UserId,
                snapshot.User!.DisplayName ?? snapshot.User.Email))
            .OrderBy(customer => customer.Name)
            .ToArray();

    private static IQueryable<AdminTransaction> SortTransactions(
        IQueryable<AdminTransaction> rows,
        string? sortBy,
        string? sortDirection)
    {
        var descending = !string.Equals(sortDirection, "asc", StringComparison.OrdinalIgnoreCase);
        return (sortBy?.Trim().ToLowerInvariant(), descending) switch
        {
            ("customer", false) => rows.OrderBy(row => row.User!.DisplayName ?? row.User.Email).ThenByDescending(row => row.OccurredAt),
            ("customer", true) => rows.OrderByDescending(row => row.User!.DisplayName ?? row.User.Email).ThenByDescending(row => row.OccurredAt),
            ("description", false) => rows.OrderBy(row => row.Description).ThenByDescending(row => row.OccurredAt),
            ("description", true) => rows.OrderByDescending(row => row.Description).ThenByDescending(row => row.OccurredAt),
            ("kind", false) => rows.OrderBy(row => row.Kind).ThenByDescending(row => row.OccurredAt),
            ("kind", true) => rows.OrderByDescending(row => row.Kind).ThenByDescending(row => row.OccurredAt),
            ("status", false) => rows.OrderBy(row => row.Status).ThenByDescending(row => row.OccurredAt),
            ("status", true) => rows.OrderByDescending(row => row.Status).ThenByDescending(row => row.OccurredAt),
            ("currency", false) => rows.OrderBy(row => row.Currency).ThenByDescending(row => row.OccurredAt),
            ("currency", true) => rows.OrderByDescending(row => row.Currency).ThenByDescending(row => row.OccurredAt),
            ("amount", false) => rows.OrderBy(row => row.Amount).ThenByDescending(row => row.OccurredAt),
            ("amount", true) => rows.OrderByDescending(row => row.Amount).ThenByDescending(row => row.OccurredAt),
            ("direction", false) => rows.OrderBy(row => row.Direction).ThenByDescending(row => row.OccurredAt),
            ("direction", true) => rows.OrderByDescending(row => row.Direction).ThenByDescending(row => row.OccurredAt),
            (_, false) => rows.OrderBy(row => row.OccurredAt).ThenBy(row => row.ProviderTransactionId),
            _ => rows.OrderByDescending(row => row.OccurredAt).ThenByDescending(row => row.ProviderTransactionId)
        };
    }

    private static IEnumerable<PortfolioCardRow> SortCards(
        IEnumerable<PortfolioCardRow> cards,
        string? sortBy,
        string? sortDirection)
    {
        var descending = !string.Equals(sortDirection, "asc", StringComparison.OrdinalIgnoreCase);
        return (sortBy?.Trim().ToLowerInvariant(), descending) switch
        {
            ("customer", false) => cards.OrderBy(card => card.CustomerName),
            ("customer", true) => cards.OrderByDescending(card => card.CustomerName),
            ("type", false) => cards.OrderBy(card => card.Type),
            ("type", true) => cards.OrderByDescending(card => card.Type),
            ("status", false) => cards.OrderBy(card => card.Status),
            ("status", true) => cards.OrderByDescending(card => card.Status),
            ("currency", false) => cards.OrderBy(card => card.Currency),
            ("currency", true) => cards.OrderByDescending(card => card.Currency),
            ("balance", false) => cards.OrderBy(card => card.Balance),
            ("balance", true) => cards.OrderByDescending(card => card.Balance),
            (_, false) => cards.OrderBy(card => card.IssuedAt),
            _ => cards.OrderByDescending(card => card.IssuedAt)
        };
    }

    private static object ParseJson(string json, object fallback)
    {
        try
        {
            return JsonSerializer.Deserialize<JsonElement>(json);
        }
        catch (JsonException)
        {
            return fallback;
        }
    }

    private static string? FriendlySyncMessage(string? error) =>
        string.IsNullOrWhiteSpace(error)
            ? null
            : error.Contains("not yet connected", StringComparison.OrdinalIgnoreCase)
                ? "The customer has not finished connecting their banking account."
                : "Some customer information could not be refreshed. Try again shortly.";

    private static bool HasActionableSyncError(string? error) => AdminKpiService.HasActionableSyncError(error);

    private ObjectResult MissingCompany() => Problem(
        statusCode: StatusCodes.Status401Unauthorized,
        title: "Company context is missing",
        detail: "Sign in again to continue.");

    private sealed record CustomerRow(
        Guid customerId,
        string name,
        string email,
        string? phone,
        string customerType,
        string accountStatus,
        string onboardingStatus,
        string onboardingStep,
        string verificationStatus,
        IReadOnlyList<CurrencyRow> balances,
        int activeCards,
        int totalCards,
        DateTimeOffset? lastActivityAt,
        string? attentionReason,
        string? attentionTone,
        DateTimeOffset? lastSyncedAt,
        bool isTestAccount,
        string stage);

    private sealed record CurrencyRow(string currency, decimal amount);

    private sealed record AttentionRow(
        Guid customerId,
        string customerName,
        string customerType,
        string reason,
        string tone,
        int priority,
        long ageHours);

    private sealed record CardRow(
        string Reference,
        string LastFour,
        string Status,
        string Type,
        string? Currency,
        decimal? Balance,
        string? BudgetReference,
        DateTimeOffset? IssuedAt,
        DateTimeOffset? ActivatedAt);

    private sealed record AccountProjectionRow(
        string Reference,
        string Name,
        string Status,
        string? Currency,
        decimal? Balance,
        string? MaskedNumber,
        string? ResourceType,
        string? TransactionReference,
        string? AccountReference);

    private sealed record CustomerOptionRow(Guid Id, string Name);

    private sealed record LedgerTransactionRow(
        Guid UserId,
        string reference,
        string description,
        string? merchant,
        string kind,
        string? feeType,
        string status,
        string rawStatus,
        string direction,
        decimal amount,
        string currency,
        DateTimeOffset occurredAt,
        string? cardReference,
        string? budgetReference,
        string? accountReference,
        bool isPrimary,
        bool isDuplicate);

    private sealed record PortfolioCardRow(
        Guid CustomerId,
        string CustomerName,
        string Reference,
        string LastFour,
        string Status,
        string Type,
        string? Currency,
        decimal? Balance,
        string? BudgetReference,
        DateTimeOffset? IssuedAt,
        DateTimeOffset? ActivatedAt);

    public sealed record TestAccountRequest(bool IsTestAccount);
}
