# Runbook de la defensa

La letra pide para la defensa: *"Se debe ejecutar el script de caos implementado, mostrar sus efectos mediante telemetría y la respuesta del sistema. Se deben explicar cómo los mecanismos implementados en el obligatorio garantizan el comportamiento observado."*

Este documento dice cómo dejar todo andando desde cero, qué abre cada uno, qué pasa con cada falla y por qué, y cómo diagnosticar una falla que no conocemos. Complementa a `docs/plan-incidentes.md` (roles, severidades y comunicación) y a `docs/playbooks/` (un playbook por tipo de falla). Los valores medidos salen de `Implementacion K8S/Codigo/chaos-engineering/EXPERIMENTOS.md` (C18) y del ensayo de C23 (`docs/evidencia/C23/`).

Roles (sorteados en C19): **IC Martin Roux**, **Ops Ignacio Aramburu**, **Comms Franco**.

## 1. Arranque desde cero

Requisitos de la PC: Docker Desktop corriendo, minikube, kubectl y Git Bash (`Implementacion K8S/Codigo/k8s/README-k8s.md`). Memoria: el cluster usa 5 nodos de 4 GiB; en una PC de 16 GB, `.wslconfig` con `memory=10GB` o menos.

Un solo comando, en Git Bash:

```bash
cd "Implementacion K8S/Codigo/k8s"
./full-up.sh
```

Cuando el script muestre `=== ... minikube tunnel ===`, abrir **PowerShell como administrador** y dejar corriendo:

```powershell
minikube tunnel
```

`full-up.sh` espera al tunnel, corre `steady-state.sh` (hasta 6 intentos, porque las alertas del arranque tardan en volver a Normal) y `check-separacion.sh`, y al final muestra cuánto tardó cada paso. Después, en otra terminal de Git Bash:

```bash
./port-forward.sh
```

Tiempos medidos en la PC de Martin (16 GB, imágenes ya en la caché de Docker), `docs/evidencia/C23/01-desde-cero.txt`:

| Paso | Qué hace | Tiempo |
|---|---|---|
| `minikube delete` | Borra el cluster anterior | 2 s |
| `cluster-up.sh` | Crea los 5 nodos, Calico, ingress, metrics-server y etiquetas `node-type` | 6 min 50 s |
| `build-images.sh` | Compila (desde caché) y carga las 4 imágenes en los 5 nodos | 2 min 6 s |
| `apply-k8s.sh` | Namespace, Secret, BD, observabilidad, app, PDB e Ingress | 4 min 37 s |
| Rollout de la app | Espera los 4 microservicios 2/2 y la BD 1/1 | 46 s |
| `seed-db.sh` | Roles, usuarios y datos iniciales | 4 s |
| `setup-kibana.sh` | Data view `pharmago-logs-*` | 1 min 21 s |
| `steady-state.sh` | Steady state OK al primer intento | 27 s |
| `check-separacion.sh` | Ningún nodo con dos microservicios | 1 s |
| **Total de `full-up.sh`** | | **16 min 13 s** |

Si las imágenes no están en la caché de Docker (PC nueva), `build-images.sh` compila los 3 servicios .NET y el frontend: sumar unos 10 a 15 min. En una PC de 16 GB conviene compilar antes de levantar el cluster (ver sección 6).

## 2. Checklist 30 minutos antes

| # | Qué | Cómo | Quién |
|---|---|---|---|
| 1 | Docker Desktop corriendo y con memoria | `docker info --format '{{.MemTotal}}'` | Ops |
| 2 | Cluster arriba, 5 nodos Ready | `kubectl get nodes` | Ops |
| 3 | Todos los pods Running y 1/1 | `kubectl get pods -n pharmago -o wide` | Ops |
| 4 | Separación de microservicios | `bash k8s/verify/check-separacion.sh` (exit 0) | Ops |
| 5 | `minikube tunnel` abierto y la app responde | Abrir `http://127.0.0.1/` e iniciar sesión con un usuario del seed | IC |
| 6 | Port-forwards de las herramientas | `./port-forward.sh`; abrir Grafana, Prometheus, Kibana y Jaeger | Ops |
| 7 | Steady state | `bash chaos-engineering/steady-state.sh` (exit 0) | Ops |
| 8 | Alertas cargadas y en Normal | Grafana → Alerting → Alert rules: carpeta PharmaGo, 10 reglas, ninguna en Firing | IC |
| 9 | Dashboards con datos | "PharmaGo - Overview" y "PharmaGo - Infra" con series de los últimos 5 min | IC |
| 10 | Logs llegan a Kibana | Discover, data view "PharmaGo logs", últimos 15 min con documentos | Ops |
| 11 | Plantilla de registro abierta y reloj UTC | `docs/plantillas/registro-incidente.md` copiada para el día | Comms |
| 12 | Playbooks y este runbook a mano | `docs/playbooks/`, sección 4 de este documento | IC |
| 13 | Tráfico de fondo para ver el breaker | Dejar listo el loop de la sección 5 (paso 0) | Ops |

