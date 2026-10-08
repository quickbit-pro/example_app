using NeoBanking.Application.Common;

namespace NeoBanking.Api.Cards;

/// <summary>
/// Rules for a customer-chosen card PIN, mirrored in the app
/// (mobile_flutter/lib/features/cards/domain/card_pin_policy.dart):
/// exactly six digits, not a single repeated digit, not a run of consecutive
/// digits up or down (including 890123 / 210987), and not a short block
/// repeated to fill the PIN (121212, 123123).
/// </summary>
public static class CardPinPolicy
{
    public const int Length = 6;
    public const string ErrorCode = "mobile.cards.pin.weak";
    public const string ErrorMessage =
        "Choose a 6-digit PIN that is not a single repeated digit, a run such as 123456, or a repeating pattern such as 121212.";

    public static ApplicationError? Validate(string? pin)
    {
        return IsAcceptable(pin)
            ? null
            : new ApplicationError(ErrorCode, ErrorMessage, StatusCodes.Status422UnprocessableEntity);
    }

    public static bool IsAcceptable(string? pin)
    {
        if (pin is null || pin.Length != Length || !pin.All(char.IsAsciiDigit))
        {
            return false;
        }

        return !IsSingleDigit(pin) && !IsSequential(pin) && !IsRepeatedBlock(pin);
    }

    public static bool IsSingleDigit(string pin) => pin.Distinct().Count() == 1;

    public static bool IsSequential(string pin)
    {
        var ascending = true;
        var descending = true;
        for (var i = 1; i < pin.Length; i++)
        {
            var step = ((pin[i] - pin[i - 1]) % 10 + 10) % 10;
            ascending &= step == 1;
            descending &= step == 9;
        }

        return ascending || descending;
    }

    public static bool IsRepeatedBlock(string pin)
    {
        for (var block = 1; block <= pin.Length / 2; block++)
        {
            if (pin.Length % block != 0)
            {
                continue;
            }

            var repeated = true;
            for (var i = block; i < pin.Length && repeated; i++)
            {
                repeated = pin[i] == pin[i - block];
            }

            if (repeated)
            {
                return true;
            }
        }

        return false;
    }
}
