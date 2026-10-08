using System.Text.Json;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Admin;
using Xunit;

namespace NeoBanking.Tests;

/// <summary>
/// Row shapes follow the production captures in the mobile tests
/// (group_card_fees_test.dart "Hoppa production shapes") and the descriptions
/// the admin Money page showed for live Example data in September 2026.
/// </summary>
public sealed class AdminTransactionClassifierTests
{
    [Fact]
    public void CardPaymentsAreSpendingNotInflow_AndKeepTheMerchant()
    {
        var settled = Classify("""
            {"id":"77001","type":"card_payment","description":"Type1: OPENAI                 SAN FRANCISCOCAUS",
             "amount":20.4,"currency":"USD","status":"closed","transactionDate":"2026-09-20T10:00:00","cardId":"541",
             "metadata":{"clientTransactionId":"2094","type":1}}
            """);
        Assert.Equal(AdminTransactionKinds.CardPurchase, settled.Kind);
        Assert.Equal(AdminTransactionDirections.Out, settled.Direction);
        Assert.Equal(AdminTransactionStatuses.Completed, settled.Status);
        Assert.Equal(20.4m, settled.Amount);
        Assert.Equal("OPENAI", settled.Merchant);
        Assert.Equal("541", settled.CardReference);

        var declined = Classify("""
            {"id":"76748","externalTransactionId":"ext-76748","type":"card_payment","description":"Type1: MESARIJA SELAK",
             "amount":66.87,"currency":"USD","status":"fail","transactionDate":"2026-09-01T09:44:43","cardId":"541",
             "feeAmount":1.51,"metadata":{"clientTransactionId":"2094723116296110081","type":1,"cardTransactionId":"ext-76748"}}
            """);
        Assert.Equal(AdminTransactionKinds.CardPurchase, declined.Kind);
        Assert.Equal(AdminTransactionStatuses.Failed, declined.Status);
        Assert.Equal("MESARIJA SELAK", declined.Merchant);
        Assert.Equal("2094723116296110081", declined.ClientReference);
        Assert.Equal(1.51m, declined.FeeAmount);
        Assert.Null(declined.StatusReason);

        var withReason = Classify("""{"id":"r","type":"card_payment","amount":5,"status":"declined","metadata":{"declineReason":"Insufficient funds"}}""");
        Assert.Equal("Insufficient funds", withReason.StatusReason);
    }

    [Fact]
    public void ZeroAmountAuthorisationsAreCardChecks()
    {
        var check = Classify("""
            {"id":"1","type":"card_payment","description":"Type1: APPLE PAY              St. Louis      US",
             "amount":0,"currency":"USD","status":"closed","transactionDate":"2026-09-20T10:00:00","cardId":"9"}
            """);
        Assert.Equal(AdminTransactionKinds.CardCheck, check.Kind);
        Assert.Equal(AdminTransactionDirections.None, check.Direction);
        Assert.Equal("APPLE PAY", check.Merchant);
    }

    [Theory]
    [InlineData("""{"id":"76750","type":"card_decline_fee","description":"Card decline fee for transaction","amount":-0.5,"currency":"USD","status":"completed","relatedCardTransactionId":"ext-76748","feeAmount":0.5}""", "decline", 0.5)]
    [InlineData("""{"id":"76749","type":"card_payment_fee","amount":0.5,"currency":"USD","status":"closed","metadata":{"clientTransactionId":"2094723116296110081_Fee_Consumption"}}""", "card_payment", 0.5)]
    [InlineData("""{"id":"53421","type":"card_payment_fee","description":"Type10: ","amount":0,"currency":"USD","status":"closed","feeAmount":0.5,"metadata":{"clientTransactionId":"d2edd680","type":10}}""", "decline", 0.5)]
    [InlineData("""{"id":"f1","type":"card_payment_fee","description":"Fee_Consumption: OPENAI                 SAN FRANCISCOCAUS - Fee_Consum","amount":0.2,"currency":"USD","status":"closed"}""", "card_payment", 0.2)]
    [InlineData("""{"id":"f2","type":"fees","description":"fees: card_topup_fee","amount":-0.18,"currency":"USD","status":"completed"}""", "top_up", 0.18)]
    [InlineData("""{"id":"f3","type":"fees","description":"fees: card_issuance_fee","amount":-9.99,"currency":"USD","status":"completed"}""", "card_issuance", 9.99)]
    [InlineData("""{"id":"f4","type":"7","description":"Monthly card fee for card ending 6295 (2026-09-24 to 2026-10-23)","amount":1.5,"currency":"USD","status":"success"}""", "monthly", 1.5)]
    public void FeesAreRevenueRows_WithTheirType(string json, string feeType, decimal amount)
    {
        var fee = Classify(json);
        Assert.Equal(AdminTransactionKinds.Fee, fee.Kind);
        Assert.Equal(AdminTransactionDirections.Out, fee.Direction);
        Assert.Equal(AdminTransactionStatuses.Completed, fee.Status);
        Assert.Equal(feeType, fee.FeeType);
        Assert.Equal(amount, fee.Amount);
    }

