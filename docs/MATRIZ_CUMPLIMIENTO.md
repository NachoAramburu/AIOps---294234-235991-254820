# Matriz de cumplimiento

Recorre `docs/letra-obligatorio.md` frase por frase y apunta a la evidencia de cada requisito. Cada ruta de esta tabla se comprobó con `docs/evidencia/C24/check_matriz.py`, que falla si alguna no existe (`docs/evidencia/C24/01-check-matriz.txt`).

`CODE` = `Implementacion K8S/Codigo`. Estado al 2026-11-15, rama `team/obligatorio`.

**Estados:** `CUMPLE`: hecho y con evidencia ejecutada. `CUMPLE (defensa)`: listo; la letra dice que se completa en la defensa. `PARCIAL`: hecho en parte; se explica qué falta. `NO CUMPLE`: no hecho.

## 1. Rúbrica

| # | Requisito de la letra | Estado | Commit | Evidencia |
|---|---|---|---|---|
| 1.1 | "El sistema debe correr sobre Kubernetes" | CUMPLE | C02, C23 | `docs/evidencia/C02/06-pods.txt`, `docs/evidencia/C23/01-desde-cero.txt` (cluster de 5 nodos desde cero con `full-up.sh`) |
| 1.2 | "Cada microservicio debe ejecutar en un pod independiente" | CUMPLE | C02, C03 | `docs/evidencia/C23/02-pods-wide.txt` (gateway, users, pharmacy y UI en pods propios, 2 réplicas cada uno) |
| 1.3 | "Los microservicios no pueden ejecutar en mismos nodos físicos" | CUMPLE | C03 | `CODE/k8s/verify/check-separacion.sh`, `docs/evidencia/C03/04-check-separacion.txt`, `docs/evidencia/C03/05-prueba-negativa.txt`. Supuesto declarado: un nodo de Minikube cuenta como nodo físico |
| 1.4 | "Se debe implementar un diagrama de despliegue de los componentes principales" | CUMPLE | C03, C23 | `docs/diagrama-despliegue.md`, comparado contra el cluster en `docs/evidencia/C23/02-pods-wide.txt` |
| 2.1 | "Los microservicios deben curarse automáticamente [...] volver al mismo estado [READY] luego de excepciones" | CUMPLE | C05, C06, C09 | `docs/mttr.md`, `docs/evidencia/C09/03-cluster-mttr.txt` (borrado de pod y crash del proceso en los 4 microservicios: 0 errores, de 3,0 a 8,8 s) |
| 2.2 | "Resiliente a ataques que inciten fallas reiteradas. Se debe implementar algún patrón [...]" | CUMPLE | C07 | `docs/resiliencia.md`, `CODE/Backend/PharmaGo.ApiGateway/Resilience/ResilientForwarderHttpClientFactory.cs`, `docs/evidencia/C07/02-cluster-circuit-breaker.txt` (circuit breaker, retry con jitter, timeout) y rate limit con 429 (`docs/evidencia/C05/03-gateway-rate-limit.txt`) |
| 3.1 | "Reemplazar sus componentes garantizando 100 % de disponibilidad" | CUMPLE | C08, C09 | `CODE/k8s/verify/test-rollout.sh`, `docs/evidencia/C09/02-cluster-test-rollout.txt` (145 requests en v1 → v2 → rollback, 0 no-2xx), `CODE/k8s/deploy.sh`, `CODE/k8s/rollback.sh` |
| 3.2 | "Se necesita documentar y explicar la técnica elegida" | CUMPLE | C09 | `docs/despliegue-seguro.md` |
| 4.1 | "Logs estructurados en JSON" | CUMPLE | C14 | `docs/logs.md`, `docs/evidencia/C14/03-logs-json-por-servicio.txt` |
| 4.2 | "Trazas de acuerdo a OTLP" | CUMPLE | C11 | `docs/trazas.md`, `docs/evidencia/C11/03-traza-login-y-drug.txt`, `docs/evidencia/C11/05-jaeger-traza-login.png` |
| 4.3 | "Métricas a nivel de pod/contenedor y nodo físico (CPU, memoria, storage y red)" | CUMPLE | C12 | `docs/metricas.md`, `docs/evidencia/C12/02-series-por-nodo.txt`, `docs/evidencia/C12/08-grafana-infra-nodos.png`. Límites del cluster (sin red por pod) en D39 |
| 4.4 | "Las métricas deben recolectarse con OTLP hacia Prometheus" | CUMPLE | C10, C12 | `CODE/k8s/configmaps/prometheus-config.yaml` (único target: el Collector), `docs/evidencia/C10/05-prometheus-targets.txt`, `docs/evidencia/C12/03-prometheus-targets.txt` |
| 4.5 | "Visualización con Grafana" | CUMPLE | C10, C12 | `CODE/k8s/configmaps/grafana-dashboards.yaml`, `CODE/k8s/configmaps/grafana-dashboard-infra.yaml`, `docs/evidencia/C10/07-grafana-overview.txt`, `docs/evidencia/C12/07-grafana-api.txt` |
| 4.6 | "Los logs deben poder consultarse en [...] Kibana con ElasticSearch" | CUMPLE | C02, C14 | `CODE/k8s/setup-kibana.sh`, `docs/evidencia/C14/05-trace-id-jaeger-en-elasticsearch.txt` |
| 4.7 | "Por lo menos 5 alertas en Grafana para detección de anomalías de las métricas" | CUMPLE | C13, C18 | `CODE/k8s/configmaps/grafana-alerting.yaml` (10 reglas), `docs/alertas.md`, `docs/evidencia/C13/01-reglas-provisionadas.txt`, disparos medidos en `CODE/chaos-engineering/EXPERIMENTOS.md` |
| 5.1 | "Implementarse los algoritmos IsolationForest y Support Vector Machine con función núcleo RBF" | CUMPLE | C15 | `anomaly-detection/laboratorio_comparacion_detectores.ipynb`, `anomaly-detection/README.md`, `docs/evidencia/C15/02-laboratorio.txt`, `docs/evidencia/C15/05-reproducibilidad.txt` |
| 5.2 | "[...] para datasets que serán provistos por los docentes" | CUMPLE (defensa) | C15 | `anomaly-detection/deteccion_dataset_docentes.ipynb`, probado con un CSV de prueba en `docs/evidencia/C15/04-docentes-con-dataset-lab.txt`. El dataset se entrega el día de la defensa; ese día se corre con `DATA_PATH` (README, "Con el dataset de los docentes") |
| 6.1 | "Se debe realizar un plan de mitigación de incidentes operacionales" | CUMPLE | C19, C20 | `docs/plan-incidentes.md`, `docs/playbooks/` (8 playbooks), `docs/plantillas/registro-incidente.md`, `docs/plantillas/postmortem.md`, `docs/incidentes/ejemplo-postmortem.md`, `docs/evidencia/C20/03-check-plan-incidentes.txt` |
| 7.1 | Caos: "inyección de requests" | CUMPLE | C16, C18 | `CODE/chaos-engineering/load-requests.sh`, `docs/evidencia/C16/07-load-requests.txt`, `docs/evidencia/C18/01-requests.txt` |
| 7.2 | Caos: "sobrecarga de CPU" | CUMPLE | C16, C18 | `CODE/chaos-engineering/cpu-spike.sh`, `docs/evidencia/C16/02-cpu-spike.txt`, `docs/evidencia/C18/02-cpu.txt` |
| 7.3 | Caos: "sobrecarga de memoria" | CUMPLE | C16, C18 | `CODE/chaos-engineering/ram-spike.sh`, `docs/evidencia/C16/03-ram-spike-150.txt`, `docs/evidencia/C18/03b-memoria.txt` |
| 7.4 | Caos: "sobrecarga de storage" | CUMPLE | C16, C18 | `CODE/chaos-engineering/volume-spike.sh`, `docs/evidencia/C16/06-volume-spike-600-desalojo.txt`, `docs/evidencia/C18/04c-storage-400.txt` |
| 7.5 | Caos: "interrupción de tráfico de red" | CUMPLE | C17, C18 | `CODE/chaos-engineering/network-chaos.sh`, `docs/evidencia/C17/02-network-chaos-users.txt`, `docs/evidencia/C18/05b-red.txt` |
| 7.6 | Caos: "desconexión de componentes internos de la aplicación" | CUMPLE | C17, C18 | `CODE/chaos-engineering/disconnect.sh`, `docs/evidencia/C17/04-disconnect-users.txt`, `docs/evidencia/C18/06-desconexion.txt` |
| 8.1 | Defensa: "ejecutar el script de caos implementado, mostrar sus efectos mediante telemetría y la respuesta del sistema" | CUMPLE | C18, C23 | `docs/runbook-defensa.md`, `CODE/k8s/full-up.sh`, ensayo técnico de los 6 tipos en `docs/evidencia/C23/03-ensayo-red.txt` (y los otros cinco `03-ensayo-*.txt`) |
| 8.2 | Defensa: "explicar cómo los mecanismos implementados garantizan el comportamiento observado" | CUMPLE | C23 | `docs/runbook-defensa.md` (sección 4: matriz falla → mecanismo → alerta → panel → mitigación → por qué) |

