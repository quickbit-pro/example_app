#nullable enable

using Microsoft.EntityFrameworkCore;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence;

public sealed class NeoBankingDbContext : DbContext
{
    public NeoBankingDbContext(DbContextOptions<NeoBankingDbContext> options)
        : base(options)
    {
    }

    public DbSet<MonthlyStatementExport> MonthlyStatementExports => Set<MonthlyStatementExport>();
    public DbSet<TransactionDocument> TransactionDocuments => Set<TransactionDocument>();
    public DbSet<StoredDocument> StoredDocuments => Set<StoredDocument>();

    public DbSet<ReferralSignupAttempt> ReferralSignupAttempts => Set<ReferralSignupAttempt>();
    public DbSet<ReferralAttributionIntent> ReferralAttributionIntents => Set<ReferralAttributionIntent>();

    public DbSet<CompanyInstallation> CompanyInstallations => Set<CompanyInstallation>();

    public DbSet<ApplicationUser> Users => Set<ApplicationUser>();

    public DbSet<UserIdentity> UserIdentities => Set<UserIdentity>();

    public DbSet<RefreshSession> RefreshSessions => Set<RefreshSession>();

    public DbSet<AdminProfile> AdminProfiles => Set<AdminProfile>();

    public DbSet<ProviderMapping> ProviderMappings => Set<ProviderMapping>();

    public DbSet<OnboardingApplication> OnboardingApplications => Set<OnboardingApplication>();

    public DbSet<KycVerification> KycVerifications => Set<KycVerification>();

    public DbSet<KybVerification> KybVerifications => Set<KybVerification>();

    public DbSet<BankingSnapshot> BankingSnapshots => Set<BankingSnapshot>();

    public DbSet<PaymentCard> Cards => Set<PaymentCard>();

    public DbSet<WebhookEndpoint> WebhookEndpoints => Set<WebhookEndpoint>();

    public DbSet<WebhookDelivery> WebhookDeliveries => Set<WebhookDelivery>();

    public DbSet<IdempotencyRecord> IdempotencyRecords => Set<IdempotencyRecord>();

    public DbSet<AssistantUsageReservation> AssistantUsageReservations => Set<AssistantUsageReservation>();

    public DbSet<AuditLogEntry> AuditLogEntries => Set<AuditLogEntry>();

    public DbSet<HoppaApiCallLog> HoppaApiCallLogs => Set<HoppaApiCallLog>();

    public DbSet<AdminCustomerSnapshot> AdminCustomerSnapshots => Set<AdminCustomerSnapshot>();

    public DbSet<AdminDailyFinancialSummary> AdminDailyFinancialSummaries => Set<AdminDailyFinancialSummary>();

    public DbSet<AdminTransaction> AdminTransactions => Set<AdminTransaction>();

    public DbSet<AdminCustomerFlag> AdminCustomerFlags => Set<AdminCustomerFlag>();

    public DbSet<PushDevice> PushDevices => Set<PushDevice>();

    public DbSet<PushNotification> PushNotifications => Set<PushNotification>();

    public DbSet<MarketRateSnapshot> MarketRateSnapshots => Set<MarketRateSnapshot>();

    public DbSet<EmailTemplate> EmailTemplates => Set<EmailTemplate>();

    public DbSet<EmailMessage> EmailMessages => Set<EmailMessage>();

    public DbSet<UserVerificationCode> UserVerificationCodes => Set<UserVerificationCode>();

    public DbSet<PeerTransfer> PeerTransfers => Set<PeerTransfer>();

    public DbSet<PeerPaymentRequest> PeerPaymentRequests => Set<PeerPaymentRequest>();

    public DbSet<PeerContact> PeerContacts => Set<PeerContact>();

    public DbSet<SupportTicket> SupportTickets => Set<SupportTicket>();

    public DbSet<SupportTicketMessage> SupportTicketMessages => Set<SupportTicketMessage>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("neobanking");
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(NeoBankingDbContext).Assembly);
    }

    public override int SaveChanges(bool acceptAllChangesOnSuccess)
    {
        StampAuditableEntities();
        return base.SaveChanges(acceptAllChangesOnSuccess);
    }

    public override Task<int> SaveChangesAsync(
        bool acceptAllChangesOnSuccess,
        CancellationToken cancellationToken = default)
    {
        StampAuditableEntities();
        return base.SaveChangesAsync(acceptAllChangesOnSuccess, cancellationToken);
    }

    private void StampAuditableEntities()
    {
        var now = DateTimeOffset.UtcNow;

        foreach (var entry in ChangeTracker.Entries<AuditableEntity>())
        {
            if (entry.State == EntityState.Added)
            {
                if (entry.Entity.CreatedAt == default)
                {
                    entry.Entity.CreatedAt = now;
                }

                entry.Entity.UpdatedAt = now;
            }

            if (entry.State == EntityState.Modified)
            {
                entry.Property(entity => entity.CreatedAt).IsModified = false;
                entry.Entity.UpdatedAt = now;
            }
        }
    }
}
