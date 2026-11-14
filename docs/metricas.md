# Métricas (C10 y C12)

Letra: *"Las métricas deben recolectarse con OTLP hacia Prometheus, visualización con Grafana"* y *"Métricas a nivel de pod/contenedor y nodo físico (se sugiere tener CPU, memoria, storage y red)"*.

## Cómo llegan a Prometheus

```
apps .NET (SDK OTel, cada 5 s) ──OTLP──┐
otel-agent ×5 (kubeletstats, 10 s) ─OTLP┼──► otlp-collector ──► exporter prometheus :8889 ◄── scrape ── Prometheus ──► Grafana
                k8s_cluster (API, 10 s) ┘    (memory_limiter, batch)
```

- **Prometheus scrapea un solo target:** `otlp-collector:8889`. No scrapea apps ni nodos (D30). La configuración está en `k8s/configmaps/prometheus-config.yaml`, que tiene un único job con `honor_labels: true`.
- **Apps:** `PharmaGo.Telemetry` exporta por OTLP a `OTEL_EXPORTER_OTLP_ENDPOINT`. Cada réplica es una serie distinta: `job` es el servicio e `instance` es el pod (`service.instance.id`). El Collector convierte los atributos de recurso en labels (`resource_to_telemetry_conversion`), así que también llegan `k8s_pod_name` y `k8s_node_name`. `MetricsMiddleware` no mide `/health*` ni `/metrics`: los probes no cuentan como tráfico.
- **Nodo, pod y contenedor:** el DaemonSet `otel-agent` corre un pod por nodo. Cada uno le pregunta a **su** kubelet (`https://<IP del nodo>:10250`) y agrega `k8s.node.name` (D31, D37).
- **Estado de Kubernetes:** el receiver `k8s_cluster` del Collector central lee la API y aporta reinicios, réplicas y condiciones de los nodos (D32).
- **Nombres:** el exporter cambia puntos por guiones bajos y agrega la unidad. Por ejemplo, `k8s.node.memory.working_set` (By) pasa a `k8s_node_memory_working_set_bytes`. La lista real, sacada del Collector, está en `docs/evidencia/C12/nombres-metricas.txt`.

## Tabla de métricas

| Métrica en Prometheus | Origen | Nivel | Qué mide | Panel |
|---|---|---|---|---|
| `pharmago_http_requests_total` | App (`PharmaGo.CustomMetrics`) | Réplica | Requests por endpoint, método y status (tráfico, errores) | Overview: Peticiones por segundo, Tasa de error, 429 |
| `pharmago_http_request_duration_milliseconds` | App | Réplica | Latencia por endpoint (histograma) | Overview: Latencia promedio por endpoint |
| `pharmago_circuit_breaker_state` | App (gateway, C07) | Réplica del gateway | 0 cerrado, 1 abierto, 2 medio abierto, por cluster de YARP (label `cluster`) | Alertas (C13) |
| `http_server_request_duration_seconds` | App (instrumentación ASP.NET Core) | Réplica | Latencia y status por ruta (`http_route`) | Alertas (C13) |
| `http_client_request_duration_seconds` | App (instrumentación HttpClient) | Réplica del gateway | Latencia de gateway hacia servicio | — |
| `k8s_node_cpu_utilization_ratio` | kubeletstats | Nodo | CPU usada, **en núcleos** | Infra: CPU por nodo |
| `k8s_node_memory_working_set_bytes` | kubeletstats | Nodo | Memoria en uso | Infra: Memoria por nodo |
| `k8s_node_filesystem_usage_bytes` / `_capacity_bytes` | kubeletstats | Nodo | Disco usado y total (ver limitación) | Infra: Filesystem por nodo |
| `k8s_node_network_io_bytes_total` | kubeletstats | Nodo | Bytes recibidos y enviados por `eth0` (`direction`) | Infra: Red por nodo |
| `k8s_node_condition_ready`, `_memory_pressure`, `_disk_pressure` | k8s_cluster | Nodo | Condiciones del nodo (1, 0 o -1) | Infra: Nodos Ready, Presión |
| `k8s_pod_cpu_utilization_ratio` | kubeletstats | Pod | CPU usada, en núcleos | Infra: CPU por pod |
| `k8s_pod_memory_working_set_bytes` | kubeletstats | Pod | Memoria en uso | Infra: Memoria por pod |
| `k8s_pod_memory_limit_utilization_ratio` | kubeletstats (opcional) | Pod | Memoria / límite (1 = 100 %) | Infra: Memoria del pod contra su límite |
| `k8s_pod_filesystem_usage_bytes` | kubeletstats | Pod | Ephemeral-storage usado (capa escribible y logs) | Infra: Filesystem por pod |
| `k8s_container_cpu_limit_utilization_ratio` | kubeletstats (opcional) | Contenedor | CPU / límite | Infra: CPU del contenedor contra su límite |
| `container_memory_working_set_bytes` ÷ `k8s_container_memory_limit_bytes` | kubeletstats + k8s_cluster | Contenedor | Memoria / límite | Infra: Memoria del contenedor contra su límite |
| `k8s_container_restarts` | k8s_cluster | Contenedor | Reinicios acumulados | Infra: Reinicios por contenedor |
| `k8s_deployment_desired` / `_available` | k8s_cluster | Deployment | Réplicas deseadas y disponibles | Infra: Réplicas deseadas y disponibles |

Los dashboards son `PharmaGo - Overview` (app, Golden Signals) y `PharmaGo - Infra` (nodo, pod y contenedor). Ambos están provisionados desde `k8s/configmaps/grafana-dashboard*.yaml`.

## Limitaciones de este cluster (verificadas)

Minikube con driver docker y cri-dockerd. Evidencia en `docs/evidencia/C12/05-kubelet-summary.txt` y `02-series-por-nodo.txt` (D39).

1. **No hay red por pod.** El kubelet no informa `network` para los pods en `/stats/summary`, así que no existe `k8s_pod_network_*`. Como cada microservicio tiene su propio nodo (C03), la red del nodo `minikube-m03` es la de users, la de `minikube-m04` la de pharmacy y la de `minikube-m02` la del gateway.
2. **La memoria por contenedor es solo `working_set`.** No existe `k8s_container_memory_limit_utilization`: el panel la calcula dividiendo por el límite que informa `k8s_cluster`. A nivel pod sí están `usage`, `rss`, `available` y el porcentaje contra el límite.
3. **El filesystem de nodo es el disco del host.** Los 5 nodos son contenedores sobre el mismo disco de WSL2: misma capacidad (1,08 TB) y casi el mismo uso. Para storage sirve `k8s_pod_filesystem_usage_bytes`, que sí es propio de cada pod y es lo que mide el desalojo por `ephemeral-storage`.
4. **CPU en núcleos.** `k8s_*_cpu_utilization_ratio` mide núcleos usados aunque el nombre diga *ratio*: el receiver lo documenta como uso en CPUs, no como porcentaje. Cada nodo tiene 2 CPU.

CPU, memoria y red de nodo **sí distinguen entre nodos**. Por ejemplo, el nodo `ops` usa unos 3,9 GB de working set y los de servicios unos 0,85 GB.