Si algo falla, ver la sección 6.

## 3. Qué abre cada rol

| Herramienta | URL | Credenciales | Quién la mira |
|---|---|---|---|
| App (UI) | `http://127.0.0.1/` (con `minikube tunnel`) | Usuarios del seed (`Backend/seed-data.sql`) | IC, para mostrar que la app sigue andando |
| API | `http://127.0.0.1/api/drug`, `/api/roles` | Sin login | Ops (curl) |
| Grafana | `http://127.0.0.1:3000` | admin / admin (`README-k8s.md`) | IC: "PharmaGo - Overview" y Alerting. Ops: "PharmaGo - Infra" |
| Prometheus | `http://127.0.0.1:9090` | Sin login | Ops, para queries puntuales (`pharmago_circuit_breaker_state`) |
| Jaeger | `http://127.0.0.1:16686` | Sin login | Ops, ante latencia: qué tramo es el lento |
| Kibana | `http://127.0.0.1:5601` | Sin login | Ops, data view "PharmaGo logs" (`pharmago-logs-*`), buscar por `trace_id` o `circuit_breaker` |
| Terminal 1 | `kubectl get pods -n pharmago -o wide -w` | | Ops |
| Terminal 2 | Libre para diagnóstico y mitigación | | Ops |
| Registro | `docs/plantillas/registro-incidente.md` | | Comms |

Grafana, Prometheus, Jaeger y Kibana usan `port-forward.sh`. La app no: entra por el Ingress, como pide la letra.

## 4. Matriz por falla

Tiempos desde que empieza la falla, medidos en C18 (`EXPERIMENTOS.md`) salvo que diga "ensayo C23". "Firing" es la alerta de Grafana; "Pending" significa que la condición se cumple pero todavía no pasó la ventana.

