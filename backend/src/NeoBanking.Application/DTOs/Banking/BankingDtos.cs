using System;

namespace NeoBanking.Application.DTOs.Banking;

public sealed class BankAccountSummaryDto
{
    public string? AccountId { get; init; }

    public string? DisplayName { get; init; }

    public string? IbanLast4 { get; init; }

    public string? Currency { get; init; }

    public decimal AvailableBalance { get; init; }
}

public sealed class LinkBankAccountRequestDto
{
    public string? Provider { get; init; }

    public string? RedirectUri { get; init; }
}

public sealed class LinkBankAccountResponseDto
{
    public string? LinkSessionId { get; init; }

    public Uri? RedirectUrl { get; init; }
}

public sealed class CreateBudgetRequestDto
{
    public string? Name { get; init; }

    public string[] Currencies { get; init; } = Array.Empty<string>();

    public decimal Amount { get; init; }

    public string? Currency { get; init; }

    public string? Period { get; init; }

    public string? Category { get; init; }
}

public sealed class UpdateBudgetRequestDto
{
    public string? Name { get; init; }

    public bool? AllowCurrencyAlignment { get; init; }

    public decimal? Amount { get; init; }

    public string? Currency { get; init; }

    public string? Period { get; init; }

    public string? Category { get; init; }

    public string? Status { get; init; }
}

public sealed class CreatePayeeRequestDto
{
    public string? Name { get; init; }

    public string? PaymentType { get; init; }

    public string? Currency { get; init; }

    public string? Country { get; init; }

    public string? DisplayName { get; init; }

    public string? AccountNumber { get; init; }

    public string? Iban { get; init; }

    public string? RoutingNumber { get; init; }

    public string? Bic { get; init; }

    public string? BankCode { get; init; }

    public string? BankName { get; init; }

    public string? CountryCode { get; init; }

    public string? FirstName { get; init; }

    public string? LastName { get; init; }

    public string? UserName { get; init; }

    public object[] RoutingCodeList { get; init; } = Array.Empty<object>();

    public object[] RoutingCodes { get; init; } = Array.Empty<object>();

    public object? BankAddress { get; init; }

    public object? PayeeAddress { get; init; }

    public string? Comments { get; init; }

    public string? PaymentMethod { get; init; }

    public string? VerificationMethod { get; init; }
}

public sealed class CreatePayeeUpstreamRequestDto
{
    public object? UserId { get; init; }

    public string? Name { get; init; }

    public string? PaymentType { get; init; }

    public string? Currency { get; init; }

    public string? Country { get; init; }

    public string? DisplayName { get; init; }

    public string? AccountNumber { get; init; }

    public string? Iban { get; init; }

    public string? RoutingNumber { get; init; }

    public string? Bic { get; init; }

    public string? BankCode { get; init; }

    public string? BankName { get; init; }

    public string? CountryCode { get; init; }

    public string? FirstName { get; init; }

    public string? LastName { get; init; }

    public string? UserName { get; init; }

    public object[] RoutingCodeList { get; init; } = Array.Empty<object>();

    public object[] RoutingCodes { get; init; } = Array.Empty<object>();

    public object? BankAddress { get; init; }

    public object? PayeeAddress { get; init; }

    public string? Comments { get; init; }

    public string? PaymentMethod { get; init; }

    public string? VerificationMethod { get; init; }

    public static CreatePayeeUpstreamRequestDto From(CreatePayeeRequestDto request, string userId)
    {
        return new CreatePayeeUpstreamRequestDto
        {
            UserId = int.TryParse(userId, out var numericUserId) ? numericUserId : userId,
            Name = request.Name ?? request.DisplayName,
            PaymentType = request.PaymentType,
            Currency = request.Currency,
            Country = request.Country ?? request.CountryCode,
            DisplayName = request.DisplayName,
            AccountNumber = request.AccountNumber,
            Iban = request.Iban,
            RoutingNumber = request.RoutingNumber,
            Bic = request.Bic,
            BankCode = request.BankCode,
            BankName = request.BankName,
            CountryCode = request.CountryCode,
            FirstName = request.FirstName,
            LastName = request.LastName,
            UserName = request.UserName,
            RoutingCodeList = request.RoutingCodeList,
            RoutingCodes = request.RoutingCodes.Length > 0 ? request.RoutingCodes : request.RoutingCodeList,
            BankAddress = request.BankAddress,
            PayeeAddress = request.PayeeAddress,
            Comments = request.Comments,
            PaymentMethod = request.PaymentMethod,
            VerificationMethod = request.VerificationMethod
        };
    }
}

public sealed class UpdatePayeeRequestDto
{
    public string? DisplayName { get; init; }

    public string? Status { get; init; }
}

public sealed class CreateTransferRequestDto
{
    public object? UserId { get; init; }

    public string? FromAccountId { get; init; }

    public string? SourceAccountId { get; init; }

    public string? DestinationId { get; init; }

    public string? DestinationAccountId { get; init; }

    public string? PayeeId { get; init; }

    public string? TransferType { get; init; }

    public decimal Amount { get; init; }

    public string? Currency { get; init; }

