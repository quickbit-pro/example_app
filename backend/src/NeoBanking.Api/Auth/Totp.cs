using System.Security.Cryptography;
using System.Text;

namespace NeoBanking.Api.Auth;

/// <summary>RFC 6238 time-based one-time passwords (SHA-1, 6 digits, 30 s), as used by authenticator apps.</summary>
public static class Totp
{
    private const string Base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    private const int Digits = 6;
    private const int StepSeconds = 30;

    public static string GenerateSecret() => Base32Encode(RandomNumberGenerator.GetBytes(20));

    public static string BuildUri(string issuer, string account, string secret)
    {
        var label = Uri.EscapeDataString($"{issuer}:{account}");
        return $"otpauth://totp/{label}?secret={secret}&issuer={Uri.EscapeDataString(issuer)}&algorithm=SHA1&digits={Digits}&period={StepSeconds}";
    }

    /// <summary>Accepts the current step and one step either side to absorb clock drift.</summary>
    public static bool Verify(string secret, string? code, DateTimeOffset? at = null)
    {
        var digits = new string((code ?? string.Empty).Where(char.IsDigit).ToArray());
        if (digits.Length != Digits)
        {
            return false;
        }
        var key = Base32Decode(secret);
        var step = (at ?? DateTimeOffset.UtcNow).ToUnixTimeSeconds() / StepSeconds;
        for (var offset = -1; offset <= 1; offset++)
        {
            if (CryptographicOperations.FixedTimeEquals(
                    Encoding.ASCII.GetBytes(Compute(key, step + offset)),
                    Encoding.ASCII.GetBytes(digits)))
            {
                return true;
            }
        }
        return false;
    }

    private static string Compute(byte[] key, long step)
    {
        var counter = new byte[8];
        for (var i = 7; i >= 0; i--)
        {
            counter[i] = (byte)(step & 0xff);
            step >>= 8;
        }
        var hash = HMACSHA1.HashData(key, counter);
        var offset = hash[^1] & 0x0f;
        var binary = ((hash[offset] & 0x7f) << 24) | ((hash[offset + 1] & 0xff) << 16) | ((hash[offset + 2] & 0xff) << 8) | (hash[offset + 3] & 0xff);
        return (binary % (int)Math.Pow(10, Digits)).ToString().PadLeft(Digits, '0');
    }

    public static string Base32Encode(byte[] data)
    {
        var output = new StringBuilder();
        int buffer = 0, bits = 0;
        foreach (var b in data)
        {
            buffer = (buffer << 8) | b;
            bits += 8;
            while (bits >= 5)
            {
                output.Append(Base32Alphabet[(buffer >> (bits - 5)) & 31]);
                bits -= 5;
            }
        }
        if (bits > 0)
        {
            output.Append(Base32Alphabet[(buffer << (5 - bits)) & 31]);
        }
        return output.ToString();
    }

    public static byte[] Base32Decode(string value)
    {
        var clean = value.Trim().Replace(" ", string.Empty).Replace("-", string.Empty).ToUpperInvariant().TrimEnd('=');
        var output = new List<byte>(clean.Length * 5 / 8);
        int buffer = 0, bits = 0;
        foreach (var c in clean)
        {
            var index = Base32Alphabet.IndexOf(c);
            if (index < 0)
            {
                throw new FormatException("Invalid base32 character.");
            }
            buffer = (buffer << 5) | index;
            bits += 5;
            if (bits >= 8)
            {
                output.Add((byte)((buffer >> (bits - 8)) & 0xff));
                bits -= 8;
            }
        }
        return output.ToArray();
    }
}

/// <summary>One-time recovery codes shown once at 2FA setup; only their hashes are kept.</summary>
public static class RecoveryCodes
{
    public const int Count = 10;

    public static IReadOnlyList<string> Generate()
    {
        var codes = new List<string>(Count);
        for (var i = 0; i < Count; i++)
        {
            var raw = Totp.Base32Encode(RandomNumberGenerator.GetBytes(10)).ToLowerInvariant();
            codes.Add($"{raw[..4]}-{raw[4..8]}-{raw[8..12]}");
        }
        return codes;
    }

    public static string Normalize(string? code) =>
        new string((code ?? string.Empty).ToLowerInvariant().Where(char.IsLetterOrDigit).ToArray());

    public static string Hash(string code) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Normalize(code))));
}