| Falla | Script | Mecanismo que actúa | Alerta (tiempo medido) | Panel | Mitigación | Por qué pasa lo que se ve |
|---|---|---|---|---|---|---|
| Inyección de requests | `load-requests.sh 300 20` | Rate limit en el gateway (AspNetCoreRateLimit): 10/min en login y 100/min en el resto, por IP, endpoint y réplica | `pg-429`: Pending 17 s, Firing 50 s, Normal 70 s después | Overview → "Rate Limit Errors (429) por Endpoint" | Ninguna: es la protección funcionando. Si bloquea usuarios legítimos, identificar la IP en Kibana | El límite es por endpoint: la ráfaga a `/api/login` recibe 429 (280 de 300) y `/api/drug` sigue con 0 errores. El 429 no cuenta para el breaker |
| Sobrecarga de CPU | `cpu-spike.sh <deploy> 120 4` | Límite de CPU del contenedor (500m): el kernel lo limita y no le roba CPU al nodo; la otra réplica atiende | `pg-cpu`: Pending 33 s, Firing 70 s, Normal 30 s después | Infra → "CPU del contenedor contra su límite" y "CPU por pod (núcleos)" | Esperar a que termine. Si no termina: `kubectl rollout restart deploy/<nombre>` | El pod llega al 100 % de su límite pero el usuario no lo nota (P95 60 ms, 0 errores): el límite contiene el daño y YARP reparte entre 2 réplicas |
| Sobrecarga de memoria (sostenida) | `ram-spike.sh <deploy> 250 150` | Límite de memoria (384Mi en pharmacy). Si se pasa, el OOM killer mata el proceso que más usa dentro del contenedor | `pg-memory`: Pending 27 s, Firing 59 s, Normal 23 s después | Infra → "Memoria del pod contra su límite" | Esperar. Si la app se reinicia sola (`pg-restarts`), verificar que volvió a Ready | Al 89 % del límite la app sigue respondiendo (0 errores). El límite protege al nodo y al resto de los pods |
| Sobrecarga de memoria (pico) | `ram-spike.sh <deploy> 240 120` (versión de C16) | OOM killer a los 7 s, mata solo el proceso del experimento | Ninguna: el pico dura menos que la cadena de métricas (~30 s) | Infra → "Memoria del pod contra su límite" (puede no verse); `memory.events` del contenedor | Ninguna | La falla se resolvió antes de que la métrica llegara a Grafana. La señal es `oom_kill` en `memory.events` y la ausencia de reinicios |
| Sobrecarga de storage (brusca) | `volume-spike.sh <deploy> 600 120` | Límite de `ephemeral-storage` (512Mi): el kubelet desaloja el pod y el Deployment crea otro | Ninguna (`pg-replicas` solo Pending): el desalojo a los 47 s llega antes | Infra → "Réplicas deseadas y disponibles por Deployment"; evento `Evicted` | Ninguna. Si queda un pod `Evicted`: `kubectl delete pod <pod> -n pharmago` | El reemplazo estuvo Ready 9 s después del desalojo y la otra réplica atendió todo: 0 errores |
| Sobrecarga de storage (sostenida) | `volume-spike.sh <deploy> 400 150` | Ninguno automático hasta el límite: avisa la alerta | `pg-storage`: Pending 44 s, Firing 76 s, Normal 47-89 s después de borrar (ensayo C23: Firing 100 s). En el ensayo también disparó `pg-memory` a los 68 s | Infra → "Filesystem por pod (ephemeral-storage usado)" | Borrar el archivo o el pod: `kubectl delete pod <pod> -n pharmago` | 400 MiB pasan el umbral de 300 MiB sin llegar al desalojo: la alerta avisa antes de que actúe el kubelet. Lo escrito queda en el page cache, que cuenta como memoria del contenedor: por eso `pg-memory` puede acompañar a `pg-storage` |
| Interrupción de red (varios usuarios) | `network-chaos.sh <deploy> 60` | Circuit breaker de Polly en YARP: abre con 50 % de fallas en 10 s y al menos 8 requests; responde 503 al instante; prueba cada 5 s (half-open). Timeout por intento 3 s y 2 reintentos con jitter | `pg-breaker`: Firing 33 s (alterna con Normal en cada half-open). `pg-5xx`: Firing 61 s | Overview → "Distribución de Status Codes (%)" y "Tasa de Error por Endpoint (%)" | `kubectl get networkpolicy -n pharmago` y `kubectl delete networkpolicy <nombre> -n pharmago` | El breaker abrió a los 14 s y cortó con 503 en menos de 0,1 s en vez de esperar 9 s. Solo falla el servicio aislado: el otro sigue con 0 errores. Volvió a 200 a los 3 s de borrar la policy |
| Interrupción de red (poco tráfico) | Igual, con menos de 8 requests en 10 s | Timeout y reintentos; el breaker **no** abre (no llega al mínimo de 8) | `pg-latency`: Firing a los 92 s (después del corte). Sin `pg-breaker` | Overview → "Latencia Promedio por Endpoint" | Igual que arriba | Con poco tráfico cada request espera los reintentos (hasta 9 s) y aparece como latencia, no como 503. Para mostrar el breaker hace falta tráfico (sección 5, paso 0) |
| Desconexión de un componente | `disconnect.sh <deploy> 60` | Circuit breaker (503 inmediato) y restauración de réplicas | `pg-breaker`: Firing 33 s. `pg-5xx`: Firing 55 s. `pg-replicas` **no** dispara (bajan también las deseadas) | Infra → "Réplicas deseadas y disponibles por Deployment"; Overview → "Distribución de Status Codes (%)" | `kubectl scale deploy/<nombre> -n pharmago --replicas=2` | Con 0 réplicas no hay a quién llamar: el breaker abre y corta con 503. El otro servicio sigue con 0 errores. Al restaurar, 2/2 en 14 s |
| Borrado de un pod | `kubectl delete pod` o `measure-mttr.sh <deploy>` | 2 réplicas, readiness rápida (cada 2 s), PDB, reintento de YARP a la otra réplica y `preStop` | Ninguna (`pg-replicas` solo Pending; tiene 30 s de ventana) | Infra → "Réplicas deseadas y disponibles por Deployment" | Ninguna | La otra réplica atiende mientras el Deployment crea el reemplazo. MTTR 8,6 s, 0 errores |
| Rollout fallido | `kubectl set image ...:no-existe` | `RollingUpdate` con `maxUnavailable: 0`: las réplicas viejas no se bajan hasta que la nueva esté Ready | Ninguna: el usuario no ve nada | `kubectl rollout status`; Infra → "Réplicas deseadas y disponibles por Deployment" | `k8s/rollback.sh <deploy>` (1 s). `deploy.sh` vuelve atrás solo a los 180 s | La nueva réplica queda en `ErrImageNeverPull` y nunca recibe tráfico. Las viejas siguen 2/2 |
| Base de datos caída | `disconnect.sh pharmago-db 60` | Readiness de users y pharmacy chequea la BD: salen del balanceo; breaker en los dos clusters; `EnableRetryOnFailure` de EF Core al volver | `pg-breaker` y `pg-5xx` (los dos clusters) | Overview → "Distribución de Status Codes (%)"; Jaeger: span `PharmaDb` con error | `kubectl scale deploy/pharmago-db -n pharmago --replicas=1` y esperar unos 50 s sin reiniciar los microservicios | Punto único de falla aceptado (D04). En el postmortem de C19, 64 requests fallidas y recuperación automática 8 s después de que volvió la base |

