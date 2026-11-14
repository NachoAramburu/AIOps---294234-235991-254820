# Trazas distribuidas (C11)

Letra: *"Trazas de acuerdo a OTLP"* y *"trazas con propagación de contexto de acuerdo a OpenTelemetry"*.

## Conceptos

- **Traza:** el recorrido completo de una request por el sistema. Tiene un identificador único, el `traceID`.
- **Span:** un tramo de ese recorrido. Por ejemplo, "el gateway atendió `POST /api/login`", "el servicio de usuarios atendió la misma request" o "se ejecutó esta consulta SQL". Cada span tiene su `spanID`, un inicio, una duración y el `spanID` de su padre. Con eso Jaeger arma el árbol.
- **`traceparent`:** header HTTP estándar ([W3C Trace Context](https://www.w3.org/TR/trace-context/)) que lleva el contexto de un servicio al siguiente. Tiene la forma `00-<traceID de 32 hex>-<spanID del padre, 16 hex>-<flags>`. El servicio que lo recibe continúa la misma traza en lugar de empezar una nueva. Eso es la **propagación de contexto**.

## Cómo está armado

```
navegador ──► Ingress ──► gateway (YARP) ──traceparent──► users / pharmacy ──► SQL Server
                             │                                │
                             └──────── OTLP gRPC ─────────────┘
                                          ▼
                                   otlp-collector ──OTLP──► Jaeger (UI :16686)
```

1. **SDK en cada servicio.** `PharmaGo.Telemetry` (`AddPharmaGoTelemetry`) activa `WithTracing` con tres instrumentaciones automáticas:
   - **ASP.NET Core:** un span por cada request entrante. Se filtran `/health*` y `/metrics` para que los probes de Kubernetes (cada 2 a 3 s por pod) no llenen Jaeger de ruido.
   - **HttpClient:** spans de llamadas salientes.
   - **SqlClient:** un span por consulta, con el texto SQL (`SetDbStatementForText`) y la excepción si falla (`RecordException`).
2. **Propagación por YARP.** El gateway reenvía con YARP. La fábrica de clientes de YARP (`ForwarderHttpClientFactory.WrapHandler`) agrega su `ActivityPropagationHandler`, que escribe `traceparent` en la request saliente con el span actual del gateway. `ResilientForwarderHttpClientFactory` (C07) llama a `base.WrapHandler` y conserva ese handler. Los reintentos de Polly reenvían la misma request, con la misma traza.
3. **Exportación.** El SDK manda los spans por OTLP a `OTEL_EXPORTER_OTLP_ENDPOINT` (`http://otlp-collector:4317`, definido en cada Deployment). Cada span lleva `service.name`, `service.instance.id` (el pod), `k8s.pod.name` y `k8s.node.name`.
4. **Collector.** Usa el pipeline `traces`: receiver `otlp`, processors `memory_limiter` y `batch`, y exporter `otlp/jaeger` a `jaeger:4317`.
5. **Jaeger.** `jaegertracing/all-in-one:1.60.0` en el nodo `ops`. Guarda en memoria hasta 5000 trazas (`--memory.max-traces`); si el pod se reinicia, se pierden. Para una demo y para la defensa alcanza (D34).

## Cómo buscar una traza

1. `cd "Implementacion K8S/Codigo/k8s" && ./port-forward.sh` y abrí <http://127.0.0.1:16686>.
2. En **Service** elegí `PharmaGo.ApiGateway`. Si hace falta, filtrá **Operation** (por ejemplo `POST` o `GET`) o **Tags** (`http.response.status_code=500`). Después tocá **Find Traces**.
3. Abrí una traza. El primer nivel es el span del gateway. Debajo están el span del servicio (`PharmaGo.UsersService` o `PharmaGo.PharmacyService`) y, debajo de ese, los spans de SQL (`PharmaDb`, con la consulta en `db.statement`).
4. Para pasar de un log a su traza: copiá el `trace_id` del log en Kibana (C14) y pegalo en el buscador de Jaeger (arriba a la izquierda, **Lookup by Trace ID**).

Por API, útil para scripts y evidencia:

```bash
curl -s "http://127.0.0.1:16686/api/traces?service=PharmaGo.ApiGateway&limit=20"
curl -s "http://127.0.0.1:16686/api/traces/<traceID>"
```

## Qué mirar en un incidente

- **Latencia alta:** buscá trazas con `Min Duration` alto y fijate qué span ocupa la mayor parte del tiempo: gateway, servicio o SQL.
- **Errores 5xx:** filtrá por tag `error=true`. Si el span de SQL tiene la excepción, el problema es la base.
- **Circuit breaker abierto:** el gateway responde 503 sin span hijo del servicio, porque la request nunca salió. Ver `docs/resiliencia.md`.
