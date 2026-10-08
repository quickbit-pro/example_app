namespace NeoBanking.Infrastructure.Admin;

public sealed class AdminCustomerSyncOptions
{
    public const string SectionName = "AdminCustomerSync";
    public int RefreshMinutes { get; set; } = 15;
    public int InitialBackoffMinutes { get; set; } = 2;
    public int MaxBackoffMinutes { get; set; } = 60;

    public TimeSpan RefreshInterval => TimeSpan.FromMinutes(Math.Clamp(RefreshMinutes, 1, 1440));
    public TimeSpan Backoff(int failures) => TimeSpan.FromMinutes(Math.Min(
        Math.Clamp(MaxBackoffMinutes, 1, 1440),
        Math.Clamp(InitialBackoffMinutes, 1, 1440) * Math.Pow(2, Math.Clamp(failures - 1, 0, 20))));
}
