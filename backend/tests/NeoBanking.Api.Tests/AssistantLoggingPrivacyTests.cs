using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using NeoBanking.Api.HoppaLogging;
using NeoBanking.Application.Company;
using NeoBanking.Application.Interfaces;
using NeoBanking.Infrastructure.Persistence;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class AssistantLoggingPrivacyTests
{
    [Theory]
    [InlineData("/api/v1/mobile/assistant/chat")]
    [InlineData("/API/V1/MOBILE/ASSISTANT/CHAT")]
    [InlineData("/api/v1/mobile/assistant/usage")]
    public async Task AssistantSkipsRequestResponseBufferingAndAuditPersistence(string path)
    {
        await using var db = new NeoBankingDbContext(new DbContextOptionsBuilder<NeoBankingDbContext>()
            .UseInMemoryDatabase($"assistant-privacy-{Guid.NewGuid()}").Options);
        var context = new DefaultHttpContext();
        context.Request.Path = path;
        context.Request.ContentType = "application/json";
        context.Request.ContentLength = 100;
        context.Request.Body = new MustNotReadStream();
        context.Response.Body = new MemoryStream();
        var originalRequest = context.Request.Body;
        var originalResponse = context.Response.Body;
        var called = false;
        var middleware = new HoppaFlowLoggingMiddleware(async http =>
        {
            called = true;
            Assert.Same(originalRequest, http.Request.Body);
            Assert.Same(originalResponse, http.Response.Body);
            await http.Response.WriteAsync("private conversation");
        }, NullLogger<HoppaFlowLoggingMiddleware>.Instance);
        var collector = new HoppaFlowLogCollector();
        collector.AddHoppaExchange(new HoppaExchangeLog { Endpoint = "/test", Succeeded = true, StatusCode = 200 });
        await middleware.InvokeAsync(context, collector, db, new CompanyAccessor());
        Assert.True(called);
        Assert.Empty(await db.HoppaApiCallLogs.ToListAsync());
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
        public override int Read(byte[] buffer, int offset, int count) => throw new InvalidOperationException("Private chat was read.");
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default) =>
            throw new InvalidOperationException("Private chat was read.");
    }
}
