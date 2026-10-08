using System.Text.Json;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Admin;
using Xunit;

namespace NeoBanking.Tests;

public sealed class AdminCustomerProjectionTests
{
    [Fact]
    public void AssetBalancesUseStableBalanceIdInsteadOfZeroAssetId()
    {
        var document = Parse("""
            {
              "assets": [
                { "id": 0, "balanceId": "card-1", "currency": "USD", "availableBalance": "19.70" },
                { "id": 0, "balanceId": "account-1", "currency": "USD", "availableBalance": "7.38" },
                { "id": 0, "balanceId": "wallet-1", "currency": "BTC", "availableBalance": "0" }
              ]
            }
            """);

        var balances = AdminCustomerSyncService.NormalizeBalances(document);

        Assert.Equal(27.08m, balances["USD"]);
        Assert.False(balances.ContainsKey("BTC"));
    }

    [Fact]
    public void UnofferedChainsAreHiddenFromBalancesEvenWhenFunded()
    {
        var document = Parse("""
            {
              "assets": [
                { "balanceId": "a", "currency": "USDT", "availableBalance": "12" },
                { "balanceId": "b", "currency": "eth", "availableBalance": "0.5" },
                { "balanceId": "c", "asset": "BTC", "availableBalance": "0.01" }
              ]
            }
            """);

        var balances = AdminCustomerSyncService.NormalizeBalances(document);

        Assert.Equal(["USDT"], balances.Keys);
        Assert.True(AdminCustomerSyncService.IsVisibleBalanceCurrency("GBP"));
        Assert.False(AdminCustomerSyncService.IsVisibleBalanceCurrency("btc"));
    }

    [Fact]
    public void BudgetBackedAccountsUseBudgetIdAsStableReference()
    {
        var document = Parse("""
            {
              "accounts": [
                { "accountId": "shared", "budgetId": "budget-1", "displayName": "Main", "status": "active", "supportedCurrencies": ["GBP"] },
                { "accountId": "shared", "budgetId": "budget-2", "displayName": "Travel", "status": "active", "supportedCurrencies": ["EUR"] }
              ]
            }
            """);

        var accounts = AdminCustomerSyncService.NormalizeAccounts(document);

        Assert.Equal(2, accounts.Count);
        Assert.Contains(accounts, account => account.Reference == "budget-1" && account.Name == "Main" && account.Currency == "GBP" && account.TransactionReference == "budget-1");
        Assert.Contains(accounts, account => account.Reference == "budget-2" && account.Name == "Travel" && account.Currency == "EUR" && account.AccountReference == "shared");
    }

    [Fact]
    public void BudgetsExpandNestedCurrencyBalancesAndRemainDistinct()
    {
        var document = Parse("""
            {
              "budgets": [
                {
                  "budgetId": "main",
                  "name": "Account balance",
                  "status": "active",
                  "balances": [{ "currency": "GBP", "availableBalance": 380 }]
                },
                {
                  "budgetId": "travel",
                  "name": "Travel",
                  "status": "active",
                  "balances": [
                    { "currency": "GBP", "availableBalance": 20 },
                    { "currency": "EUR", "availableBalance": 15 }
                  ]
                }
              ]
            }
            """);

        var rows = AdminCustomerSyncService.NormalizeBudgets(document);
        var balances = rows
            .GroupBy(row => row.Currency!)
            .ToDictionary(group => group.Key, group => group.Sum(row => row.Balance));

        Assert.Equal(3, rows.Count);
        Assert.Equal(400m, balances["GBP"]);
        Assert.Equal(15m, balances["EUR"]);
    }

    [Fact]
    public void FundedCurrenciesHideUnhelpfulZeroBalanceAssets()
    {
        var balances = AdminCustomerSyncService.MergeCurrencyTotals(
            new Dictionary<string, decimal> { ["USD"] = 27.08m, ["BTC"] = 0m },
            new Dictionary<string, decimal> { ["GBP"] = 380m, ["EUR"] = 0m });

        Assert.Equal(2, balances.Count);
        Assert.Equal(27.08m, balances["USD"]);
        Assert.Equal(380m, balances["GBP"]);
    }

    [Fact]
    public void ActiveApprovedProviderMarksOnboardingComplete()
    {
        var snapshot = new AdminCustomerSnapshot
        {
            OnboardingStatus = "not_started",
            OnboardingStep = "start",
            VerificationStatus = "pending"
        };
        var document = Parse("""
            {
              "status": "ACTIVE",
              "kycStatus": "APPROVED",
              "createdAt": "2026-04-01T10:00:00Z",
              "updatedAt": "2026-04-22T15:18:19Z",
              "kycCompletedAt": "2026-04-22T15:00:00Z"
            }
            """);

        AdminCustomerSyncService.ApplyProviderState(snapshot, document);

        Assert.Equal("approved", snapshot.VerificationStatus);
        Assert.Equal("completed", snapshot.OnboardingStatus);
        Assert.Equal("account_ready", snapshot.OnboardingStep);
        Assert.NotNull(snapshot.OnboardingCompletedAt);
    }

    [Fact]
    public void ProviderTransactionDateAndCardLastFourAreProjected()
    {
        var transactions = Parse("""
            { "data": [{ "id": "tx-1", "cardId": 173, "budgetId": null, "status": "closed", "amount": 5, "currency": "GBP", "type": "deposit", "transactionDate": "2026-08-27T14:16:37Z", "metadata": { "budgetId": "budget-1", "accountId": "account-1" } }] }
            """);
        var cards = Parse("""
            { "cards": [{ "id": "card-1", "status": "ACTIVE", "currency": "USD", "cardType": "VIRTUAL", "cardNumber": "4111111111111234", "balance": { "available": "19.70" } }] }
            """);

        var transaction = Assert.Single(AdminCustomerSyncService.ClassifyTransactions(transactions));
        var card = Assert.Single(AdminCustomerSyncService.NormalizeCards(cards));

        Assert.Equal(new DateTimeOffset(2026, 8, 27, 14, 16, 37, TimeSpan.Zero), transaction.OccurredAt);
        Assert.Equal("173", transaction.CardReference);
        Assert.Equal(AdminTransactionKinds.Deposit, transaction.Kind);
        Assert.Equal(AdminTransactionStatuses.Completed, transaction.Status);
        Assert.Equal("budget-1", transaction.BudgetReference);
        Assert.Equal("account-1", transaction.AccountReference);
        Assert.Equal("1234", card.LastFour);
        Assert.Equal(19.70m, card.Balance);
    }

    private static JsonElement Parse(string json) => JsonDocument.Parse(json).RootElement.Clone();
}