    [Fact]
    public void FeeReversalsReturnMoney()
    {
        var reversal = Classify("""{"id":"r1","type":"fees","description":"Fee reversal: card_issuance_fee","amount":9.99,"currency":"USD","status":"completed"}""");
        Assert.Equal(AdminTransactionKinds.FeeRefund, reversal.Kind);
        Assert.Equal(AdminTransactionDirections.In, reversal.Direction);
        Assert.Equal("card_issuance", reversal.FeeType);
    }

    [Theory]
    [InlineData("card_topup", "Card top-up", AdminTransactionKinds.CardFunding, AdminTransactionDirections.Internal)]
    [InlineData("wallet_debit", "Infinity account wallet_debit: 12 USD", AdminTransactionKinds.CardFunding, AdminTransactionDirections.Internal)]
    [InlineData("card_unload", "Card unload", AdminTransactionKinds.CardFunding, AdminTransactionDirections.Internal)]
    [InlineData("crypto_to_quantum_transfer", "crypto_to_quantum_transfer: Transfer 7.5 USDT to USD", AdminTransactionKinds.Conversion, AdminTransactionDirections.Internal)]
    [InlineData("quantum_to_crypto_exchange", "Exchange 10 USD to USDT", AdminTransactionKinds.Conversion, AdminTransactionDirections.Internal)]
    [InlineData("crypto_deposit", "Crypto deposit of 62.5 USDT from TRX", AdminTransactionKinds.Deposit, AdminTransactionDirections.In)]
    [InlineData("crypto_withdrawal", "Mobile crypto withdrawal", AdminTransactionKinds.Withdrawal, AdminTransactionDirections.Out)]
    [InlineData("transfer_to_master", "Sent to Hubert Wistak", AdminTransactionKinds.Transfer, AdminTransactionDirections.Out)]
    [InlineData("user_to_master_transfer", "Sent to Hubert Wistak", AdminTransactionKinds.Transfer, AdminTransactionDirections.Out)]
    [InlineData("transfer_from_master", "From Roman Smienov", AdminTransactionKinds.Transfer, AdminTransactionDirections.In)]
    [InlineData("master_to_user_transfer", "Refund of failed transfer to Willam", AdminTransactionKinds.Transfer, AdminTransactionDirections.In)]
    [InlineData("transfer_in", "EUR conversion credit", AdminTransactionKinds.Transfer, AdminTransactionDirections.In)]
    public void MovementsKeepTheirMeaningAndDirection(string type, string description, string kind, string direction)
    {
        var row = Classify($$"""{"id":"m1","type":"{{type}}","description":"{{description}}","amount":7.5,"currency":"USDT","status":"complete"}""");
        Assert.Equal(kind, row.Kind);
        Assert.Equal(direction, row.Direction);
        Assert.Equal(AdminTransactionStatuses.Completed, row.Status);
        Assert.Equal("USDT", row.Currency);
    }

    [Theory]
    [InlineData("4", AdminTransactionKinds.CardRefund, AdminTransactionDirections.In)]
    [InlineData("2", AdminTransactionKinds.CardFunding, AdminTransactionDirections.Internal)]
    [InlineData("13", AdminTransactionKinds.CardCash, AdminTransactionDirections.Out)]
    [InlineData("11", AdminTransactionKinds.CardEvent, AdminTransactionDirections.None)]
    [InlineData("5", AdminTransactionKinds.CardPurchase, AdminTransactionDirections.Out)]
    public void NumericInterlaceTypesFollowTheMobileCatalogue(string type, string kind, string direction)
    {
        var row = Classify($$"""{"id":"n1","type":"{{type}}","description":"Type{{type}}: SHOP","amount":10,"currency":"USD","status":"closed","cardId":"1"}""");
        Assert.Equal(kind, row.Kind);
        Assert.Equal(direction, row.Direction);
    }