    public string? Reference { get; init; }

    public DateOnly? ScheduledDate { get; init; }
}

public sealed class CancelTransferRequestDto
{
    public string? Reason { get; init; }
}

public sealed class CreateBudgetUpstreamRequestDto
{
    public string? Name { get; init; }

    public string[] Currencies { get; init; } = Array.Empty<string>();

    public static CreateBudgetUpstreamRequestDto From(CreateBudgetRequestDto request)
    {
        return new CreateBudgetUpstreamRequestDto
        {
            Name = request.Name,
            Currencies = request.Currencies.Length > 0
                ? request.Currencies
                : string.IsNullOrWhiteSpace(request.Currency) ? Array.Empty<string>() : new[] { request.Currency }
        };
    }
}

public sealed class TransferBudgetRequestDto
{
    public string? DestinationBudgetId { get; init; }

    public string? ToBudgetId { get; init; }

    public decimal Amount { get; init; }

    public string? Currency { get; init; }

    public string? Reference { get; init; }
}

public sealed class TransferBudgetUpstreamRequestDto
{
    public string? DestinationBudgetId { get; init; }

    public decimal Amount { get; init; }

    public string? Currency { get; init; }

    public string? Reference { get; init; }

    public static TransferBudgetUpstreamRequestDto From(TransferBudgetRequestDto request)
    {
        return new TransferBudgetUpstreamRequestDto
        {
            DestinationBudgetId = request.DestinationBudgetId ?? request.ToBudgetId,
            Amount = request.Amount,
            Currency = request.Currency,
            Reference = request.Reference
        };
    }
}

public sealed class CreateInternalTransferRequestDto
{
    public object? UserId { get; init; }

    public string? SourceBalanceId { get; init; }

    public string? DestinationBalanceId { get; init; }

    public decimal Amount { get; init; }

    public string? Currency { get; init; }

    public string? Reference { get; init; }

    public static CreateInternalTransferRequestDto From(CreateInternalTransferRequestDto request, string userId)
    {
        return new CreateInternalTransferRequestDto
        {
            UserId = int.TryParse(userId, out var numericUserId) ? numericUserId : (object)userId,
            SourceBalanceId = request.SourceBalanceId,
            DestinationBalanceId = request.DestinationBalanceId,
            Amount = request.Amount,
            Currency = request.Currency,
            Reference = request.Reference
        };
    }
}

public sealed class CreateTransferUpstreamRequestDto
{
    public object? UserId { get; init; }

    public string? SourceAccountId { get; init; }

    public string? DestinationId { get; init; }

    public string? TransferType { get; init; }

    public string? PayeeId { get; init; }

    public decimal Amount { get; init; }

    public string? Currency { get; init; }

    public string? Reference { get; init; }

    public DateOnly? ScheduledDate { get; init; }

    public static CreateTransferUpstreamRequestDto From(CreateTransferRequestDto request, string userId)
    {
        return new CreateTransferUpstreamRequestDto
        {
            UserId = int.TryParse(userId, out var numericUserId) ? numericUserId : (object)userId,
            SourceAccountId = request.SourceAccountId ?? request.FromAccountId,
            DestinationId = request.DestinationId ?? request.PayeeId ?? request.DestinationAccountId,
            TransferType = request.TransferType ?? (string.IsNullOrWhiteSpace(request.PayeeId) ? null : "payee"),
            PayeeId = request.PayeeId,
            Amount = request.Amount,
            Currency = request.Currency,
            Reference = request.Reference,
            ScheduledDate = request.ScheduledDate
        };
    }
}

public sealed class WalletTopUpRequestDto
{
    public string? Token { get; init; }

    public string? WalletAddress { get; init; }

    public string? WalletId { get; init; }

    public decimal Value { get; init; }

    public decimal? Amount { get; init; }

    public string? Currency { get; init; }

    public long? MinorUnits { get; init; }

    public MoneyPayloadDto? Money { get; init; }
}

public sealed class WalletTopUpUpstreamRequestDto
{
    public string? Token { get; init; }

    public string? WalletAddress { get; init; }

    public string? WalletId { get; init; }

    public decimal Value { get; init; }

    public decimal? Amount { get; init; }

    public string? Currency { get; init; }

    public long? MinorUnits { get; init; }

    public MoneyPayloadDto? Money { get; init; }

    public static WalletTopUpUpstreamRequestDto From(WalletTopUpRequestDto request)
    {
        var amount = request.Amount
            ?? request.Money?.MinorUnits / 100m
            ?? request.MinorUnits / 100m;

        return new WalletTopUpUpstreamRequestDto
        {
            Token = request.Token,
            WalletAddress = request.WalletAddress ?? request.WalletId,
            WalletId = request.WalletId,
            Value = request.Value != 0 ? request.Value : amount ?? 0,
            Amount = amount,
            Currency = request.Currency ?? request.Money?.Currency,
            MinorUnits = request.MinorUnits ?? request.Money?.MinorUnits,
            Money = request.Money
        };
    }
}

public sealed class MoneyPayloadDto
{
    public string? Currency { get; init; }

    public long MinorUnits { get; init; }
}
