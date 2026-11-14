using System;
using System.Collections.Generic;
using System.Diagnostics.Metrics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using InstrumentationInterface;

namespace Instrumentation
{
    public class CustomMetrics : ICustomMetrics, IDisposable
    {
        private readonly Meter _meter;
        private readonly Counter<long> _loginInvocationsCounter;
        private readonly Counter<long> _httpRequestsCounter;
        private readonly Counter<long> _httpErrorsCounter;
        private readonly Histogram<double> _requestDurationHistogram;
        private readonly Histogram<double> _endpointDurationHistogram;
        private int _activeUserCount;
        private readonly System.Collections.Concurrent.ConcurrentDictionary<string, int> _circuitStates = new();

        public CustomMetrics()
        {
            _meter = new Meter("PharmaGo.CustomMetrics");

            _loginInvocationsCounter = _meter.CreateCounter<long>(
                "login_invocations",
                unit: "1",
                description: "Counts the number of login invocations"
            );

            _httpRequestsCounter = _meter.CreateCounter<long>(
                "pharmago_http_requests_total",
                unit: "1",
                description: "Total number of HTTP requests by endpoint, method, and status code"
            );

            _httpErrorsCounter = _meter.CreateCounter<long>(
                "pharmago_http_errors_total",
                unit: "1",
                description: "Total number of HTTP errors by endpoint and error type"
            );

            _requestDurationHistogram = _meter.CreateHistogram<double>(
                "request_duration",
                unit: "ms",
                description: "Records the duration of requests in milliseconds"
            );

            _endpointDurationHistogram = _meter.CreateHistogram<double>(
                "pharmago_http_request_duration_milliseconds",
                unit: "ms",
                description: "HTTP request duration in milliseconds by endpoint and method"
            );

            // Sin unidad a proposito: con "1" Prometheus le agrega el sufijo _ratio, y con "{state}"
            // el exporter Prometheus de .NET deforma el nombre a pharmago_circuit_breaker_state__state_.
            _meter.CreateObservableGauge(
                "pharmago_circuit_breaker_state",
                () => _circuitStates.Select(kv => new Measurement<int>(kv.Value, new KeyValuePair<string, object?>("cluster", kv.Key))),
                unit: null,
                description: "Circuit breaker state per gateway cluster: 0=closed 1=open 2=half-open"
            );

            _meter.CreateObservableGauge(
                "active_user_count",
                () => new Measurement<int>[] { new Measurement<int>(_activeUserCount) },
                unit: "1",
                description: "The current number of active users"
            );
        }

        public void LoginInvocations(long value = 1)
        {
            Console.WriteLine("Logging invocation");
            _loginInvocationsCounter.Add(value);
        }

        public void RecordHttpRequest(string endpoint, string method, int statusCode)
        {
            var tags = new KeyValuePair<string, object?>[]
            {
                new("endpoint", endpoint),
                new("method", method),
                new("status_code", statusCode.ToString())
            };
            _httpRequestsCounter.Add(1, tags);
        }

        public void RecordError(string endpoint, string errorType)
        {
            var tags = new KeyValuePair<string, object?>[]
            {
                new("endpoint", endpoint),
                new("error_type", errorType)
            };
            _httpErrorsCounter.Add(1, tags);
        }

        public void SetCircuitState(string cluster, int state)
        {
            _circuitStates[cluster] = state;
        }

        public void SetActiveUserCount(int count)
        {
            _activeUserCount = count;
        }

        public void RequestDuration(double milliseconds)
        {
            _requestDurationHistogram.Record(milliseconds);
        }

        public void RecordEndpointDuration(string endpoint, string method, double milliseconds)
        {
            var tags = new KeyValuePair<string, object?>[]
            {
                new("endpoint", endpoint),
                new("method", method)
            };
            _endpointDurationHistogram.Record(milliseconds, tags);
        }

        public void Dispose()
        {
            _meter?.Dispose();
        }
    }
}
