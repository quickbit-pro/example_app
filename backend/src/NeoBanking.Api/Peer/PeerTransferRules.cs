#nullable enable

using System.Globalization;
using System.Text;

namespace NeoBanking.Api.Peer;

/// <summary>
/// Pure business rules for customer-to-customer transfers: which currencies
/// move, how the fee scales after the free daily quota, the anti-spam
/// pacing, and how a counterparty is shown without leaking their contact
/// details. Kept side-effect free so it can be unit tested.
/// </summary>
public static class PeerTransferRules
{
    public static readonly IReadOnlyList<string> SupportedCurrencies = ["USD", "USDC", "USDT"];

    public const int FreeTransfersPerDay = 10;

    public const decimal FeePercent = 1m;

    /// <summary>Hard ceiling on outgoing sends per day, on top of the fee.</summary>
    public const int MaxSendsPerDay = 50;

    public const int MaxRequestsPerDay = 20;

    /// <summary>Open requests one person may have towards the same payer.</summary>
    public const int MaxOpenRequestsPerPayer = 3;

    public const decimal MinAmount = 0.01m;

    public const decimal MaxAmount = 1_000_000m;

    public const int NoteMaxLength = 250;

    public static readonly TimeSpan MinimumInterval = TimeSpan.FromSeconds(15);

    public static readonly TimeSpan RequestTimeToLive = TimeSpan.FromDays(7);

    private static readonly string[] AvatarColors =
    [
        "#7B6CF6", "#27D7C2", "#F2B94B", "#FF6474", "#20D996",
        "#A78BFA", "#F7931A", "#627EEA", "#2E2A6E", "#C9B8F5",
    ];

    public static string? NormalizeCurrency(string? currency)
    {
        var code = currency?.Trim().ToUpperInvariant();
        return code is not null && SupportedCurrencies.Contains(code) ? code : null;
    }

    public static int DecimalsFor(string currency) =>
        currency is "USDC" or "USDT" ? 6 : 2;

    /// <summary>Provider payload format: two decimals for fiat, six for stablecoins.</summary>
    public static string FormatAmount(decimal amount, string currency) =>
        amount.ToString(DecimalsFor(currency) == 6 ? "F6" : "F2", CultureInfo.InvariantCulture);

    public static decimal RoundAmount(decimal amount, string currency) =>
        Math.Round(amount, DecimalsFor(currency), MidpointRounding.ToZero);

    public static decimal CalculateFee(decimal amount, int transfersUsedToday, string currency)
    {
        if (transfersUsedToday < FreeTransfersPerDay)
        {
            return 0m;
        }

        return Math.Round(amount * FeePercent / 100m, DecimalsFor(currency), MidpointRounding.AwayFromZero);
    }

    public sealed record Pricing(
        int TransfersUsedToday,
        int FreeTransfersRemaining,
        bool FeeApplies,
        decimal FeeAmount,
        bool IsRateLimited,
        int RateLimitSecondsRemaining,
        DateTimeOffset? NextAllowedAt,
        int SendsRemainingToday);

    public static Pricing Evaluate(
        DateTimeOffset now,
        int transfersUsedToday,
        DateTimeOffset? lastTransferAt,
        decimal amount,
        string currency)
    {
        var nextAllowedAt = lastTransferAt?.Add(MinimumInterval);
        var isRateLimited = nextAllowedAt.HasValue && nextAllowedAt.Value > now;
        var secondsRemaining = isRateLimited
            ? Math.Max(1, (int)Math.Ceiling((nextAllowedAt!.Value - now).TotalSeconds))
            : 0;
        var feeApplies = transfersUsedToday >= FreeTransfersPerDay;
        return new Pricing(
            transfersUsedToday,
            Math.Max(0, FreeTransfersPerDay - transfersUsedToday),
            feeApplies,
            feeApplies ? CalculateFee(amount, transfersUsedToday, currency) : 0m,
            isRateLimited,
            secondsRemaining,
            isRateLimited ? nextAllowedAt : null,
            Math.Max(0, MaxSendsPerDay - transfersUsedToday));
    }

    public static (string FirstName, string LastName) SplitName(string? displayName, string email)
    {
        var name = displayName?.Trim();
        if (string.IsNullOrEmpty(name))
        {
            var local = email.Split('@')[0];
            return (string.IsNullOrEmpty(local) ? "Member" : local, string.Empty);
        }

        var parts = name.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return parts.Length == 1
            ? (parts[0], string.Empty)
            : (parts[0], string.Join(' ', parts.Skip(1)));
    }

    public static string Initials(string firstName, string lastName)
    {
        var builder = new StringBuilder(2);
        if (!string.IsNullOrEmpty(firstName)) builder.Append(char.ToUpperInvariant(firstName[0]));
        if (!string.IsNullOrEmpty(lastName)) builder.Append(char.ToUpperInvariant(lastName[0]));
        return builder.Length == 0 ? "?" : builder.ToString();
    }

    public static string AvatarColor(Guid userId)
    {
        var bytes = userId.ToByteArray();
        var hash = 0;
        foreach (var value in bytes) hash = unchecked(hash * 31 + value);
        return AvatarColors[Math.Abs(hash % AvatarColors.Length)];
    }

    public static string? MaskEmail(string? email)
    {
        if (string.IsNullOrWhiteSpace(email)) return null;
        var at = email.IndexOf('@');
        if (at <= 0) return "***";
        var local = email[..at];
        var visible = local.Length <= 2 ? local[..1] : local[..2];
        return $"{visible}***{email[at..]}";
    }

    public static string? MaskPhone(string? phone)
    {
        var digits = NormalizePhone(phone);
        if (digits.Length == 0) return null;
        var tail = digits.Length <= 3 ? digits : digits[^3..];
        var prefix = phone!.TrimStart().StartsWith('+') ? "+" : string.Empty;
        return $"{prefix}{new string('*', Math.Max(2, digits.Length - tail.Length))}{tail}";
    }

    /// <summary>Digits only, so "+386 40 123 456" and "038640123456" compare equal.</summary>
    public static string NormalizePhone(string? phone)
    {
        if (string.IsNullOrWhiteSpace(phone)) return string.Empty;
        var digits = new string(phone.Where(char.IsDigit).ToArray());
        // Drop the international dialling prefix so 00386… equals +386….
        return digits.StartsWith("00", StringComparison.Ordinal) ? digits[2..] : digits;
    }

    public static bool PhonesMatch(string? stored, string? query)
    {
        // Local formats omit the country code and carry a trunk "0" instead:
        // compare the trailing digits with leading zeros removed.
        var a = NormalizePhone(stored).TrimStart('0');
        var b = NormalizePhone(query).TrimStart('0');
        if (a.Length < 6 || b.Length < 6) return false;
        if (a == b) return true;
        var tail = Math.Min(a.Length, b.Length);
        return tail >= 8 && a[^tail..] == b[^tail..];
    }
}
