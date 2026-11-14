using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

namespace PharmaGo.Telemetry
{
    /// <summary>
    /// Telemetría común de los servicios desplegados. Métricas y trazas salen por OTLP al Collector;
    /// Prometheus solo scrapea el Collector (C10) y las trazas siguen a Jaeger (C11).
    /// </summary>
    public static class TelemetryExtensions
    {
        /// <summary>Intervalo de exportación de métricas: cada 5 s, para que las alertas reaccionen rápido.</summary>
        private const int MetricExportIntervalMs = 5000;

        public static IServiceCollection AddPharmaGoTelemetry(this IServiceCollection services, string serviceName)
        {
            // El endpoint OTLP no se hardcodea: el SDK lo lee de OTEL_EXPORTER_OTLP_ENDPOINT,
            // y los atributos del pod y del nodo de OTEL_RESOURCE_ATTRIBUTES (los define el Deployment).
            // serviceInstanceId = nombre del pod, así cada réplica es una serie distinta.
            services.AddOpenTelemetry()
                .ConfigureResource(resource => resource.AddService(serviceName, serviceInstanceId: Environment.MachineName))
                .WithMetrics(metrics => metrics
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddMeter("PharmaGo.CustomMetrics")
                    .AddOtlpExporter((_, reader) =>
                        reader.PeriodicExportingMetricReaderOptions.ExportIntervalMilliseconds = MetricExportIntervalMs))
                // Trazas (C11): un span por request entrante (ASP.NET), por llamada saliente (HttpClient,
                // que es lo que usa YARP en el gateway) y por consulta a la base (SqlClient).
                // El contexto viaja en el header W3C traceparent, que agrega la instrumentación de HttpClient.
                .WithTracing(tracing => tracing
                    .AddAspNetCoreInstrumentation(options => options.Filter = context => !IsProbeOrScrape(context.Request.Path))
                    .AddHttpClientInstrumentation()
                    .AddSqlClientInstrumentation(options =>
                    {
                        options.SetDbStatementForText = true;
                        options.RecordException = true;
                    })
                    .AddOtlpExporter());

            return services;
        }

        /// <summary>Los probes de Kubernetes y /metrics no son tráfico de usuario: no generan trazas.</summary>
        private static bool IsProbeOrScrape(PathString path) =>
            path.StartsWithSegments("/health") || path.StartsWithSegments("/metrics");
    }
}