## 2. Objetivo y actividades

| # | Requisito de la letra | Estado | Commit | Evidencia |
|---|---|---|---|---|
| 9.1 | "Requerimientos no funcionales para [...] disponibilidad, desplegabilidad y mantenibilidad" | CUMPLE | C06, C08, C21 | `docs/mttr.md` (disponibilidad), `docs/despliegue-seguro.md` (desplegabilidad), `docs/ci-cd.md` y `docs/DECISIONES.md` (mantenibilidad) |
| 9.2 | "Scripts que permitan simular incidentes operacionales" | CUMPLE | C16, C17 | `CODE/chaos-engineering/README.md`, `CODE/chaos-engineering/run-all.sh` |
| 9.3 | "Técnicas de aprendizaje automático para detectar anomalías en datasets de datos operacionales" | CUMPLE | C15 | `anomaly-detection/README.md` |
| 9.4 | War room con "un script de ingeniería de caos provisto por los docentes" y "presentar hallazgos" | CUMPLE (defensa) | C19, C23 | `docs/plan-incidentes.md` (sección 7: falla desconocida), `docs/runbook-defensa.md` (sección 5). El ensayo con los 3 integrantes en sus roles queda en `docs/evidencia/C23/04-ensayo-equipo.md` |
| 10.1 | "Reducir el MTTR [...] idealmente al orden de pocos segundos" | CUMPLE | C06, C09 | `docs/mttr.md` (3,0 a 8,8 s sin errores visibles) |
| 10.2 | "Técnicas de despliegue/reemplazo de componentes seguro" | CUMPLE | C08 | `docs/despliegue-seguro.md` |
| 10.3 | "Diseñar, capturar y visualizar métricas de aplicación e infraestructura" | CUMPLE | C10, C12 | `docs/metricas.md` |
| 10.4 | "Logs estructurados y trazas con propagación de contexto de acuerdo a OpenTelemetry" | CUMPLE | C11, C14 | `docs/trazas.md` (W3C `traceparent` a través de YARP), `docs/logs.md` (`trace_id` en cada log) |
| 10.5 | "Implementar un plan de mitigación de incidentes operacionales" | CUMPLE | C19, C20 | `docs/plan-incidentes.md` |
| 10.6 | "Entrenar dos técnicas no supervisadas de detección de anomalías" | CUMPLE | C15 | `anomaly-detection/README.md` (sección "Protocolo: por qué es no supervisado") |
| 10.7 | "Diseñar e implementar experimentos de ingeniería del caos" | CUMPLE | C18 | `CODE/chaos-engineering/EXPERIMENTOS.md`, `CODE/chaos-engineering/steady-state.sh` |
| 10.8 | "Reflexionar sobre el impacto de las prácticas de ingeniería de software ágil" | CUMPLE | C24 | `docs/informe/informe.md`, sección 10 |

