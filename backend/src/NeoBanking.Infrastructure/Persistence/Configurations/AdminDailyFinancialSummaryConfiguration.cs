#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class AdminDailyFinancialSummaryConfiguration : IEntityTypeConfiguration<AdminDailyFinancialSummary>
{
    public void Configure(EntityTypeBuilder<AdminDailyFinancialSummary> builder)
    {
        builder.ToTable("admin_daily_financial_summaries");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(summary => summary.Day).HasColumnType("date").IsRequired();
        builder.Property(summary => summary.Currency).HasMaxLength(16).IsRequired();

        builder
            .HasOne(summary => summary.User)
            .WithMany()
            .HasForeignKey(summary => summary.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder
            .HasOne(summary => summary.CompanyInstallation)
            .WithMany()
            .HasForeignKey(summary => summary.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(summary => new
        {
            summary.CompanyInstallationId,
            summary.UserId,
            summary.Day,
            summary.Currency
        }).IsUnique();
        builder.HasIndex(summary => new { summary.CompanyInstallationId, summary.Day, summary.Currency });
    }
}
