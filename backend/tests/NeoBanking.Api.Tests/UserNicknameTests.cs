using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using NeoBanking.Api.Controllers;
using NeoBanking.Api.Notifications;
using NeoBanking.Api.Peer;
using NeoBanking.Application.Common;
using NeoBanking.Application.DTOs.Peer;
using NeoBanking.Application.UseCases.Hoppa;
using NeoBanking.Domain.Entities;
using NeoBanking.Domain.Identity;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public class UserNicknameTests
{
    [Theory]
    [InlineData(" @AnA_123 ", "ana_123", true)]
    [InlineData("ab", "ab", false)]
    [InlineData("123456", "123456", false)]
    [InlineData("ana@example.com", "ana@example.com", false)]
    [InlineData("a b", "a b", false)]
    [InlineData("@@ana", "@ana", false)]
    [InlineData("ana\nsmith", "ana\nsmith", false)]
    [InlineData("аna", "аna", false)]
    public void NormalizeAndValidate(string input, string normalized, bool valid)
    {
        Assert.Equal(normalized, UserNickname.Normalize(input));
        Assert.Equal(valid, UserNickname.IsValid(normalized));
        Assert.True(UserNickname.IsValid(new string('a', 30)));
        Assert.False(UserNickname.IsValid(new string('a', 31)));
    }

    [Fact]
    public async Task Profile_CanonicalNicknamePersists_OmissionPreserves_BlankRemoves()
    {
        await using var db = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(db);
        var controller = Controller(db, user.Id);
        var result = MobileIdentityTestSupport.Payload(await controller.UpdateProfile(
            new() { Nickname = " @AnA_123 " }, default));
        Assert.Equal("ana_123", result.GetProperty("Nickname").GetString());
        await controller.UpdateProfile(new() { Name = "New name" }, default);
        Assert.Equal("ana_123", (await db.Users.SingleAsync()).Nickname);
        var current = MobileIdentityTestSupport.Payload(await controller.GetCurrentUser(default));
        Assert.Equal("ana_123", current.GetProperty("Nickname").GetString());
        await controller.UpdateProfile(new() { Nickname = " " }, default);
        Assert.Null((await db.Users.SingleAsync()).Nickname);
    }

    [Fact]
    public async Task Profile_RejectsDuplicateAcrossCase_ButAllowsOwnAndOtherInstallation()
    {
        await using var db = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(db);
        await Controller(db, user.Id).UpdateProfile(new() { Nickname = "ana" }, default);
        Assert.IsType<OkObjectResult>((await Controller(db, user.Id).UpdateProfile(new() { Nickname = "ANA" }, default)).Result);
        var other = await AddUser(db, user.CompanyInstallationId);
        var response = await Controller(db, other.Id).UpdateProfile(new() { Nickname = "@ANA" }, default);
        Assert.Equal(409, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Null((await db.Users.SingleAsync(x => x.Id == other.Id)).Nickname);
        var external = await AddUser(db, Guid.NewGuid());
        Assert.IsType<OkObjectResult>((await Controller(db, external.Id).UpdateProfile(new() { Nickname = "ana" }, default)).Result);
    }

    [Theory]
    [InlineData("@")]
    [InlineData("12abc")]
    [InlineData("a.b")]
    [InlineData("abc def")]
    public async Task Profile_InvalidNicknameDoesNotChangeProfile(string nickname)
    {
        await using var db = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(db);
        var response = await Controller(db, user.Id).UpdateProfile(new() { Nickname = nickname, Name = "Changed" }, default);
        Assert.Equal(400, Assert.IsType<ObjectResult>(response.Result).StatusCode);
        Assert.Equal("Customer", (await db.Users.SingleAsync()).DisplayName);
    }

    [Fact]
    public async Task Lookup_CaseInsensitiveExactMatch_PreservesPhoneEmail_EnforcesEligibility()
    {
        await using var db = MobileIdentityTestSupport.CreateDatabase();
        var owner = await MobileIdentityTestSupport.SeedUserAsync(db);
        var user = await AddUser(db, owner.CompanyInstallationId);
        user.Nickname = "ana_123";
        user.PhoneNumber = "+38640123456";
        db.ProviderMappings.Add(new() {
            CompanyInstallationId = user.CompanyInstallationId, InternalEntityType = "user",
            InternalEntityId = user.Id, Provider = "hoppa", ProviderEntityType = "user", ProviderEntityId = "123"
        });
        await db.SaveChangesAsync();
        var service = new PeerTransferService(db, new ProfileProxy(), new PasswordHasher<ApplicationUser>(),
            new PushNotificationOutbox(db), NullLogger<PeerTransferService>.Instance);
        foreach (var request in new PeerLookupRequestDto[] {
            new() { Nickname = " @ANA_123 " }, new() { Email = user.Email }, new() { PhoneNumber = user.PhoneNumber }
        })
        {
            var result = await service.LookupAsync(owner.CompanyInstallationId, owner.Id, request, default);
            Assert.True(result.IsSuccess, result.Error?.Message);
            Assert.Equal(user.Id.ToString(), result.Value!.UserId);
            Assert.Equal("ana_123", result.Value.Nickname);
        }
        Assert.Equal("peer.lookup.not_found", (await service.LookupAsync(owner.CompanyInstallationId, owner.Id, new() { Nickname = "ana" }, default)).Error!.Code);
        Assert.Equal("peer.lookup.not_found", (await service.LookupAsync(Guid.NewGuid(), owner.Id, new() { Nickname = "ana_123" }, default)).Error!.Code);
        Assert.Equal("peer.lookup.self", (await service.LookupAsync(owner.CompanyInstallationId, user.Id, new() { Nickname = "ana_123" }, default)).Error!.Code);
        Assert.Equal("peer.lookup.query_required", (await service.LookupAsync(owner.CompanyInstallationId, owner.Id, new() { Nickname = "ana_123", Email = user.Email }, default)).Error!.Code);
        user.Status = "blocked";
        await db.SaveChangesAsync();
        Assert.Equal("peer.lookup.not_found", (await service.LookupAsync(owner.CompanyInstallationId, owner.Id, new() { Nickname = "ana_123" }, default)).Error!.Code);
        user.Status = "active";
        db.ProviderMappings.RemoveRange(db.ProviderMappings);
        await db.SaveChangesAsync();
        Assert.Equal("peer.lookup.not_ready", (await service.LookupAsync(owner.CompanyInstallationId, owner.Id, new() { Nickname = "ana_123" }, default)).Error!.Code);
    }

    internal static MobileProfileController Controller(NeoBankingDbContext db, Guid id) => new(db, new ProfileProxy())
    {
        ControllerContext = MobileIdentityTestSupport.ControllerContext(id)
    };

    internal static async Task<ApplicationUser> AddUser(NeoBankingDbContext db, Guid company)
    {
        var email = $"{Guid.NewGuid():N}@example.com";
        var user = new ApplicationUser { CompanyInstallationId = company, Email = email, EmailNormalized = email.ToUpperInvariant(), Status = "active" };
        db.Users.Add(user);
        await db.SaveChangesAsync();
        return user;
    }

    private sealed class ProfileProxy : IProxyHoppaRequestUseCase
    {
        public Task<ApplicationResult<JsonElement?>> ExecuteAsync<T>(ProxyHoppaRequestCommand<T> command, CancellationToken cancellationToken) =>
            Task.FromResult(ApplicationResult<JsonElement?>.Success(JsonSerializer.SerializeToElement(new { })));
    }
}
