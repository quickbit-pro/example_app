#nullable enable

using System.ComponentModel.DataAnnotations;

namespace NeoBanking.Application.DTOs.Peer;

public sealed class PeerLookupRequestDto
{
    [StringLength(31)]
    public string? Nickname { get; init; }

    [EmailAddress]
    [StringLength(320)]
    public string? Email { get; init; }

    [StringLength(40)]
    public string? PhoneNumber { get; init; }
}

public sealed class PeerUserDto
{
    public string? Nickname { get; init; }

    public string UserId { get; init; } = string.Empty;

    public string FirstName { get; init; } = string.Empty;

    public string LastName { get; init; } = string.Empty;

    public string Initials { get; init; } = string.Empty;

    public string AvatarColor { get; init; } = string.Empty;

    public string? MaskedEmail { get; init; }

    public string? MaskedPhone { get; init; }

    public bool IsContact { get; init; }
}

public sealed class PeerSendRequestDto
{
    [Required]
    public string RecipientUserId { get; init; } = string.Empty;

    [Required]
    [Range(0.01, 1_000_000)]
    public decimal Amount { get; init; }

    [Required]
    [StringLength(4, MinimumLength = 3)]
    public string Currency { get; init; } = "USD";

    [StringLength(250)]
    public string? Note { get; init; }

    /// <summary>
    /// "biometric" when the device prompt confirmed the action, "password"
    /// when <see cref="Password"/> carries the account password instead.
    /// </summary>
    [StringLength(32)]
    public string? ConfirmationMethod { get; init; }

    [StringLength(256)]
    public string? Password { get; init; }
}

public sealed class PeerRequestMoneyDto
{
    [Required]
    public string FromUserId { get; init; } = string.Empty;

    [Required]
    [Range(0.01, 1_000_000)]
    public decimal Amount { get; init; }

    [Required]
    [StringLength(4, MinimumLength = 3)]
    public string Currency { get; init; } = "USD";

    [StringLength(250)]
    public string? Note { get; init; }
}

public sealed class PeerRespondRequestDto
{
    /// <summary>accept or decline.</summary>
    [Required]
    [StringLength(16)]
    public string Action { get; init; } = string.Empty;

    [StringLength(32)]
    public string? ConfirmationMethod { get; init; }

    [StringLength(256)]
    public string? Password { get; init; }
}

public sealed class PeerAddContactDto
{
    [Required]
    public string UserId { get; init; } = string.Empty;

    [StringLength(80)]
    public string? Nickname { get; init; }
}

public sealed class PeerTransferDto
{
    public string Id { get; init; } = string.Empty;

    /// <summary>sent or received, from the caller's point of view.</summary>
    public string Type { get; init; } = string.Empty;

    public PeerUserDto OtherUser { get; init; } = new();

    public decimal Amount { get; init; }

    public string Currency { get; init; } = string.Empty;

    public string? Note { get; init; }

    public string Status { get; init; } = string.Empty;

    public decimal Fee { get; init; }

    public DateTimeOffset CreatedAt { get; init; }

    public DateTimeOffset? CompletedAt { get; init; }

    public string? PaymentRequestId { get; init; }

    public string? ErrorMessage { get; init; }
}

public sealed class PeerPaymentRequestDto
{
    public string Id { get; init; } = string.Empty;

    /// <summary>sent (I asked) or received (someone asked me).</summary>
    public string Type { get; init; } = string.Empty;

    public PeerUserDto OtherUser { get; init; } = new();

    public decimal Amount { get; init; }

    public string Currency { get; init; } = string.Empty;

    public string? Note { get; init; }

    public string Status { get; init; } = string.Empty;

    public DateTimeOffset CreatedAt { get; init; }

    public DateTimeOffset ExpiresAt { get; init; }

    public DateTimeOffset? RespondedAt { get; init; }

    public string? TransferId { get; init; }
}

public sealed class PeerRequestsDto
{
    public IReadOnlyList<PeerPaymentRequestDto> Received { get; init; } = [];

    public IReadOnlyList<PeerPaymentRequestDto> Sent { get; init; } = [];

    public IReadOnlyList<PeerPaymentRequestDto> History { get; init; } = [];
}

public sealed class PeerContactDto
{
    public string Id { get; init; } = string.Empty;

    public PeerUserDto User { get; init; } = new();

    public string? Nickname { get; init; }

    public DateTimeOffset AddedAt { get; init; }
}

public sealed class PeerFeeInfoDto
{
    public int FreeTransfersPerDay { get; init; }

    public int TransfersUsedToday { get; init; }

    public int FreeTransfersRemaining { get; init; }

    public decimal FeePercent { get; init; }

    public decimal FeeAmount { get; init; }

    public string FeeCurrency { get; init; } = "USD";

    public bool FeeApplies { get; init; }

    public bool IsRateLimited { get; init; }

    public int RateLimitSecondsRemaining { get; init; }

    public DateTimeOffset? NextTransferAllowedAt { get; init; }

    public int DailySendLimit { get; init; }

    public int SendsRemainingToday { get; init; }

    public decimal MinAmount { get; init; }

    public decimal MaxAmount { get; init; }

    public IReadOnlyList<string> Currencies { get; init; } = [];
}

public sealed class PeerRespondResultDto
{
    public PeerPaymentRequestDto Request { get; init; } = new();

    public PeerTransferDto? Transfer { get; init; }
}
