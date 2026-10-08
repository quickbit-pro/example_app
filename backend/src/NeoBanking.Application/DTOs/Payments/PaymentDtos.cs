using System;

namespace NeoBanking.Application.DTOs.Payments;

public sealed class CreatePaymentRequestDto
{
    public string? SourceAccountId { get; init; }

    public string? DestinationReference { get; init; }

    public decimal Amount { get; init; }

    public string? Currency { get; init; }

    public string? Reference { get; init; }
}

public sealed class PaymentResponseDto
{
    public string? PaymentId { get; init; }

    public string? Status { get; init; }

    public DateTimeOffset? CreatedAt { get; init; }
}

public sealed class CancelPaymentRequestDto
{
    public string? Reason { get; init; }
}
