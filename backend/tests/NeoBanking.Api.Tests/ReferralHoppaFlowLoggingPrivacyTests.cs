using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using NeoBanking.Api.HoppaLogging;
using NeoBanking.Application.Company;
using NeoBanking.Application.Interfaces;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class ReferralHoppaFlowLoggingPrivacyTests
{
    [Theory]
    [InlineData("/api/v1/mobile/auth/signup")]
    [InlineData("/API/V1/MOBILE/AUTH/REFERRAL-QUOTE/")]
    public async Task ReferralSignupSuppressesMalformedRawInputAndAddressWhileKeepingStatus(string path)
    {
        await using var db = Database();
        const string body = "{invalid-json-with-private-installation-token";
        var context = Context(path, "application/json", new MemoryStream(Encoding.UTF8.GetBytes(body)));
        context.Request.ContentLength = Encoding.UTF8.GetByteCount(body);
        context.Request.QueryString = new("?invitationToken=private-query-token&status=pending");
        context.Request.Headers["X-Forwarded-For"] = "198.51.100.28";
        var collector = Collector();
        var middleware = new HoppaFlowLoggingMiddleware(async ctx =>
        {
            using var reader = new StreamReader(ctx.Request.Body, leaveOpen: true);
            Assert.Equal(body, await reader.ReadToEndAsync());
            ctx.Response.StatusCode = 400;
            await ctx.Response.WriteAsync("{\"status\":\"invalid-request\"}");
        }, NullLogger<HoppaFlowLoggingMiddleware>.Instance);
        await middleware.InvokeAsync(context, collector, db, new CompanyAccessor());
        var log = Assert.Single(await db.HoppaApiCallLogs.ToListAsync());
        Assert.Equal(400, log.AppStatusCode);
        Assert.Null(log.IpAddress);
        Assert.Contains("REDACTED REFERRAL", log.AppRequestJson!);
        Assert.Contains("invalid-request", log.AppResponseJson!);
        Assert.Contains("pending", log.AppQueryString!);
        Assert.DoesNotContain("private-", log.AppRequestJson! + log.AppQueryString!);
    }

    [Fact]
    public async Task ReferralObservationFieldsAreRedactedFromCollectedUpstreamBodies()
    {
        await using var db = Database();
        var context = Context("/api/v1/admin/referrals/program", "application/json", new MemoryStream());
        context.Request.ContentLength = 0;
        var collector = new HoppaFlowLogCollector();
        collector.AddHoppaExchange(new HoppaExchangeLog { Endpoint = "/api/v2/referrals/signup-signals", Succeeded = true, StatusCode = 200,
            RequestJson = "{\"ServerObservedIp\":\"private-ip\",\"installation_token\":\"private-install\",\"InvitationToken\":\"private-invite\",\"source\":\"SIGNUP\"}",
            QueryString = "?invitationToken=private-token&status=pending" });
        var middleware = new HoppaFlowLoggingMiddleware(async ctx => await ctx.Response.WriteAsync("{\"status\":\"ok\"}"), NullLogger<HoppaFlowLoggingMiddleware>.Instance);
        await middleware.InvokeAsync(context, collector, db, new CompanyAccessor());
        var log = Assert.Single(await db.HoppaApiCallLogs.ToListAsync());
        Assert.Contains("SIGNUP", log.HoppaRequestJson!);
        Assert.Contains("pending", log.HoppaQueryString!);
        Assert.DoesNotContain("private-", log.HoppaRequestJson! + log.HoppaQueryString!);
    }

    private static NeoBankingDbContext Database() => new(new DbContextOptionsBuilder<NeoBankingDbContext>()
        .UseInMemoryDatabase($"receipt-logging-{Guid.NewGuid()}").Options);

    private static DefaultHttpContext Context(string path, string contentType, Stream body)
    {
        var context = new DefaultHttpContext();
        context.Request.Path = path;
        context.Request.Method = "POST";
        context.Request.ContentType = contentType;
        context.Request.ContentLength = 100_000;
        context.Request.Body = body;
        context.Response.Body = new MemoryStream();
        return context;
    }

    private static HoppaFlowLogCollector Collector()
    {
        var collector = new HoppaFlowLogCollector();
        collector.AddHoppaExchange(new HoppaExchangeLog { Endpoint = "/test", Succeeded = true, StatusCode = 200 });
        return collector;
    }

    private sealed class CompanyAccessor : ICompanyContextAccessor
    {
        public ICompanyContext Current { get; private set; } = CompanyContext.Empty;
        public void SetCurrent(ICompanyContext context) => Current = context;
        public void Clear() => Current = CompanyContext.Empty;
    }

    private sealed class MustNotReadStream : Stream
    {
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override int Read(byte[] buffer, int offset, int count) => throw new InvalidOperationException("Audit middleware read a private image.");
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default) =>
            throw new InvalidOperationException("Audit middleware read a private image.");
    }
}
