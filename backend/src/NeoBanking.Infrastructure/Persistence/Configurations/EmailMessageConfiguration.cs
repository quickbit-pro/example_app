#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class EmailMessageConfiguration : IEntityTypeConfiguration<EmailMessage>
{
    public void Configure(EntityTypeBuilder<EmailMessage> builder)
    {
        builder.ToTable("email_messages");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(message => message.TemplateKey).IsRequired().HasMaxLength(80);
        builder.Property(message => message.ToEmail).IsRequired().HasMaxLength(320);
        builder.Property(message => message.ToName).HasMaxLength(160);
        builder.Property(message => message.Subject).IsRequired().HasMaxLength(400);
        builder.Property(message => message.HtmlBody).IsRequired();
        builder.Property(message => message.TextBody).IsRequired();
        builder.Property(message => message.Status).IsRequired().HasMaxLength(24);
        builder.Property(message => message.ProviderMessageId).HasMaxLength(200);
        builder.Property(message => message.ErrorMessage).HasMaxLength(1000);
        builder.Property(message => message.MetadataJson).IsRequired().HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");

        builder
            .HasOne(message => message.CompanyInstallation)
            .WithMany()
            .HasForeignKey(message => message.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Cascade);

        builder
            .HasOne(message => message.User)
            .WithMany()
            .HasForeignKey(message => message.UserId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasIndex(message => new { message.Status, message.NextAttemptAt });
        builder.HasIndex(message => new { message.CompanyInstallationId, message.CreatedAt });
    }
}