    [Fact]
    public void ExplicitDirectionAndSignDecideTransfers()
    {
        Assert.Equal(AdminTransactionDirections.Out,
            Classify("""{"id":"t1","type":"transfer","amount":42,"currency":"EUR","direction":"DBIT","status":"completed"}""").Direction);
        Assert.Equal(AdminTransactionDirections.In,
            Classify("""{"id":"t2","type":"transfer","amount":42,"currency":"EUR","metadata":{"direction":"credit"},"status":"completed"}""").Direction);
        Assert.Equal(AdminTransactionDirections.Out,
            Classify("""{"id":"t3","type":"internal_payment","amount":-7.85,"currency":"USD","status":"completed"}""").Direction);
    }

    [Theory]
    [InlineData("closed", AdminTransactionStatuses.Completed)]
    [InlineData("Complete", AdminTransactionStatuses.Completed)]
    [InlineData("success", AdminTransactionStatuses.Completed)]
    [InlineData("fail", AdminTransactionStatuses.Failed)]
    [InlineData("declined", AdminTransactionStatuses.Failed)]
    [InlineData("pending", AdminTransactionStatuses.Pending)]
    [InlineData("authorized", AdminTransactionStatuses.Pending)]
    [InlineData("mystery", AdminTransactionStatuses.Other)]
    public void StatusSpellingsCollapseIntoBuckets(string raw, string bucket) =>
        Assert.Equal(bucket, AdminTransactionClassifier.StatusOf(raw));

    [Fact]
    public void RowsWithoutIdAreSkipped_AndRelatedLegsAreFlagged()
    {
        using var missing = JsonDocument.Parse("""{"type":"card_payment","amount":1}""");
        Assert.Null(AdminTransactionClassifier.Classify(missing.RootElement));
        Assert.False(Classify("""{"id":"x","type":"exchange","amount":1,"isPrimary":false}""").IsPrimary);
        Assert.True(Classify("""{"id":"y","type":"exchange","amount":1}""").IsPrimary);
    }

    [Fact]
    public void RequestPaymentsAndMonthlyFeesSeenTwiceCountOnce()
    {
        var payment = Classify("""{"id":"6747","type":"internal_payment","description":"internal_payment: Payment internal payment","amount":-7.85,"currency":"USD","status":"completed","metadata":{"clientTransactionId":"35"}}""");
        var request = Classify("""{"id":"6746","type":"fees","description":"fees: Direct payment for request 35","amount":-7.85,"currency":"USD","status":"completed","metadata":{"clientTransactionId":"6746"}}""");
        var cardFee = Classify("""{"id":"9001","type":"7","description":"Monthly card fee for card ending 6295 (2026-09-24 to 2026-10-23)","amount":1.5,"currency":"USD","status":"success"}""");
        var ledgerFee = Classify("""{"id":"9002","type":"fees","description":"fees: Monthly card fee for card ending 6295 (2026-09-24 to 2026-10-23)","amount":-1.5,"currency":"USD","status":"completed"}""");
        var otherCard = Classify("""{"id":"9003","type":"fees","description":"fees: Monthly card fee for card ending 1111 (2026-09-24 to 2026-10-23)","amount":-1.5,"currency":"USD","status":"completed"}""");
        var unrelatedRequest = Classify("""{"id":"6748","type":"fees","description":"fees: Direct payment for request 99","amount":-2,"currency":"USD","status":"completed"}""");

        AdminTransactionClassifier.MarkDuplicates([payment, request, cardFee, ledgerFee, otherCard, unrelatedRequest]);

        Assert.Equal(AdminTransactionKinds.Transfer, request.Kind);
        Assert.True(request.IsDuplicate);
        Assert.False(payment.IsDuplicate);
        Assert.True(ledgerFee.IsDuplicate);
        Assert.False(cardFee.IsDuplicate);
        Assert.False(otherCard.IsDuplicate);
        Assert.False(unrelatedRequest.IsDuplicate);
    }

    private static AdminTransaction Classify(string json)
    {
        using var document = JsonDocument.Parse(json);
        return AdminTransactionClassifier.Classify(document.RootElement)!;
    }
}
