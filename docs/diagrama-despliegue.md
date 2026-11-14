# Diagrama de despliegue

Cumple el pedido de la letra: *"Cada microservicio debe ejecutar en un pod independiente. Los microservicios no pueden ejecutar en mismos nodos físicos. Se debe implementar un diagrama de despliegue."*

Cluster Minikube de 5 nodos (decisión D01), namespace `pharmago`. El diagrama refleja el estado del repo al cerrar B3 (C10 a C12) y se completa en C23.

```mermaid
graph TB
    user(["Usuario<br/>http://127.0.0.1 con minikube tunnel"])

    subgraph N1["Nodo minikube · node-type=frontend · control-plane"]
        ingress["ingress-nginx<br/>Ingress pharmago-ingress"]
        ui["pharmago-ui<br/>Angular + nginx<br/>2 réplicas"]
    end

    subgraph N2["Nodo minikube-m02 · node-type=gateway"]
        gw["pharmago-api-gateway<br/>YARP + rate limit + circuit breaker<br/>2 réplicas"]
    end

    subgraph N3["Nodo minikube-m03 · node-type=users"]
        users["pharmago-users-service<br/>2 réplicas"]
    end

    subgraph N4["Nodo minikube-m04 · node-type=pharmacy"]
        pharmacy["pharmago-pharmacy-service<br/>2 réplicas"]
    end

    subgraph N5["Nodo minikube-m05 · node-type=ops"]
        db[("pharmago-db<br/>SQL Server 2019")]
        collector["otlp-collector<br/>OTLP :4317 · k8s_cluster · exporter prometheus :8889"]
        prometheus["Prometheus"]
        grafana["Grafana"]
        jaeger["Jaeger<br/>OTLP :4317 · UI :16686"]
        es[("Elasticsearch")]
        kibana["Kibana"]
    end

    subgraph DS["DaemonSets: un pod en cada uno de los 5 nodos"]
        fluentbit["Fluent Bit<br/>lee los logs de los contenedores"]
        otelagent["otel-agent<br/>kubeletstats del nodo"]
    end

    user --> ingress
    ingress -- "/" --> ui
    ingress -- "/api" --> gw
    gw -- "HTTP /api/..." --> users
    gw -- "HTTP /api/..." --> pharmacy
    users -- "EF Core" --> db
    pharmacy -- "EF Core" --> db

    gw -- "métricas y trazas OTLP" --> collector
    users -- "métricas y trazas OTLP" --> collector
    pharmacy -- "métricas y trazas OTLP" --> collector
    otelagent -- "métricas de nodo, pod y contenedor OTLP" --> collector
    collector -- "scrape :8889" --> prometheus
    prometheus --> grafana
    collector -- "trazas OTLP" --> jaeger

    fluentbit -- "logs" --> es
    es --> kibana
```

**Cómo leerlo.** Las flechas son el camino real de requests, métricas, trazas y logs. Los cuatro microservicios (UI, gateway, users y pharmacy) están cada uno en un nodo propio. Todo lo de operación comparte el nodo `ops`.

## Qué corre en cada nodo y por qué

| Nodo | `node-type` | Corre | Por qué |
|---|---|---|---|
| `minikube` (control-plane) | `frontend` | `pharmago-ui`, ingress-nginx | La UI es el único microservicio que el usuario pide directo. El addon ingress de Minikube corre en el nodo principal, así que la entrada y la UI quedan juntas y el camino a `/` no cruza nodos. |
| `minikube-m02` | `gateway` | `pharmago-api-gateway` | El gateway es el borde de la API: rate limit y, desde C07, circuit breaker. Si satura su nodo (por ejemplo, con el caos de requests), no le saca CPU a los servicios de atrás. |
| `minikube-m03` | `users` | `pharmago-users-service` | Un nodo por microservicio, como pide la letra. Un fallo o una sobrecarga de users no afecta a pharmacy. |
| `minikube-m04` | `pharmacy` | `pharmago-pharmacy-service` | Igual que users. |
| `minikube-m05` | `ops` | BD, Collector, Prometheus, Grafana, Jaeger, Elasticsearch y Kibana | No son microservicios de la app, así que la letra no les exige nodo propio. Juntarlos deja libres los otros 4 nodos y permite tener los volúmenes persistentes (BD, Prometheus, Grafana y Elasticsearch) en un único nodo fijo. La BD es una sola réplica: punto único de falla aceptado (D04). |
| Los 5 | — | Fluent Bit y otel-agent | Son DaemonSets: cada pod lee los logs y las métricas del kubelet **del nodo donde corre**, así que tiene que haber uno en cada nodo. No son microservicios. |

## Cómo se garantiza la separación

Cada Deployment de microservicio tiene dos reglas en `spec.template.spec.affinity`:

- **`nodeAffinity` por `node-type`** (`required`): manda cada microservicio a su nodo. Hace la colocación predecible. Sin ella, el scheduler podría repartir las 2 réplicas del primer microservicio en dos nodos y dejar al último sin nodo libre (`Pending`).
- **`podAntiAffinity`** (`required`, `topologyKey: kubernetes.io/hostname`): el pod no puede ir a un nodo donde ya haya pods con `app` igual a cualquiera de los **otros tres** microservicios. Es la garantía dura de la letra: aunque alguien etiquete mal un nodo o quite la `nodeAffinity`, Kubernetes deja el pod en `Pending` antes que juntar dos microservicios. No se excluye a sí mismo, porque las réplicas de un mismo microservicio pueden compartir nodo (D02).

Riesgo aceptado (D03): si se cae un nodo entero, se cae el microservicio que vive ahí, porque sus réplicas comparten ese nodo. Con 5 nodos no hay lugar para repartirlas sin romper la separación.

La comprobación automática es `Implementacion K8S/Codigo/k8s/verify/check-separacion.sh`. La evidencia está en `docs/evidencia/C03/`.

## Flujo de telemetría (desde B3)

- **Métricas:** las apps (cada 5 s) y los `otel-agent` de cada nodo (cada 10 s) mandan por OTLP al `otlp-collector`, que además lee la API de Kubernetes con `k8s_cluster`. Prometheus scrapea **solo** el exporter del Collector (`:8889`): no scrapea apps ni nodos (D30, D31, D32). Detalle en `docs/metricas.md`.
- **Trazas:** apps por OTLP al Collector y de ahí a Jaeger. Detalle en `docs/trazas.md`.
- **Logs:** consola JSON, Fluent Bit, Elasticsearch y Kibana. El `trace_id` en los logs llega en C14.