## 3. Tecnología, herramientas y entrega

| # | Requisito de la letra | Estado | Commit | Evidencia |
|---|---|---|---|---|
| 11.1 | "Todos los productos de trabajo deben estar versionados en GitHub" | CUMPLE | C01 a C24 | Fork `NachoAramburu/AIOps---294234-235991-254820`, rama `team/obligatorio` (se mergea a `main` en la entrega) |
| 11.2 | GitHub: "tableros" | PARCIAL | C01 | `docs/tablero.md` tiene columnas, roles y tarjetas, pero la URL del Project de GitHub sigue `PENDIENTE`. NO VERIFICADO desde esta PC si el Project existe |
| 11.3 | GitHub: "pipelines CI/CD" | CUMPLE | C21 | `.github/workflows/ci.yml`, `docs/evidencia/C21/03-corrida-github.txt` (8 jobs en verde) |
| 11.4 | "BDD: Cypress + Cucumber" | CUMPLE | C22 | `CODE/e2e/cypress/e2e/login.feature`, `CODE/e2e/cypress/e2e/salud.feature`, `docs/bdd.md`, `docs/evidencia/C22/01-smoke-local.txt`, `docs/evidencia/C22/02-e2e-cluster.txt` |
| 11.5 | "Desarrollo: .NET / Angular" | CUMPLE | C02 | Código existente sin cambios de negocio: `CODE/Backend/`, `CODE/Frontend/` |
| 11.6 | "Grafana, OTLP y Prometheus" | CUMPLE | C10 a C13 | `docs/metricas.md`, `docs/alertas.md` |
| 11.7 | "Técnicas y herramientas sobre el pipeline que permitan mejorar el valor entregado" (extensiones) | CUMPLE | C21, C22 | `docs/ci-cd.md`: tests, build, validación de manifiestos, BDD e imágenes con tag de SHA en cada push |
| 12.1 | "El informe final debe tener una sección para cada elemento de la rúbrica, explicando los desafíos enfrentados y los resultados obtenidos" | CUMPLE | C24 | `docs/informe/informe.md`, `docs/pdf/informe.pdf` |
| 12.2 | "La extensión no puede ser mayor a 10 páginas" | CUMPLE | C24 | `docs/evidencia/C24/02-paginas-informe.txt` |
| 13.1 | "Un único archivo en formato zip o rar", "máximo de 40mb" | CUMPLE | C24 | `scripts/package-entrega.sh`, `docs/evidencia/C24/03-zip.txt` |
| 13.2 | "Los documentos de texto deben ser pdf, y deben ir dentro del zip" | CUMPLE | C24 | `scripts/build-pdfs.py`, `docs/pdf/`, `docs/evidencia/C24/03-zip.txt` |
| 13.3 | "Subir el trabajo a Gestión antes de la hora indicada" (16/11/2026, 21:00) | PARCIAL | — | Lo hace el equipo a mano después de mergear a `main` (ver "Pendiente del equipo") |

