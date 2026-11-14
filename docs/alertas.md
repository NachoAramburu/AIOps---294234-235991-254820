# Alertas de Grafana (C13)

La letra pide "por lo menos 5 alertas en Grafana para detección de anomalías de las métricas ya definidas". Hay **10**, que cubren los cuatro Golden Signals (latencia, tráfico, errores y saturación), la disponibilidad y cada tipo de falla que se simula con los scripts de caos.

## Cómo están armadas

- **Como código:** `Implementacion K8S/Codigo/k8s/configmaps/grafana-alerting.yaml`, montado en `/etc/grafana/provisioning/alerting/alerts.yaml`. Grafana las carga solas al arrancar, en la carpeta **PharmaGo** (Alerting, Alert rules). No hace falta ningún clic.
- **Formato de provisioning de Grafana 10.4:** un grupo `pharmago` que se evalúa cada 10 s, con datasource `prometheus`.
- **Cada regla tiene tres pasos:** A, una consulta PromQL instantánea; B, `reduce last`; y C, `threshold`. La alerta pasa a *Pending* cuando C se cumple y a *Firing* cuando se sostiene durante la ventana (`for`).
- **Estados:** `noDataState: OK` hace que la falta de datos, por ejemplo sin tráfico, no dispare. `execErrState: Alerting` hace que una consulta rota sí dispare.
- **Etiquetas y anotaciones:** cada regla tiene `severity` (la severidad de `docs/plan-incidentes.md`), `signal`, `summary` y `runbook` (el playbook de B7).
- **Una alerta accionable** responde "pasó algo que requiere que hagas X": por eso cada una nombra el playbook. La ventana `for` evita avisar por un pico de un instante.
- Las métricas de la app se filtran con `job="PharmaGo.ApiGateway"`, porque es lo que ve el usuario y así cada request no se cuenta dos veces (gateway y servicio). Los nombres de las métricas salen de `docs/evidencia/C12/nombres-metricas.txt`.

## Reglas

