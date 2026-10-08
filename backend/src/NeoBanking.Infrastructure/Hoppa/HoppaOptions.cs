using System;

namespace NeoBanking.Infrastructure.Hoppa;

public sealed class HoppaOptions
{
    public const string SectionName = "Hoppa";

    public Uri? BaseUrl { get; init; }

    public string? ApiKey { get; init; }

    public string? WebhookSecret { get; init; }

    public string? SumSubWebhookSecret { get; init; }

    public int TimeoutSeconds { get; init; } = 30;

    public string? PortfolioEstimatePath { get; init; }

    public ReferralAuditDelegationOptions ReferralAuditDelegation { get; init; } = new();
}

public sealed class ReferralAuditDelegationOptions
{
    public bool Enabled { get; init; }
    public string? InstallationId { get; init; }
    public int CompanyId { get; init; }
    public string? Secret { get; init; }
}
