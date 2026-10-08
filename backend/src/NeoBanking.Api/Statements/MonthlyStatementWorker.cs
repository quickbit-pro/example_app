using Microsoft.EntityFrameworkCore;
using NeoBanking.Api.Documents;
using NeoBanking.Infrastructure.Persistence;
namespace NeoBanking.Api.Statements;
public sealed class MonthlyStatementWorker(IServiceScopeFactory scopes, ILogger<MonthlyStatementWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stop)
    {
        while(!stop.IsCancellationRequested)
        {
            try { await RunNextAsync(stop); }
            catch(OperationCanceledException) when(stop.IsCancellationRequested) { break; }
            catch(Exception e) { logger.LogWarning("Monthly export worker unavailable ({ErrorType}).",e.GetType().Name); }
            try { await Task.Delay(TimeSpan.FromSeconds(3),stop); } catch(OperationCanceledException) { break; }
        }
    }
    public async Task RunNextAsync(CancellationToken stop)
    {
        await using var scope=scopes.CreateAsyncScope(); var db=scope.ServiceProvider.GetRequiredService<NeoBankingDbContext>();
        var now=DateTimeOffset.UtcNow; var stale=now.AddMinutes(-10);
        var job=await db.MonthlyStatementExports.AsNoTracking().Where(j=>j.Status=="queued" || j.Status=="processing" && j.UpdatedAt<stale).OrderBy(j=>j.CreatedAt).FirstOrDefaultAsync(stop);
        if(job is null) return;
        var claimed=await db.MonthlyStatementExports.Where(j=>j.Id==job.Id && (j.Status=="queued" || j.Status=="processing" && j.UpdatedAt<stale))
            .ExecuteUpdateAsync(s=>s.SetProperty(j=>j.Status,"processing").SetProperty(j=>j.UpdatedAt,now).SetProperty(j=>j.Attempt,j=>j.Attempt+1),stop);
        if(claimed==0) return; job.Attempt++;
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(stop); timeout.CancelAfter(TimeSpan.FromMinutes(6));
        try
        {
            if(job.Attempt>3) throw new StatementExportException("The export was interrupted. Please create it again.");
            var result=await scope.ServiceProvider.GetRequiredService<MonthlyStatementBuilder>().BuildAsync(job,timeout.Token);
            var key=$"{job.CompanyInstallationId:N}/{job.OwnerUserId:N}/statements/{job.Id:N}-{job.Attempt}.zip";
            await scope.ServiceProvider.GetRequiredService<IPrivateDocumentBlobStore>().UploadAsync(key,result.Bytes,"application/zip",timeout.Token);
            await db.MonthlyStatementExports.Where(j=>j.Id==job.Id && j.Attempt==job.Attempt && j.Status=="processing")
                .ExecuteUpdateAsync(s=>s.SetProperty(j=>j.Status,"ready").SetProperty(j=>j.BlobKey,key).SetProperty(j=>j.ByteLength,result.Bytes.LongLength)
                    .SetProperty(j=>j.TransactionCount,result.Transactions).SetProperty(j=>j.AttachmentCount,result.Attachments).SetProperty(j=>j.UpdatedAt,DateTimeOffset.UtcNow),timeout.Token);
        }
        catch(OperationCanceledException) when(stop.IsCancellationRequested) { throw; }
        catch(Exception e)
        {
            logger.LogWarning("Monthly export failed ({ErrorType}).",e.GetType().Name);
            // Only controlled validation messages are user-visible; storage/provider exceptions never expose credentials.
            var message=e is StatementExportException && e.Message.Length<300 ? e.Message : "The monthly export could not be completed. Please try again.";
            await db.MonthlyStatementExports.Where(j=>j.Id==job.Id && j.Attempt==job.Attempt && j.Status=="processing")
                .ExecuteUpdateAsync(s=>s.SetProperty(j=>j.Status,"failed").SetProperty(j=>j.ErrorMessage,message).SetProperty(j=>j.UpdatedAt,DateTimeOffset.UtcNow),stop);
        }
    }
}