Playbook de cada una: `requests.md`, `cpu.md`, `memoria.md`, `storage.md`, `red.md`, `desconexion.md`, `pod-caido.md` y `rollout-fallido.md`, en `docs/playbooks/`.

## 5. Protocolo frente al script desconocido de los docentes

**Paso 0, antes de que corran el script.** Dejar tráfico de fondo, para que el breaker pueda abrir y los paneles tengan datos (≈ 1,4 requests/s, debajo del rate limit):

```bash
while true; do curl -s -o /dev/null http://127.0.0.1/api/drug & curl -s -o /dev/null http://127.0.0.1/api/roles & sleep 1.4; done
```

Comms anota la hora UTC de inicio del script. A partir de ahí, el diagnóstico va **de afuera hacia adentro** con los Golden Signals, sin saltar pasos (`docs/plan-incidentes.md`, sección 7). Ops mira y reporta con números; el IC decide.

1. **Errores.** Overview → "Distribución de Status Codes (%)". 429 es rate limit; 503 es breaker abierto o sin pods; 500/502/504 es un servicio que responde mal o no responde.
2. **Latencia.** Overview → "Latencia Promedio por Endpoint". Si sube sin errores, Jaeger: qué tramo es el lento.
3. **Tráfico.** Overview → "Throughput Total". Un salto es inyección; una caída a 0 es corte.
4. **Saturación.** Infra → CPU, memoria y filesystem contra su límite. El pod cerca del 100 % es el blanco.
5. **Kubernetes.** `kubectl get pods,deploy -n pharmago -o wide` y `kubectl get events -n pharmago --sort-by=.lastTimestamp | tail -20`: `Evicted`, `OOMKilled`, `Pending`, réplicas en 0.
6. **Red.** `kubectl get networkpolicy -n pharmago`: cualquier policy que no sea nuestra.

**Cómo reconocer el tipo de falla por sus señales:**

| Lo primero que se ve | Lo que lo confirma | Falla | Tiempo esperado de la alerta |
|---|---|---|---|
| 429 en un endpoint, el resto 200 | Overview: 429 por endpoint | Requests | `pg-429` ~50 s |
| Un pod al 100 % de su CPU, sin errores | Infra: CPU contra límite | CPU | `pg-cpu` ~70 s |
| Memoria del pod sube y queda alta, sin errores | Infra: memoria contra límite | Memoria | `pg-memory` ~60 s |
| Nada en Grafana, pero un evento `OOMKilled` u `oom_kill` | `kubectl get events`, `memory.events` | Memoria (pico) | Ninguna |
| Filesystem del pod sube, o un pod `Evicted` | Infra: filesystem; eventos | Storage | `pg-storage` ~76-100 s o ninguna |
| `pg-memory` y `pg-storage` juntas en el mismo pod | Infra: filesystem por pod sube a la par de la memoria | Storage (el page cache cuenta como memoria) | `pg-memory` ~68 s, `pg-storage` ~100 s |
| 503/504 en los endpoints de un servicio, pods Ready | `kubectl get netpol` muestra una policy ajena | Red | `pg-breaker` ~33 s con tráfico |
| 503 en los endpoints de un servicio, réplicas 0/0 | `kubectl get deploy` | Desconexión | `pg-breaker` ~33 s |
| Errores en users y pharmacy a la vez, readiness falla en los dos | `kubectl get deploy pharmago-db`; Jaeger `PharmaDb` | Base de datos | `pg-breaker` y `pg-5xx` |
| Un pod desaparece y vuelve solo | Terminal 1 (`-w`) | Borrado de pod | Ninguna |
| Una réplica en `ErrImagePull` o `CrashLoopBackOff`, el resto bien | `kubectl rollout status` | Rollout fallido | Ninguna |

**Regla de oro:** primero se espera el mecanismo automático el tiempo que dice la matriz. Si a ese tiempo no se recuperó, el IC ordena la mitigación manual. Después de cada acción, `steady-state.sh` para confirmar el cierre.