| uid | Señal | Query (A) | Umbral (C) | Ventana | Por qué ese valor | Tipo de falla | Panel donde se ve |
|---|---|---|---|---|---|---|---|
| `pg-5xx` | Errores | `(sum(rate(pharmago_http_requests_total{job="PharmaGo.ApiGateway",status_code=~"5.."}[1m])) or vector(0)) / sum(rate(pharmago_http_requests_total{job="PharmaGo.ApiGateway"}[1m]))` | > 0,05 (5 %) | 30 s | 5 % es el límite inferior de SEV2 del plan de incidentes. Con 2 réplicas, retry y breaker, en estado normal hay 0 % (B1) | Red, desconexión, caída de la BD | Overview: "Tasa de Error por Endpoint (%)" y "Distribución de Status Codes (%)" |
| `pg-latency` | Latencia | `histogram_quantile(0.95, sum by (le) (rate(pharmago_http_request_duration_milliseconds_bucket{job="PharmaGo.ApiGateway"}[1m])))` | > 1000 ms | 1 min | El gateway corta cada intento a los 3 s (D13): un P95 de 1 s ya indica que un servicio responde lento o con reintentos. Es el criterio SEV2 del plan | CPU saturada, red, BD lenta | Overview: "Latencia Promedio por Endpoint" |
| `pg-latency-anomaly` | Latencia (anomalía) | z-score k-sigma: `(abs(L - avg_over_time(L[30m:30s])) > 50) / stddev_over_time(L[30m:30s])`, con `L = sum(rate(..._sum{job="PharmaGo.ApiGateway"}[1m])) / sum(rate(..._count{job="PharmaGo.ApiGateway"}[1m]))` (query completa en el YAML) | > 3 desvíos | 1 min | Es el detector k-sigma del laboratorio de anomalías (C15) aplicado en PromQL: avisa cuando la latencia media se aleja más de 3 desvíos de su propio promedio de 30 min. El piso de 50 ms evita falsos positivos cuando la latencia es muy estable y su desvío es casi 0 | Cualquier degradación gradual, aunque no llegue a 1 s | Overview: "Latencia Promedio por Endpoint" |
| `pg-429` | Tráfico | `sum(rate(pharmago_http_requests_total{job="PharmaGo.ApiGateway",status_code="429"}[1m])) or vector(0)` | > 1 por segundo | 30 s | Un 429 suelto es un usuario impaciente. Más de 1 por segundo sostenido es una ráfaga, el caso de inyección de requests. Es SEV3: la protección está funcionando | Inyección de requests | Overview: "Rate Limit Errors (429) por Endpoint" |
| `pg-cpu` | Saturación | `max by (k8s_pod_name) (k8s_pod_cpu_limit_utilization_ratio{k8s_namespace_name="pharmago"})` | > 0,8 (80 %) | 30 s | Pasado el 80 % del límite, el contenedor empieza a sufrir throttling (en C16 se vio llegar al 100 %). Se usa `cpu_limit_utilization` porque `cpu_utilization` está en núcleos, no en porcentaje (C12) | Sobrecarga de CPU | Infra: "CPU del contenedor contra su límite" y "CPU por pod (núcleos)" |
| `pg-memory` | Saturación | `max by (k8s_pod_name) (k8s_pod_memory_limit_utilization_ratio{k8s_namespace_name="pharmago"})` | > 0,85 (85 %) | 30 s | Por encima del 85 % del límite queda poco margen antes de que el OOM killer actúe (C16). Es el criterio SEV2 del plan | Sobrecarga de memoria | Infra: "Memoria del pod contra su límite" |
| `pg-storage` | Saturación | `max by (k8s_pod_name) (k8s_pod_filesystem_usage_bytes{k8s_namespace_name="pharmago"}) / 1048576` | > 300 MiB | 30 s | El límite de `ephemeral-storage` es 512 MiB y el kubelet desaloja al superarlo (C16). Con 300 MiB se avisa antes del desalojo; en estado normal un pod usa pocos MiB | Sobrecarga de storage | Infra: "Filesystem por pod (ephemeral-storage usado)" |
| `pg-restarts` | Errores | `sum by (k8s_pod_name, k8s_container_name) (increase(k8s_container_restarts{k8s_namespace_name="pharmago"}[2m]))` | > 0 | 0 s | Un reinicio es el síntoma de un crash o de una liveness fallida. Se usa `increase` porque el contador es acumulado (C12). Sin ventana, porque el evento ya pasó | Proceso caído, liveness fallida | Infra: "Reinicios por contenedor" |
| `pg-replicas` | Disponibilidad | `max by (k8s_deployment_name) (k8s_deployment_desired{k8s_namespace_name="pharmago"} - k8s_deployment_available{k8s_namespace_name="pharmago"})` | > 0 | 30 s | Con `maxUnavailable: 0` (C08), en un rollout sano nunca faltan réplicas. 30 s tapa el reemplazo normal de un pod borrado (MTTR de 3 a 9 s, `docs/mttr.md`) | Pod caído, desalojo, rollout trabado | Infra: "Réplicas deseadas y disponibles por Deployment" |
| `pg-breaker` | Errores | `max by (cluster) (pharmago_circuit_breaker_state == 1)` | > 0 (abierto) | 0 s | El breaker abierto significa que un servicio está fallando y el gateway ya devuelve 503 (D13). Es SEV1 en el plan. Se filtra `== 1` para no contar half-open (2) | Desconexión, red, caída de la BD | Overview: "Distribución de Status Codes (%)" (503). La métrica, en Prometheus: `pharmago_circuit_breaker_state` |

Las columnas de playbook y su validación las completa C20 (bloque B7). La anotación `runbook` de cada regla ya apunta al playbook que nombra `docs/plan-incidentes.md`.

## Limitaciones

- **`pg-replicas` y la desconexión:** `disconnect.sh` escala el Deployment a 0, así que también baja las réplicas deseadas y esta alerta no dispara. Esa falla la detectan `pg-5xx` y `pg-breaker`.
- **`pg-latency-anomaly` necesita historia:** el promedio y el desvío salen de los últimos 30 min de tráfico. Con el cluster recién levantado y sin tráfico, no tiene con qué comparar y no dispara.
- **`pg-429` y el rate limit:** el límite es por réplica del gateway (C16), así que con 2 réplicas hacen falta más requests de las que dice la configuración para ver 429.
