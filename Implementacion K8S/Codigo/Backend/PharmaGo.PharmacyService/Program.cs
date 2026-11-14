using PharmaGo.PharmacyService.Factory;
using PharmaGo.PharmacyService.Filters;
using System.Diagnostics.CodeAnalysis;
using Instrumentation;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using PharmaGo.Telemetry;

var builder = WebApplication.CreateBuilder(args);

builder.Logging.SuppressEfAndSqlClientLogs();

builder.Services.AddHttpContextAccessor();
builder.Services.RegisterBusinessLogicServices(builder.Configuration);
builder.Services.RegisterDataAccessServices(builder.Configuration);
builder.Services.AddControllers(options => options.Filters.Add(typeof(ExceptionFilter)));

builder.Services.AddControllers();

builder.Services.AddHealthChecks()
    .AddCheck("self", () => HealthCheckResult.Healthy(), tags: new[] { "live" })
    .AddDbContextCheck<DbContext>("db", tags: new[] { "ready" });

// Métricas por OTLP al Collector (C10). Prometheus ya no scrapea al servicio.
builder.Services.AddPharmaGoTelemetry("PharmaGo.PharmacyService");

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddCors(options =>
{
    options.AddPolicy("MyAllowedOrigins",
        policy =>
        {
            policy.WithOrigins("*")
                .AllowAnyHeader()
                .AllowAnyMethod();
        });
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors("MyAllowedOrigins");
app.UseServiceCorrelationScope();

app.UseAuthorization();

app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = check => check.Tags.Contains("live") });
app.MapHealthChecks("/health/ready", new HealthCheckOptions { Predicate = check => check.Tags.Contains("ready") });
app.MapHealthChecks("/health", new HealthCheckOptions { Predicate = check => check.Tags.Contains("live") });
app.UseMetricsMiddleware();

app.MapControllers();

app.Run();

[ExcludeFromCodeCoverage]
public partial class Program { }

