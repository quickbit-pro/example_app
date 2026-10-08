using Microsoft.Extensions.Hosting;
using NeoBanking.Application;
using NeoBanking.Infrastructure;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddNeoBankingApplication();
builder.Services.AddNeoBankingInfrastructure(builder.Configuration);

var app = builder.Build();

await app.RunAsync();