## 4. Uso de IA generativa

| # | Requisito de la letra | Estado | Commit | Evidencia |
|---|---|---|---|---|
| 14.1 | "Indicar la/las herramientas utilizadas y el contexto de uso" | CUMPLE | C01 a C24 | `docs/USO_IA.md` (una fila por commit o bloque), resumen en `docs/informe/informe.md`, sección 11 |
| 14.2 | "Todo contenido producido por IAG debe ser revisado y verificado" | PARCIAL | C01 a C24 | Cada commit se revisa antes de commitear (paso `revisado`). Falta firmar la fila "Plan" del 2026-11-08 en `docs/USO_IA.md`, que sigue `PENDIENTE` |
| 14.3 | "Seguir las pautas de los docentes" sobre IA | NO VERIFICADO | — | Las pautas específicas de la cátedra no estaban en el material analizado (`docs/DECISIONES.md`, "Puntos abiertos") |

## Resumen

- **NO CUMPLE:** ninguna fila.
- **PARCIAL (3):** 11.2 tablero (falta la URL del Project de GitHub), 13.3 subida a Gestión (es el último paso, a mano) y 14.2 revisión de la fila "Plan" de `docs/USO_IA.md`.
- **CUMPLE (defensa) (2):** 5.2 dataset de los docentes y 9.4 war room con el script de los docentes.
- **NO VERIFICADO (1):** 14.3 pautas de IA de la cátedra.

## Pendiente del equipo antes de entregar

1. Crear el Project de GitHub y poner su URL en `docs/tablero.md`, o declarar en la defensa que el tablero se llevó en ese archivo.
2. Firmar la fila "Plan" de `docs/USO_IA.md`.
3. Mergear `team/obligatorio` a `main`, confirmar el pipeline en verde, regenerar el zip con `scripts/package-entrega.sh` y subirlo a Gestión antes de las 21:00 del 16/11.
