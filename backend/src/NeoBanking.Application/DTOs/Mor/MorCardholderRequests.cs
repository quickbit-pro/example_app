using System.ComponentModel.DataAnnotations;
namespace NeoBanking.Application.DTOs.Mor;

public sealed class MorLoadRequest
{
    public MorLoadRequest() { }
    public MorLoadRequest(decimal amount, string? note) { Amount = amount; Note = note; }
    [Range(typeof(decimal), "0.01", "250000", ParseLimitsInInvariantCulture = true, ConvertValueInInvariantCulture = true)]
    public decimal Amount { get; init; }
    [StringLength(500)] public string? Note { get; init; }
}
public sealed class MorRevealRequest
{
    public MorRevealRequest() { }
    public MorRevealRequest(string currentPassword, string? code) { CurrentPassword = currentPassword; Code = code; }
    [Required, StringLength(1024)] public string CurrentPassword { get; init; } = string.Empty;
    [StringLength(16)] public string? Code { get; init; }
}
