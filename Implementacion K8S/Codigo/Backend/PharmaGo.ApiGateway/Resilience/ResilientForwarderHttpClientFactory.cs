using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using InstrumentationInterface;
using Polly;
using Polly.CircuitBreaker;
using Polly.Timeout;
using Polly.Wrap;
using Yarp.ReverseProxy.Forwarder;

namespace PharmaGo.ApiGateway.Resilience;

/// <summary>
/// Cliente HTTP de YARP con resiliencia en el único salto HTTP real del sistema (gateway -> servicio).
/// Por cluster: timeout por intento, circuit breaker (Closed -> Open -> Half-Open) y, solo para GET/HEAD,
/// reintentos con backoff exponencial y jitter. Los POST/PUT/DELETE nunca se reintentan para no duplicar operaciones.
/// Parámetros en la sección "Resilience" de appsettings.json (docs/resiliencia.md).
/// </summary>
public sealed class ResilientForwarderHttpClientFactory : ForwarderHttpClientFactory
{
    private readonly ConcurrentDictionary<string, ClusterPolicies> _policies = new();
    private readonly ICustomMetrics _metrics;
    private readonly ILogger<ResilientForwarderHttpClientFactory> _logger;
    private readonly IConfiguration _configuration;

    public ResilientForwarderHttpClientFactory(ICustomMetrics metrics, ILogger<ResilientForwarderHttpClientFactory> logger, IConfiguration configuration)
    {
        _metrics = metrics;
        _logger = logger;
        _configuration = configuration;
    }

    protected override void ConfigureHandler(ForwarderHttpClientContext context, SocketsHttpHandler handler)
    {
        base.ConfigureHandler(context, handler);
        // Renovar conexiones cada 15 s: el tráfico rota entre réplicas y deja de usar pods que murieron.
        handler.PooledConnectionLifetime = TimeSpan.FromSeconds(_configuration.GetValue("Resilience:PooledConnectionLifetimeSeconds", 15));
    }

    protected override HttpMessageHandler WrapHandler(ForwarderHttpClientContext context, HttpMessageHandler handler)
    {
        var inner = base.WrapHandler(context, handler);
        var policies = _policies.GetOrAdd(context.ClusterId, Build);
        return new ResilienceHandler(policies) { InnerHandler = inner };
    }

    private ClusterPolicies Build(string cluster)
    {
        var o = _configuration.GetSection("Resilience");
        var perTryTimeout = TimeSpan.FromSeconds(o.GetValue("PerTryTimeoutSeconds", 3));
        var retries = o.GetValue("RetryCount", 2);
        var baseDelayMs = o.GetValue("RetryBaseDelayMs", 100);
        var failureRatio = o.GetValue("BreakerFailureRatio", 0.5);
        var sampling = TimeSpan.FromSeconds(o.GetValue("BreakerSamplingSeconds", 10));
        var minThroughput = o.GetValue("BreakerMinimumThroughput", 8);
        var breakFor = TimeSpan.FromSeconds(o.GetValue("BreakerDurationSeconds", 5));

        var timeout = Policy.TimeoutAsync<HttpResponseMessage>(perTryTimeout, TimeoutStrategy.Optimistic);

        var breaker = Policy<HttpResponseMessage>
            .Handle<HttpRequestException>()
            .Or<TimeoutRejectedException>()
            .OrResult(r => (int)r.StatusCode >= 500)
            .AdvancedCircuitBreakerAsync(failureRatio, sampling, minThroughput, breakFor,
                onBreak: (_, wait) => Transition(cluster, 1, $"open for {wait.TotalSeconds}s"),
                onReset: () => Transition(cluster, 0, "closed"),
                onHalfOpen: () => Transition(cluster, 2, "half-open"));

        var retry = Policy<HttpResponseMessage>
            .Handle<HttpRequestException>()
            .Or<TimeoutRejectedException>()
            .OrResult(r => r.StatusCode is HttpStatusCode.BadGateway or HttpStatusCode.ServiceUnavailable or HttpStatusCode.GatewayTimeout)
            .WaitAndRetryAsync(retries, attempt =>
                TimeSpan.FromMilliseconds(baseDelayMs * Math.Pow(2, attempt - 1) + Random.Shared.Next(0, baseDelayMs)));

        _metrics.SetCircuitState(cluster, 0);
        return new ClusterPolicies(Policy.WrapAsync(retry, breaker, timeout), Policy.WrapAsync(breaker, timeout));
    }

    private void Transition(string cluster, int state, string detail)
    {
        _metrics.SetCircuitState(cluster, state);
        _logger.LogWarning("circuit_breaker cluster={Cluster} state={State}", cluster, detail);
    }

    private sealed record ClusterPolicies(AsyncPolicyWrap<HttpResponseMessage> Idempotent, AsyncPolicyWrap<HttpResponseMessage> NonIdempotent);

    private sealed class ResilienceHandler : DelegatingHandler
    {
        private readonly ClusterPolicies _policies;

        public ResilienceHandler(ClusterPolicies policies) => _policies = policies;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var idempotent = request.Method == HttpMethod.Get || request.Method == HttpMethod.Head;
            var policy = idempotent ? _policies.Idempotent : _policies.NonIdempotent;
            try
            {
                return await policy.ExecuteAsync(ct => base.SendAsync(request, ct), cancellationToken);
            }
            catch (BrokenCircuitException)
            {
                var response = Error(request, HttpStatusCode.ServiceUnavailable, "circuit_open");
                response.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(5));
                return response;
            }
            catch (TimeoutRejectedException)
            {
                return Error(request, HttpStatusCode.GatewayTimeout, "upstream_timeout");
            }
        }

        private static HttpResponseMessage Error(HttpRequestMessage request, HttpStatusCode code, string error) => new(code)
        {
            RequestMessage = request,
            Content = new StringContent($"{{\"error\":\"{error}\"}}", Encoding.UTF8, "application/json"),
        };
    }
}
