#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Infrastructure.Persistence.Configurations;

public sealed class UserVerificationCodeConfiguration : IEntityTypeConfiguration<UserVerificationCode>
{
    public void Configure(EntityTypeBuilder<UserVerificationCode> builder)
    {
        builder.ToTable("user_verification_codes");
        builder.ConfigureCompanyScopedEntity();

        builder.Property(code => code.Purpose).IsRequired().HasMaxLength(40);
        builder.Property(code => code.CodeHash).IsRequired().HasMaxLength(64);
        builder.Property(code => code.ExpiresAt).IsRequired();

        builder
            .HasOne(code => code.CompanyInstallation)
            .WithMany()
            .HasForeignKey(code => code.CompanyInstallationId)
            .OnDelete(DeleteBehavior.Cascade);

        builder
            .HasOne(code => code.User)
            .WithMany()
            .HasForeignKey(code => code.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(code => new { code.UserId, code.Purpose, code.ConsumedAt, code.ExpiresAt });
    }
}
