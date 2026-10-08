using System.Text.Json;
using NeoBanking.Api.Notifications;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class HoppaUserNotificationMapperTests
{
    [Fact]
    public void InformationRequest_MapsToActionableOnboardingNotification()
    {
        var message = Map("kyc.information_request", """{"userId":42}""");

        Assert.NotNull(message);
        Assert.Equal("Information required", message.Title);
        Assert.Equal("/onboarding/banking", message.Route);
    }

    [Fact]
    public void IncomingPayment_IncludesAmountAndActivityRoute()
    {
        var message = Map(
            "payment.completed",
            """{"direction":"CREDIT","amount":125.5,"currency":"EUR","transactionId":"txn-1"}""");

        Assert.NotNull(message);
        Assert.Equal("Money received", message.Title);
        Assert.Contains("125.5 EUR", message.Body);
        Assert.Equal("/activity", message.Route);
        Assert.Equal("txn-1", message.Data["reference"]);
    }

    [Fact]
    public void CompletedOrder_MapsToExchange()
    {
        var message = Map("order.completed", """{"status":"completed","orderId":"order-1"}""");

        Assert.NotNull(message);
        Assert.Equal("Exchange completed", message.Title);
        Assert.Equal("/wallets/exchange", message.Route);
    }

    [Fact]
    public void IntermediateEvents_AreSuppressed()
    {
        Assert.Null(Map("payment.created", """{"status":"created"}"""));
        Assert.Null(Map("paymentbatch.processing", """{"status":"processing"}"""));
        Assert.Null(Map("recipient.created", """{"recipientId":"recipient-1"}"""));
    }

    [Fact]
    public void Withdrawal_NotifiesOnlyAtTerminalStatus()
    {
        Assert.Null(Map("wallet.withdrawal", """{"status":"pending"}"""));
        Assert.NotNull(Map("wallet.withdrawal", """{"status":"completed"}"""));
    }

    private static UserPushMessage? Map(string eventType, string json)
    {
        using var document = JsonDocument.Parse(json);
        return HoppaUserNotificationMapper.Map(eventType, document.RootElement);
    }
}
