# Logs estructurados (C14)

La letra pide "logs estructurados en JSON" que puedan "consultarse en alguna herramienta de manejo de logs como Kibana con ElasticSearch".

## El camino de un log

```
app (consola, JSON)  ->  archivo del contenedor en el nodo  ->  Fluent Bit (DaemonSet, uno por nodo)
                     ->  Elasticsearch (índice pharmago-logs-AAAA.MM.DD)  ->  Kibana (data view "PharmaGo logs")
```

1. **Los 3 servicios .NET** escriben con el formatter JSON de consola (`Logging.Console.FormatterName: json`, con `IncludeScopes` en `appsettings.json`).
2. **La UI** (nginx) escribe cada request con `log_format json_combined escape=json` en `Frontend/nginx.conf`.
3. **Docker** guarda la salida de cada contenedor en `/var/log/containers/*.log` del nodo.
4. **Fluent Bit** la lee:
   - le agrega los datos de Kubernetes (`kubernetes.pod_name`, `kubernetes.labels.app`, etc.);
   - si la línea es JSON, sube sus campos al primer nivel (`Message`, `LogLevel`, `Category`, `Scopes`, o los de nginx);
   - y la manda a Elasticsearch.
5. **Kibana** consulta el índice. El data view lo crea `k8s/setup-kibana.sh`, que se puede correr varias veces.

## Correlación con las trazas

Cada request de los 3 servicios .NET abre un scope de log con:

| Campo en `Scopes` | Qué es |
|---|---|
| `correlation_id` | El `X-Correlation-ID` que genera el gateway y reenvía a los servicios |
| `trace_id` | El trace ID de OpenTelemetry (`Activity.Current`), el mismo que muestra Jaeger |
| `span_id` | El span de esa request en ese servicio |

Así, desde una traza lenta de Jaeger se copian sus 32 caracteres de trace ID y se buscan en Kibana los logs exactos de esa request, en el gateway y en el servicio. El gateway abre el scope en `UseGatewayCorrelationId` y los servicios en `UseServiceCorrelationScope` (`Instrumentation/CorrelationIdMiddlewareExtensions.cs`).

## Campos útiles

| Campo | De dónde sale | Ejemplo |
|---|---|---|
| `@timestamp` | Fluent Bit | `2026-11-14T15:02:11.123Z` |
| `kubernetes.labels.app` | Fluent Bit | `pharmago-api-gateway` |
| `kubernetes.pod_name` | Fluent Bit | `pharmago-api-gateway-6d6656b845-vp8fz` |
| `LogLevel` | .NET | `Information`, `Warning`, `Error` |
| `Category` | .NET | `Yarp.ReverseProxy.Forwarder.HttpForwarder` |
| `Message` | .NET | El texto del log |
| `Scopes.trace_id` / `Scopes.span_id` / `Scopes.correlation_id` | .NET (C14) | `4bf92f3577b34da6a3ce929d0e0e4736` |
| `status`, `request`, `request_time`, `http_x_correlation_id` | nginx (UI) | `200`, `GET / HTTP/1.1`, `0.001` |

## Consultas de Kibana listas para copiar (KQL, en Discover)

1. **Los logs de una traza de Jaeger:**
   ```
   Scopes.trace_id : "<trace id de Jaeger>"
   ```
2. **Errores de cualquier servicio .NET:**
   ```
   LogLevel : "Error" or LogLevel : "Critical"
   ```
3. **Logs del gateway durante un incidente** (ajustar el rango de tiempo arriba a la derecha):
   ```
   kubernetes.labels.app : "pharmago-api-gateway" and not LogLevel : "Information"
   ```
4. **Transiciones del circuit breaker:**
   ```
   kubernetes.labels.app : "pharmago-api-gateway" and Message : "circuit_breaker"
   ```
5. **Requests de la UI que no dieron 2xx:**
   ```
   kubernetes.labels.app : "pharmago-ui" and status >= 400
   ```

Con `Scopes.correlation_id : "<id>"` se siguen las requests que no tienen traza (por ejemplo, las que cortó el rate limit con 429).

## Qué no es JSON

Las líneas que escribe el runtime antes de que arranque el logger (por ejemplo, el aviso de nginx al iniciar) son texto. Quedan en el campo `log` de Elasticsearch, sin campos propios. Las cuenta la evidencia de C14.
