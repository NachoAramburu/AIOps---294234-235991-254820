# Registro de decisiones

**Cómo se decide.** 1) Lo que dice la letra manda. 2) Después, lo que dice `AGENTS.md` y lo que trae el repo del curso. 3) Lo que no está en ninguno se investiga y se elige **lo más sencillo que cumpla**, citando la fuente oficial.

**Origen:** `Letra` · `AGENTS` (resumen del curso) · `Repo` (código de la cátedra) · `Lab` (laboratorio de anomalías) · `Investigación`.

**Estado de verificación de esta tabla (2026-11-08).** Las versiones de imágenes y paquetes se confirmaron contra Docker Hub, MCR, NuGet y npm. El código .NET marcado *probado* se compiló y ejecutó en local contra un backend falso. **Nada se ejecutó todavía sobre un cluster**: Docker y Minikube no estaban instalados en la máquina donde se armó el plan. Cada commit lo verifica con evidencia propia.

## Plataforma

| # | Decisión | Elegido | Por qué es lo más simple | Origen y fuente |
|---|---|---|---|---|
| D01 | Cluster | Minikube 5 nodos: `--driver=docker --container-runtime=docker --cni=calico --kubernetes-version=v1.33.13 --nodes 5 --cpus 2 --memory 4096`, creado por `k8s/cluster-up.sh` | Sale de sumar requests: el nodo `ops` pide ~3,5 GiB y los microservicios necesitan un nodo cada uno. **Medido en C02 (2026-11-10, PC de 16 GB, Docker con 15,5 GiB):** todo Running sin Pending ni OOMKilled, con 4096 alcanza. Uso real total ≈ 6,4 GiB (`docker stats`): `ops` 3,5 de 4 GiB (88 %), `frontend` 1,1 GiB, y gateway, users y pharmacy ~0,6 GiB cada uno. **Riesgo:** el nodo `ops` está cerca de su tope y los limits de sus pods suman 6,6 GiB; el kubelet ve toda la RAM de la VM como capacidad, así que no frena el scheduling. Si aparece OOM en `ops`: `minikube delete` y `MINIKUBE_MEMORY=4608 ./cluster-up.sh`. | AGENTS · [Minikube multi-nodo](https://minikube.sigs.k8s.io/docs/tutorials/multi_node/) · evidencia `docs/evidencia/C02/08-memoria.txt` |
| D02 | Separación de microservicios | `podAntiAffinity required` **solo entre microservicios distintos**, con `nodeAffinity` por `node-type` | La letra pide que *los microservicios* no compartan nodo, no que cada réplica tenga el suyo. **Difiere de AGENTS original** (label común `tier: backend`): con 2 réplicas requería 6 nodos, 7 en un rollout, y dejaba pods en Pending. | Letra · [Inter-pod anti-affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) |
| D03 | Riesgo aceptado | Las 2 réplicas de un microservicio comparten nodo; si cae el nodo entero, cae ese microservicio | Consecuencia directa de D02 con el hardware disponible. La letra pide curación ante errores en tiempo de ejecución, y eso se cubre. Se documenta en el informe. | Análisis propio |
| D04 | Base de datos | Una réplica, punto único de falla aceptado y documentado | Replicar SQL Server Express no es razonable para el alcance. | AGENTS |
| D05 | Acceso a la app | Ingress + `minikube tunnel`, `apiUrl` relativo | No depende de pods puntuales, a diferencia de `port-forward`. | AGENTS · [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) · [Acceso en Minikube](https://minikube.sigs.k8s.io/docs/handbook/accessing/) |
| D06 | Scripts | Solo bash (Git Bash en Windows); se eliminan los `.ps1` | Mantener dos copias divergentes es la causa del desfasaje actual entre `apply-k8s.sh` y `.ps1`. | Repo |
| D07 | Memoria en Windows | `.wslconfig` con `memory=18GB`, `processors=12` | Docker Desktop sobre WSL2 limita la RAM de la VM. | [Config de WSL](https://learn.microsoft.com/en-us/windows/wsl/wsl-config) |
| D08 | Seed de datos | `k8s/seed-db.sh`: espera las tablas de la migración, copia `seed-data.sql` al pod de BD y lo ejecuta con `sqlcmd`. La contraseña la toma de `SA_PASSWORD` **dentro** del contenedor (que ya viene de `secretKeyRef` a `db-secret`) vía `SQLCMDPASSWORD`, así no pasa por el host ni por la línea de comandos | Evita leer o decodificar el Secret fuera del cluster. El SQL ya es idempotente (`IF NOT EXISTS`). | Repo · [sqlcmd: variables de entorno](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility) |

## Alta disponibilidad y resiliencia

| # | Decisión | Elegido | Por qué es lo más simple | Origen y fuente |
|---|---|---|---|---|
| D10 | Salud | `/health/live` (proceso) y `/health/ready` (BD vía `AddDbContextCheck`) en users y pharmacy. *Probado*: sin BD, live 200 y ready 503 en 0,8 s. **C05 (2026-11-12):** implementado; `/health` se mantiene sin chequear la BD (mismo predicado que live) porque lo usan los probes actuales hasta C06. Medido: sin BD (`Connect Timeout=2`), ready 503 en ~3,9 s; en el cluster, el primer ready de pharmacy tardó 3,5 s (arranque en frío de EF) y después 10 a 90 ms. Para C06: el timeout de 2 s del readiness puede fallar en el primer chequeo tras arrancar, y lo cubre el failureThreshold | Paquete oficial de ASP.NET Core. | AGENTS · [Health checks](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks?view=aspnetcore-6.0) |
| D11 | Ready del gateway | `/health/ready` sin chequeo de BD | **Difiere de AGENTS**, que pedía BD también en el gateway. El gateway no tiene BD; agregar el chequeo sumaría una dependencia y haría que una caída de BD saque del aire el borde (rate limit incluido). La letra no lo pide. | Análisis propio |
| D12 | Probes | startup `/health/live` p=2 s ft=60; readiness `/health/ready` p=2 s ft=2 t=2 s; liveness `/health/live` p=3 s ft=2 t=2 s | Rangos pedidos en AGENTS. La letra apunta a MTTR de pocos segundos. | AGENTS · [Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) |
| D13 | Patrón ante fallas reiteradas | Polly 7.2.4 dentro del `ForwarderHttpClientFactory` de YARP: retry (solo GET/HEAD, 2 reintentos, exponencial + jitter), breaker por cluster (50 % en 10 s, mínimo 8, abierto 5 s), timeout 3 s por intento. *Probado*: Closed → Open → Half-Open → Closed, 503 con `Retry-After` | Es el único salto HTTP real. Polly 7 ya está en el ecosistema del repo. Los POST no se reintentan para no duplicar compras. | AGENTS · [Polly 7.2.4](https://github.com/App-vNext/Polly/tree/7.2.4) · [YARP HttpClient](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/yarp/http-client-config) · [Circuit Breaker](https://learn.microsoft.com/en-us/azure/architecture/patterns/circuit-breaker) · [Retry](https://learn.microsoft.com/en-us/azure/architecture/patterns/retry) |
| D14 | Health checks de YARP | **Apagados**, como vienen en el repo | **Difiere de AGENTS.** Cada cluster tiene un único destino (el Service), y Kubernetes ya saca los pods no listos. *Probado*: con checks activos, tras recuperarse el backend el gateway siguió en 503 más de 40 s. Empeoraba el MTTR. | Repo · [YARP health checks](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/yarp/dests-health-checks) |
| D15 | Rate limiting | El de `AspNetCoreRateLimit` que ya está, con whitelist exacta de `/health/live` y `/health/ready`. *Probado*: 150 probes sin 429, y 429 al superar 100/min | Ya existe. Sin el whitelist, los probes del gateway agotaban el límite de 1000/h en ~33 min. | Repo · [AspNetCoreRateLimit](https://github.com/stefanprodan/AspNetCoreRateLimit/wiki/IpRateLimitMiddleware) |
| D16 | BD transitoria | `EnableRetryOnFailure(3, 2 s)` y reintentos de `Migrate()` al arrancar | Mecanismos nativos de EF Core. El repo no usa transacciones manuales, así que es compatible. | AGENTS · [Resiliencia EF Core](https://learn.microsoft.com/en-us/ef/core/miscellaneous/connection-resiliency) |
| D17 | Cadena de conexión | `SA_PASSWORD` por `secretKeyRef` y expansión `$(SA_PASSWORD)` | No agrega secretos nuevos ni duplica el valor. | AGENTS · [Variables interdependientes](https://kubernetes.io/docs/tasks/inject-data-application/define-interdependent-environment-variables/) |

## Despliegue seguro

| # | Decisión | Elegido | Por qué es lo más simple | Origen y fuente |
|---|---|---|---|---|
| D20 | Técnica | RollingUpdate `maxUnavailable: 0`, `maxSurge: 1`, `minReadySeconds: 5`, `preStop sleep 5` | Nativa de Kubernetes, sin infraestructura extra. | AGENTS · [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) · [Terminación de pods](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) |
| D21 | Imágenes | `pharmago-*:<sha corto>`, placeholder `IMAGE_TAG` en manifiestos | Trazabilidad entre lo desplegado y el commit. | AGENTS |
| D22 | Versiones de terceros | `prom/prometheus:v2.53.4`, `otel/opentelemetry-collector-contrib:0.111.0`, `jaegertracing/all-in-one:1.60.0`, `busybox:1.36`, `mcr.microsoft.com/mssql/server:2019-CU32-ubuntu-20.04` | Tags confirmados. Grafana, Elasticsearch, Kibana y Fluent Bit quedan en la versión del repo. | AGENTS |

## Telemetría

| # | Decisión | Elegido | Por qué es lo más simple | Origen y fuente |
|---|---|---|---|---|
| D30 | Recolección de métricas | **Todo por OTLP al Collector**, exporter `prometheus` :8889. Prometheus solo scrapea el Collector | **Difiere del default de AGENTS** (scrape directo). La letra pide OTLP hacia Prometheus. Se mantiene el exporter que ya trae el repo de la cátedra. | Letra · Repo · [OTLP](https://opentelemetry.io/docs/specs/otlp/) · [Exporter Prometheus](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/v0.111.0/exporter/prometheusexporter) |
| D31 | Métricas de pod, contenedor y nodo | DaemonSet `otel-agent` con receiver `kubeletstats` | Un solo receiver cubre CPU, memoria, storage y red en los dos niveles, y reemplaza a cAdvisor y node-exporter (que no van por OTLP). | Letra · [kubeletstats](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/v0.111.0/receiver/kubeletstatsreceiver) |
| D32 | Estado de Kubernetes | Receiver `k8s_cluster` en el Collector central | **Difiere de AGENTS** (kube-state-metrics, que no va por OTLP). Además es un Deployment menos. | Letra · [k8s_cluster](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/v0.111.0/receiver/k8sclusterreceiver) |
| D33 | SDK .NET | OpenTelemetry 1.8.1 (`SqlClient` 1.8.0-beta.1) en proyecto nuevo `PharmaGo.Telemetry`. *Probado*: compila en net6.0 y 291/291 tests | Tiene binarios net6.0 confirmados y es la misma línea que ya usa el repo. El proyecto aparte evita romper el monolito (NU1605). | AGENTS · [OTel .NET](https://opentelemetry.io/docs/languages/dotnet/) |
| D34 | Trazas | Jaeger all-in-one en memoria. *Probado*: `traceparent` llega al servicio a través de YARP | Un solo contenedor con OTLP nativo. | AGENTS · [Jaeger](https://www.jaegertracing.io/docs/1.60/getting-started/) · [W3C Trace Context](https://www.w3.org/TR/trace-context/) |
| D35 | Logs | Formatter JSON de consola, `trace_id`/`span_id` en el scope, Fluent Bit a Elasticsearch, Kibana. *Probado*: 291 líneas, 100 % JSON | Es lo que trae el repo y lo que nombra la letra. | Letra · Repo · [Console formatter](https://learn.microsoft.com/en-us/dotnet/core/extensions/console-log-formatter) · [Fluent Bit ES](https://docs.fluentbit.io/manual/pipeline/outputs/elasticsearch) |
| D36 | Alertas | 10 reglas por archivo en `/etc/grafana/provisioning/alerting/` | Provisioning nativo de Grafana 10.4 (versión del repo). | Letra · [File provisioning](https://grafana.com/docs/grafana/v10.4/alerting/set-up/provision-alerting-resources/file-provisioning/) · [Golden Signals](https://sre.google/sre-book/monitoring-distributed-systems/) |

## Anomalías, caos, incidentes y pipeline

| # | Decisión | Elegido | Por qué es lo más simple | Origen y fuente |
|---|---|---|---|---|
| D40 | Protocolo de anomalías | El del laboratorio: entrenar sin etiquetas sobre todas las ventanas. *Probado*: IF F1 = 0,578; OCSVM F1 = 0,439. **Confirmado en C15** con `anomaly-detection/requirements.txt`, idéntico en dos corridas | **Difiere de AGENTS**, que ajustaba solo con datos normales. La letra pide técnicas no supervisadas. | Letra · Lab · [IsolationForest](https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.IsolationForest.html) · [OneClassSVM](https://scikit-learn.org/stable/modules/generated/sklearn.svm.OneClassSVM.html) |
| D41 | Caos de red | `NetworkPolicy` deny-all con Calico | Declarativa, reversible con un `delete`. | AGENTS · [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/) · [Minikube + Calico](https://minikube.sigs.k8s.io/docs/handbook/network_policy/) |
| D42 | Caos de desconexión | `kubectl scale --replicas=0` del componente, restaurado por `trap` | Corta de verdad. Cambiar el selector del Service deja vivas las conexiones ya abiertas. | Análisis propio |
| D43 | Caos de memoria | Variable de shell que retiene N MB (`dd … | tr`) dentro del contenedor | No requiere imágenes ni manifiestos nuevos, y consume memoria real del cgroup. | Análisis propio |
| D44 | Caos de storage | `dd` a `/tmp` + `limits.ephemeral-storage: 512Mi` | El kubelet desaloja el pod si se excede y se ve la autocuración. | [Recursos de contenedores](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) |
| D45 | Principios | Steady state, hipótesis falsable, blast radius acotado | Vienen del curso. | AGENTS · [Principles of Chaos](https://principlesofchaos.org/) |
| D46 | Incidentes | Roles IC/Ops/Comms, postmortem blameless | Vienen del curso. | AGENTS · [Managing incidents](https://sre.google/sre-book/managing-incidents/) · [Postmortem culture](https://sre.google/sre-book/postmortem-culture/) |
| D47 | CI/CD | GitHub Actions: build, tests, Angular, imágenes con SHA, GHCR en `main`. El deploy es local porque el runner no llega a Minikube | Lo pide la letra. | Letra · [GitHub Actions](https://docs.github.com/en/actions) |
| D48 | Tablero | GitHub Projects, una tarjeta por commit | Lo pide la letra. | Letra · [GitHub Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects) |
| D49 | BDD | `cypress@13.17.0`, `@badeball/cypress-cucumber-preprocessor@20.1.2`, `@bahmutov/cypress-esbuild-preprocessor@2.2.4`, `esbuild@0.21.5`, en carpeta `e2e/` separada | Compatibilidad declarada por el paquete. No toca las dependencias de Angular 14. | Letra · [Preprocessor](https://github.com/badeball/cypress-cucumber-preprocessor) |
| D50 | Elasticsearch | Se mantiene ES + Kibana, no Loki | Es lo que nombra la letra y lo que trae el repo. **C02 confirmó que entra:** Elasticsearch usa 915 MiB y Kibana 813 MiB (`kubectl top pods`), Fluent Bit no tiene errores de conexión y el índice `pharmago-logs-2026.11.10` recibió ~3000 documentos en los primeros minutos. | Letra · Repo · evidencia `docs/evidencia/C02/08-memoria.txt` y `09-fluent-bit.txt` |
| D51 | `docker-compose.yml` | No se mantiene | Solo Kubernetes. | AGENTS |
| D52 | Cuaderno para el dataset de los docentes | `deteccion_dataset_docentes.ipynb` genérico: `DATA_PATH`, `FEATURES` y `LABEL_COL` (opcional, solo para evaluar) en una celda o por variable de entorno; mismos hiperparámetros que D40; si el CSV no existe, avisa y termina sin error | El formato del dataset todavía no se conoce. Variables de entorno permiten correrlo con `nbconvert` sin editar el cuaderno, y que termine sin error permite ejecutarlo de punta a punta (por ejemplo en CI) mientras no llegue. | Letra · Lab · [nbconvert: ejecutar cuadernos](https://nbconvert.readthedocs.io/en/latest/execute_api.html) |

## Puntos abiertos con los docentes

La letra se contradice o está incompleta. Mientras no haya respuesta, se aplica lo indicado.

| Punto | Qué se hace mientras tanto |
|---|---|
| Puntaje "máximo 0, mínimo 40" | Se apunta a los 40 de la rúbrica. |
| Integrantes "hasta 3" y "hasta 2" | Equipo de 3, como dicen las condiciones. Confirmar antes de subir a Gestión. |
| Script de la defensa: el de los docentes o el propio | Se preparan ambos. |
| Lista vacía tras "tales como:" | Se cubren las tecnologías nombradas. |
| Datasets de anomalías | `C15` usa el del laboratorio y deja el cuaderno listo para el CSV de los docentes. |
| Si un nodo de Minikube cuenta como "nodo físico" | Se asume que sí. Se declara en el informe. |
