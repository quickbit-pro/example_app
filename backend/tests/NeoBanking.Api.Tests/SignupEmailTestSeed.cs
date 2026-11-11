using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using NeoBanking.Domain.Entities;
using NeoBanking.Infrastructure.Persistence;

namespace NeoBanking.Api.Tests;

internal static class SignupEmailTestSeed
{
    public const string Code = "123456";
    public const string Purpose = "signup_email_verification";
    public static async Task<ApplicationUser> Prepare(NeoBankingDbContext db, string email)
    {
        var company = await db.CompanyInstallations.SingleAsync(x => x.Slug == "default");
        var user = await db.Users.SingleOrDefaultAsync(x => x.CompanyInstallationId == company.Id && x.EmailNormalized == email.ToUpperInvariant());
        if (user is null)
        {
            user = new ApplicationUser { CompanyInstallationId = company.Id, Email = email, EmailNormalized = email.ToUpperInvariant(), Status = "pending_signup" };
            db.Users.Add(user);
        }
        foreach (var old in await db.UserVerificationCodes.Where(x => x.UserId == user.Id && x.Purpose == Purpose && x.ConsumedAt == null).ToListAsync())
            old.ConsumedAt = DateTimeOffset.UtcNow;
        db.UserVerificationCodes.Add(new UserVerificationCode
        {
            CompanyInstallationId = company.Id, UserId = user.Id, Purpose = Purpose,
            CodeHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes($"{user.Id:N}:{Purpose}:{Code}"))),
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(10)
        });
        await db.SaveChangesAsync();
        return user;
    }
}