## 6. Si algo del entorno falla

| Problema | Señal | Qué hacer |
|---|---|---|
| Se corta `minikube tunnel` | `http://127.0.0.1/` no carga; la terminal de PowerShell se cerró o muestra error | Volver a abrir PowerShell como administrador y `minikube tunnel`. La app no se tocó: vuelve al instante |
| Se cortan los port-forwards | Grafana o Kibana "no se puede acceder al sitio"; `lost connection to pod` | `./port-forward.sh --stop` y `./port-forward.sh`. Pasa cada vez que se reinicia el pod de destino |
| Muere el pod de Grafana | Grafana no carga y `kubectl get pods -n pharmago -l app=grafana` no está 1/1 | Esperar que el Deployment lo recree (dashboards y alertas son provisioning, vuelven solos) y relanzar `port-forward.sh` |
| Nodo `ops` sin memoria | Pods de observabilidad en `Pending` o reinicios en m05 | `kubectl top node minikube-m05`. Si no alcanza: `minikube delete` y `MINIKUBE_MEMORY=4608 ./full-up.sh` |
| Cluster colgado (kubectl no responde) | `kubectl get nodes` tarda o da timeout | `minikube status`. Si algún nodo está Stopped: `minikube start`. Si no vuelve: `minikube stop`, `minikube start` y relanzar tunnel y port-forwards |
| Docker Desktop se cae | `docker info` no responde; los 5 nodos `Exited` | Abrir Docker Desktop, `minikube start`, tunnel y port-forwards. Para que no se repita: `.wslconfig` con `memory=10GB` y compilar las imágenes con el cluster apagado |
| Las alertas no salen de Pending o quedan en Firing en reposo | Grafana → Alerting | Mirar que haya tráfico (sección 5, paso 0). `pg-5xx` y `pg-latency` sin tráfico quedan vacías a propósito (D56) |
| Todo roto y queda poco tiempo | | `minikube delete` y `./full-up.sh` (tiempo de la sección 1) |

## 7. Ensayo

**Ensayo técnico (2026-11-15, PC de Martin, cluster recién levantado con `full-up.sh`).** Los 6 tipos de falla seguidos con `docs/evidencia/C23/scripts/ensayo.sh`: steady state antes, `observar.sh` en paralelo con el caos (tráfico concurrente en red y desconexión) y steady state después hasta OK. Tiempos desde el inicio de la falla. "Steady state de vuelta" incluye que todas las alertas vuelvan a Normal (la ventana de 1 min del `rate` lo demora).

| Falla | Comando | Alerta en Firing (C18) | No-2xx que vio el usuario | Steady state de vuelta, desde el fin de la falla |
|---|---|---|---|---|
| Requests | `load-requests.sh 300 20` | `pg-429` 45 s (50 s) | 0 / 150 en `/api/drug` | 170 s |
| CPU | `cpu-spike.sh pharmago-api-gateway 120 4` | `pg-cpu` 66 s (70 s) | 0 / 200 | 116 s |
| Memoria | `ram-spike.sh pharmago-pharmacy-service 250 150` | `pg-memory` 65 s (59 s) | 0 / 200 | 72 s |
| Storage | `volume-spike.sh pharmago-users-service 400 150` | `pg-memory` 68 s y `pg-storage` 100 s (76 s) | 0 / 210 | 91 s |
| Red | `network-chaos.sh pharmago-users-service 60` | `pg-breaker` 39 s (33 s), `pg-5xx` 62 s (61 s) | 20 / 85 en `/api/roles` (19 × 503, 1 × 504); 0 / 85 en `/api/drug` | 139 s |
| Desconexión | `disconnect.sh pharmago-pharmacy-service 60` | `pg-breaker` 28 s (33 s), `pg-5xx` 66 s (55 s) | 30 / 85 en `/api/drug` (503 en ≤ 0,2 s); 0 / 85 en `/api/roles` | 124 s |

Los tiempos coinciden con C18 dentro de unos 10 s, salvo `pg-storage` (100 s contra 76 s), que depende de cuándo el kubelet recalcula el disco. Salidas completas en `docs/evidencia/C23/03-ensayo-*.txt`.

**Ensayo con los 3 integrantes y fallo sorpresa.** Pendiente: se hace con IC, Ops y Comms en sus roles, cronometrando para cada falla el tiempo hasta la alerta, hasta identificar la causa y hasta la recuperación, más un fallo elegido sin avisar por otro integrante y diagnosticado con la sección 5. El registro va en `docs/evidencia/C23/`.
