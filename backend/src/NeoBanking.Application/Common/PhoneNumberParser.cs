using PhoneNumbers;

namespace NeoBanking.Application.Common;

/// <summary>
/// Splits a phone number into the country dial code and the national number,
/// the shape the card issuer expects (<c>PhoneCode</c> + <c>Phone</c>), using
/// libphonenumber's metadata so every country parses and only numbers that
/// are valid for their region are accepted.
/// </summary>
public static class PhoneNumberParser
{
    private static readonly PhoneNumberUtil Util = PhoneNumberUtil.GetInstance();

    /// <summary>
    /// Returns the dial code and national number for a number written with an
    /// international prefix ("+49…" or "0049…"). A bare national number
    /// cannot be attributed to a country, so it is tried with the
    /// <paramref name="fallbackDialCode"/> when one is given. Returns
    /// <c>null</c> when the value is empty, unparseable, or not a valid number
    /// for its country.
    /// </summary>
    public static (string PhoneCode, string Phone)? Split(string? value, string? fallbackDialCode = null)
    {
        var normalized = value?.Trim();
        if (string.IsNullOrWhiteSpace(normalized))
        {
            return null;
        }

        if (normalized.StartsWith("00", StringComparison.Ordinal))
        {
            normalized = $"+{normalized[2..]}";
        }

        if (!normalized.StartsWith('+'))
        {
            if (string.IsNullOrWhiteSpace(fallbackDialCode))
            {
                return null;
            }

            var digits = string.Concat(normalized.Where(char.IsDigit));
            var code = string.Concat(fallbackDialCode.Where(char.IsDigit));
            if (digits.Length == 0 || code.Length == 0)
            {
                return null;
            }

            normalized = $"+{code}{digits}";
        }

        try
        {
            var number = Util.Parse(normalized, null);
            if (!Util.IsValidNumber(number))
            {
                return null;
            }

            return (
                number.CountryCode.ToString(System.Globalization.CultureInfo.InvariantCulture),
                Util.GetNationalSignificantNumber(number));
        }
        catch (NumberParseException)
        {
            return null;
        }
    }
}
