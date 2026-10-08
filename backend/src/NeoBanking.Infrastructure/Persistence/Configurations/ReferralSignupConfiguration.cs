using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class ReferralSignupAttemptConfiguration : IEntityTypeConfiguration<ReferralSignupAttempt>
{
    public void Configure(EntityTypeBuilder<ReferralSignupAttempt> b)
    {
        b.ToTable("referral_signup_attempts"); b.ConfigureCompanyScopedEntity();
        b.Property(x => x.EmailNormalized).HasMaxLength(320);
        b.Property(x => x.State).HasMaxLength(40).IsConcurrencyToken(); b.Property(x => x.ProviderUserId).HasMaxLength(240);
        b.Property(x => x.ReferralCode).HasMaxLength(240); b.Property(x => x.Source).HasMaxLength(40);
        b.Property(x => x.QuoteJson).HasColumnType("jsonb"); b.Property(x => x.FailureReason).HasMaxLength(240);
        b.HasIndex(x => new { x.CompanyInstallationId, x.EmailNormalized }).IsUnique().HasFilter("\"EmailNormalized\" IS NOT NULL");
        b.HasIndex(x => new { x.CompanyInstallationId, x.LocalUserId });
        b.HasOne(x => x.CompanyInstallation).WithMany().HasForeignKey(x => x.CompanyInstallationId).OnDelete(DeleteBehavior.Restrict);
    }
}

public sealed class ReferralAttributionIntentConfiguration : IEntityTypeConfiguration<ReferralAttributionIntent>
{
    public void Configure(EntityTypeBuilder<ReferralAttributionIntent> b)
    {
        b.ToTable("referral_attribution_intents"); b.ConfigureCompanyScopedEntity();
        b.Property(x => x.Kind).HasMaxLength(40);
        b.Property(x => x.ProviderUserId).HasMaxLength(240); b.Property(x => x.State).HasMaxLength(40);
        b.Property(x => x.PayloadJson).HasColumnType("jsonb"); b.Property(x => x.ResultJson).HasColumnType("jsonb");
        b.Property(x => x.Reason).HasMaxLength(240);
        b.HasIndex(x => new {x.SignupAttemptId,x.Kind}).IsUnique();
        b.HasIndex(x => new { x.State, x.DueAt, x.LeaseUntil });
        b.HasIndex(x => new { x.CompanyInstallationId, x.UserId });
        b.HasOne<ReferralSignupAttempt>().WithMany().HasForeignKey(x => x.SignupAttemptId).OnDelete(DeleteBehavior.Restrict);
        b.HasOne<ApplicationUser>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
        b.HasOne(x => x.CompanyInstallation).WithMany().HasForeignKey(x => x.CompanyInstallationId).OnDelete(DeleteBehavior.Restrict);
    }
}
