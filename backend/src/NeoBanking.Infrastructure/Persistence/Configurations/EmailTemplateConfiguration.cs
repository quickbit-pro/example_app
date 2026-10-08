#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class EmailTemplateConfiguration : IEntityTypeConfiguration<EmailTemplate>
{
    public void Configure(EntityTypeBuilder<EmailTemplate> builder)
    {
        builder.ToTable("email_templates");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(template => template.Key).IsRequired().HasMaxLength(80);
        builder.Property(template => template.Subject).IsRequired().HasMaxLength(200);
        builder.Property(template => template.HtmlBody).IsRequired();
        builder.Property(template => template.TextBody).IsRequired();
        builder.Property(template => template.IsEnabled).IsRequired();

        builder
            .HasOne(template => template.CompanyInstallation)
            .WithMany()
            .HasForeignKey(template => template.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(template => new { template.CompanyInstallationId, template.Key }).IsUnique();
    }
}
