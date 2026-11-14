# Experimentos de caos (C18)

Letra: *«Diseñar e implementar experimentos de ingeniería del caos»* para los seis tipos de falla: inyección de requests, sobrecarga de CPU, memoria y storage, interrupción de red y desconexión de componentes internos. Se suma un experimento de borrado de pod y uno de rollout fallido (para el playbook de C20).

Cada experimento sigue el método del curso (D45, [Principles of Chaos](https://principlesofchaos.org/)): se mide el **steady state**, se plantea una **hipótesis falsable con números**, se acota el **blast radius**, se ejecuta, se compara y se anota qué se aprendió. Una hipótesis refutada no es un experimento fallido: encontró una debilidad antes que el war room.

**Dónde y cuándo:** cluster de 5 nodos de la PC de Ignacio Aramburu, imágenes `ff313b7`, `minikube tunnel` abierto, 2026-11-14 entre las 21:00 y las 22:00 UTC. Las salidas completas de cada corrida están en `docs/evidencia/C18/` (un `.txt` por corrida y capturas de Grafana tomadas **durante** el experimento). Las hipótesis de E3 a E7 se registraron con hora antes de correrlos (`docs/evidencia/C18/00-hipotesis-registradas.txt`).

## Herramientas

| Script | Para qué |
|---|---|
| `steady-state.sh [segundos=20]` | Verifica el steady state y sale con 0 solo si todo está bien: Deployments (4 microservicios 2/2 y la BD 1/1), 5 nodos Ready, 0 no-2xx en un loop a 1 request/s por el Ingress (`/api/drug`, `/api/roles`, `/`) y ninguna alerta de Grafana en Firing (el `/metrics` de Grafana, sin credenciales). Si algo falla, sale con la cantidad de chequeos fallidos. |
| `observar.sh <segundos> [ruta ...]` | Lo que ve el usuario (1 request/s rotando las rutas, timeout de cliente de 10 s) y el estado de las alertas cada 5 s, con hora UTC. Al final, el conteo por código y la primera vez que cada alerta pasó a Pending y a Firing. |
| Los 6 scripts de caos | Los de C16 y C17 (`README.md`). `ram-spike.sh` reserva la memoria de a bloques desde C18 (D57). |

**Cómo se corrió cada experimento** (igual para todos):

```bash
cd "Implementacion K8S/Codigo/chaos-engineering"
./steady-state.sh                                  # 1. antes: tiene que dar exit 0
./observar.sh <segundos> <rutas> &                 # 2. en otra terminal (aquí en segundo plano)
<comando de caos>                                  # 3. 5 s después de arrancar el observador
./steady-state.sh                                  # 4. después: se repite hasta exit 0
```

**Tráfico concurrente** (E5b y E6): además del observador, 1 request cada 0,7 s al endpoint afectado sin esperar la respuesta, para simular varios usuarios a la vez (≈ 1,4 requests/s, debajo del rate limit de 100 por minuto por réplica del gateway):

```bash
for i in $(seq 107); do curl -s -o /dev/null -m 15 -w '%{http_code} %{time_total}\n' http://127.0.0.1/api/roles & sleep 0.7; done
```

## Steady state

| Señal | Valor sano | Cómo se mide |
|---|---|---|
| Deployments | gateway, users, pharmacy y UI 2/2; BD 1/1 | `steady-state.sh` (1) |
| Nodos | 5/5 Ready | `steady-state.sh` (2) |
| Errores que ve el usuario | 0 no-2xx a 1 request/s | `steady-state.sh` (3), `observar.sh` |
| Latencia | P95 del gateway 13-60 ms (medido en E2 y E3b antes de la falla) | "Latencia Promedio por Endpoint", `observar.sh` |
| Alertas | ninguna en Firing (Normal 109-112 instancias, Pending 0) | `steady-state.sh` (4) |

**Antes de empezar se corrigieron dos falsos positivos del steady state** (las alertas disparaban con el sistema sano, así que ningún experimento podía validar «sin alertas»):

- `otlp-collector` al 92 % de su límite de 256Mi: `pg-memory` en Firing sin falla. Límite a 512Mi (D55).
- Sin tráfico, `pg-5xx` y `pg-latency` evaluaban NaN (0/0) y Grafana lo trataba como mayor al umbral: las dos en Firing en reposo. Se filtró para que sin tráfico la query quede vacía (D56).

Evidencia: `docs/evidencia/C18/00-*.txt`. Con los dos arreglos, el steady state dio OK antes de cada experimento.

---

## E1 · Inyección de requests

| Campo | Valor |
|---|---|
| **Hipótesis** | Una ráfaga de 300 POST a `/api/login` con concurrencia 20 recibe 429 en más del 50 %; el tráfico legítimo a `/api/drug` a 1 request/s sigue con **0 no-2xx**; `pg-429` pasa a Firing en **≤ 60 s**. |
| **Blast radius** | Solo el endpoint `/api/login` (la cuota del rate limit es por IP **y endpoint**). Nada cambia en el cluster. |
| **Comando** | `./load-requests.sh 300 20` · observador: `./observar.sh 150 /api/drug` |
| **Métrica y panel** | `pharmago_http_requests_total{status_code="429"}` · "PharmaGo - Overview" → "Rate Limit Errors (429) por Endpoint" |
| **Alerta esperada** | `pg-429` |
| **Criterio de éxito** | 429 > 50 % de la ráfaga, 0 no-2xx en `/api/drug`, `pg-429` Firing ≤ 60 s y vuelta a Normal sola. |
| **Criterio de aborto** | No-2xx en `/api/drug` o 5xx en el gateway: cortar la ráfaga (Ctrl+C). |

**Resultado** (`01-requests.txt`, capturas `01-requests-grafana-*.png`)

- Inicio 21:10:27 UTC, fin 21:10:38 (11 s). Ráfaga: **429 × 280**, 404 × 20 (las 20 que entraron en la cuota de 10 por minuto por réplica; 404 = usuario inexistente).
- `pg-429`: Pending a los 17 s, **Firing a los 50 s**, Normal a las 21:11:48 (70 s después del fin: ventana de 1 min del `rate`).
- Tráfico legítimo: **0 no-2xx en 150** requests a `/api/drug`. Steady state OK al primer intento.
- **Hipótesis confirmada.**

## E2 · Sobrecarga de CPU

| Campo | Valor |
|---|---|
| **Hipótesis** | Con 4 hilos de CPU durante 120 s en un pod del gateway, el contenedor llega a su límite (500m) pero el usuario no lo nota: **0 no-2xx** y **P95 < 1000 ms**; `pg-cpu` pasa a Firing en **≤ 60 s**. |
| **Blast radius** | Un pod del gateway (el límite de CPU impide que afecte al resto del nodo). La otra réplica sigue sana. |
| **Comando** | `./cpu-spike.sh pharmago-api-gateway 120 4` · observador: `./observar.sh 200 /api/drug /api/roles` |
| **Métrica y panel** | `k8s_pod_cpu_limit_utilization_ratio` · "PharmaGo - Infra" → "CPU del contenedor contra su límite" y "CPU por pod (núcleos)" |
| **Alerta esperada** | `pg-cpu` |
| **Criterio de éxito** | 0 no-2xx, P95 < 1000 ms, `pg-cpu` Firing ≤ 60 s y Normal al terminar. |
| **Criterio de aborto** | 5xx o P95 > 3 s: Ctrl+C (el `trap` mata los loops). |

**Resultado** (`02-cpu.txt`, `02-cpu-grafana-*.png`)

- Inicio 21:14:59, fin 21:17:01. El pod llegó a **0,5 núcleos (100 % del límite)**.
- `pg-cpu`: Pending a los 33 s, **Firing a los 70 s**, Normal 30 s después del fin.
- Usuario: **0 no-2xx en 200**, P95 60 ms, máximo 186 ms. `pg-latency` no disparó.
- **Hipótesis refutada** en el tiempo de detección (70 s contra ≤ 60 s). El resto se cumplió. Ver «Qué se aprendió» (1).

## E3 · Sobrecarga de memoria

| Campo | Valor |
|---|---|
| **Hipótesis** | Con 240-250 MB retenidos durante 120-150 s en un pod de pharmacy (límite 384Mi), `pg-memory` pasa a Firing en **≤ 75 s**; **0 no-2xx**; sin reinicios del contenedor; la memoria vuelve a su valor base y la alerta a Normal en ≤ 60 s. |
| **Blast radius** | Un pod de pharmacy. Si se supera el límite, el OOM killer actúa dentro de ese contenedor. |
| **Comando** | E3a: `./ram-spike.sh pharmago-pharmacy-service 240 120` (versión de C16) · E3b: `./ram-spike.sh pharmago-pharmacy-service 250 150` (con reserva por bloques, D57) · observador: `./observar.sh 200 /api/drug /api/roles` |
| **Métrica y panel** | `k8s_pod_memory_limit_utilization_ratio` · "PharmaGo - Infra" → "Memoria del pod contra su límite" |
| **Alerta esperada** | `pg-memory` |
| **Criterio de éxito** | Firing ≤ 75 s, 0 no-2xx, 0 reinicios, Normal ≤ 60 s después del fin. |
| **Criterio de aborto** | Reinicios de la app o no-2xx: Ctrl+C. |

**Resultado E3a** (`03a-memoria-240-oom.txt`, `03-memoria-pods.txt`)

- Inicio 21:20:52. **El OOM killer mató el proceso del experimento a los 7 s** (exit 137, `oom_kill 1` en `memory.events`). La app no se reinició (0 → 0) y el usuario no vio nada (0 no-2xx en 200).
- **Ninguna alerta salió de Normal**: el pico duró menos que la cadena de métricas.
- **Hipótesis refutada.** El script armaba una sola cadena y la shell usa casi el doble mientras la construye: no podía sostener más de ~150 MB (61 % del límite). Se corrigió `ram-spike.sh` (D57) y se repitió.

**Resultado E3b** (`03b-memoria.txt`, `03b-memoria-grafana-*.png`)

- Inicio 21:25:31, fin 21:28:12. La memoria del pod quedó **sostenida en 89 %** del límite, sin OOM nuevo.
- `pg-memory`: Pending a los 27 s, **Firing a los 59 s**, Normal 23 s después del fin. (`pg-cpu` llegó a Pending unos segundos mientras se armaban los bloques y no disparó.)
- Usuario: **0 no-2xx en 210**, P95 13 ms. Reinicios 0 → 0; memoria de vuelta en 75Mi.
- **Hipótesis confirmada.**

## E4 · Sobrecarga de storage

| Campo | Valor |
|---|---|
| **Hipótesis** | Escribir 600 MB en un pod de users (límite `ephemeral-storage` 512Mi) hace que el kubelet lo desaloje durante el experimento; **0 no-2xx** en `/api/roles`; el Deployment vuelve a 2/2 en **≤ 30 s** desde el desalojo; `pg-replicas` **no** dispara; `pg-storage` dispara en ≤ 75 s si el desalojo tarda más que eso. |
| **Blast radius** | Un pod de users; el límite impide llenar el disco del nodo. |
| **Comando** | E4: `./volume-spike.sh pharmago-users-service 600 120` · E4c: `./volume-spike.sh pharmago-users-service 400 150` (bajo el límite, para validar `pg-storage`) · observador: `./observar.sh 210 /api/roles /api/drug` |
| **Métrica y panel** | `k8s_pod_filesystem_usage_bytes` · "PharmaGo - Infra" → "Filesystem por pod (ephemeral-storage usado)" y "Réplicas deseadas y disponibles por Deployment"; evento `Evicted` |
| **Alerta esperada** | `pg-storage` (llenado sostenido); ninguna con llenado brusco (lo resuelve el desalojo) |
| **Criterio de éxito** | Desalojo, 0 no-2xx, 2/2 ≤ 30 s, `pg-replicas` sin Firing. E4c: `pg-storage` Firing ≤ 75 s. |
| **Criterio de aborto** | Pods `Pending` o desalojo de la otra réplica: borrar `/tmp/chaos_fill` y Ctrl+C. |

**Resultado E4** (`04-storage.txt`, `04-storage-pods.txt`, `04-storage-grafana-*.png`)

- Inicio 21:30:25, fin 21:31:15. **Desalojo a los 47 s** (evento `Evicted` a las 21:31:12: «Pod ephemeral local storage usage exceeds the total limit of containers 512Mi»). El reemplazo se creó a las 21:31:14 y quedó **Ready a las 21:31:21: 9 s** después del desalojo.
- Usuario: **0 no-2xx en 210**. `pg-replicas` llegó a Pending 6 s y no disparó.
- `pg-storage` **no** disparó: Prometheus nunca vio el archivo (máximo 0 MiB para ese pod). Una prueba aparte (`04b-storage-kubelet-no-ve-rootfs.txt`) mostró que el kubelet calcula el disco con retraso: 15 s después de escribir 200 MB informaba 101 MiB.
- **Hipótesis confirmada** (el desalojo llegó antes de los 75 s, así que la condición de `pg-storage` no aplicaba).

**Resultado E4c** (`04c-storage-400.txt`, `04c-storage-400-grafana-*.png`)

- Inicio 21:36:51, fin 21:39:24. `pg-storage`: Pending a los 44 s, **Firing a los 76 s**, Normal entre 47 y 89 s después de borrar el archivo. 0 no-2xx en 210.
- **Hipótesis confirmada en lo esencial**: la alerta funciona ante un llenado sostenido; tardó 76 s, 1 s más que la cota de 75 s.

## E5 · Interrupción de red

| Campo | Valor |
|---|---|
| **Hipótesis** | Con una NetworkPolicy que corta todo el tráfico de users durante 60 s: `/api/roles` falla durante el corte; `/api/drug` sigue con **0 no-2xx** (blast radius: solo users); `pg-breaker` pasa a Firing en **≤ 30 s** y `pg-5xx` en **≤ 75 s**; `/api/roles` vuelve a 2xx en **≤ 15 s** después de borrar la policy. |
| **Blast radius** | El microservicio users (y los endpoints que atiende). La policy lleva el prefijo `chaos-` y el script la borra siempre (`trap`). |
| **Comando** | E5a: `./network-chaos.sh pharmago-users-service 60` con el observador a 0,5 requests/s por endpoint y timeout de cliente de 3 s · E5b: lo mismo, con timeout de 10 s y tráfico concurrente a `/api/roles` (≈ 1,4 requests/s) |
| **Métrica y panel** | `pharmago_http_requests_total` por código, `pharmago_circuit_breaker_state` · "PharmaGo - Overview" → "Distribución de Status Codes (%)" y "Tasa de Error por Endpoint (%)" |
| **Alerta esperada** | `pg-breaker`, `pg-5xx` |
| **Criterio de éxito** | Lo de la hipótesis. |
| **Criterio de aborto** | Errores en `/api/drug` o en la UI: `kubectl delete networkpolicy -n pharmago chaos-deny-pharmago-users-service`. |

**Resultado E5a: poco tráfico** (`05a-red-cliente-3s.txt`)

- Inicio 21:41:46, fin 21:42:48. `/api/roles`: 15 no-2xx de 75 (14 cortes del propio cliente a los 3 s y un 504). `/api/drug`: **0 no-2xx en 75**.
- **El breaker no abrió**: con 0,5 requests/s a users no se llega a 8 requests en 10 s (mínimo de D13). Cada request esperó el timeout de 3 s por intento. Solo disparó `pg-latency` (Pending a los 32 s, Firing a los 92 s, **después** del fin del corte). El gateway registró como 400 los cortes del cliente.
- Al borrar la policy, `/api/roles` volvió a 200 a las 21:42:50 (unos 3 s).
- **Hipótesis refutada**: no hubo `pg-breaker` ni `pg-5xx`. El timeout de 3 s del cliente también escondía el código real: se subió a 10 s en `observar.sh`.

**Resultado E5b: varios usuarios** (`05b-red.txt`, `05b-red-grafana-*.png`)

- Inicio 21:47:03, fin 21:48:05. Log del gateway: `circuit_breaker cluster=users-cluster state=open` a las 21:47:17 (**14 s** del corte), y desde ahí open y half-open cada 5-7 s.
- Tráfico concurrente a `/api/roles`: 200 × 30, **503 × 74**, 504 × 3. Las 503 tardaron **menos de 0,1 s** (salvo las pruebas de half-open, hasta 3,2 s), en lugar de esperar 9 s.
- `pg-breaker`: **Firing visto a los 33 s** (alterna con Normal en cada half-open). `pg-5xx`: Firing a los 61 s. `pg-latency`: Firing a las 21:48:42, ya terminado el corte. Todas en Normal a las 21:49:14 (69 s después del fin).
- `/api/drug`: **0 no-2xx en 75**. `/api/roles` volvió a 200 a las 21:48:08 (3 s después de borrar la policy).
- **Hipótesis refutada por poco**: `pg-breaker` tardó 33 s contra ≤ 30 s. Lo demás se cumplió.

## E6 · Desconexión de un componente interno

| Campo | Valor |
|---|---|
| **Hipótesis** | Con pharmacy escalado a 0 durante 60 s: `/api/drug` responde 503; `/api/roles` sigue con **0 no-2xx**; `pg-breaker` pasa a Firing en **≤ 30 s**; `pg-replicas` **no** dispara (las deseadas también bajan); `/api/drug` vuelve a 2xx en **≤ 30 s** desde que se restauran las réplicas; `steady-state.sh` corrido durante la falla termina con salida distinta de 0. |
| **Blast radius** | El microservicio pharmacy (`/api/drug`). El script restaura las réplicas originales siempre (`trap`). |
| **Comando** | `./disconnect.sh pharmago-pharmacy-service 60`, con tráfico concurrente a `/api/drug` y `./steady-state.sh 10` a los 25 s · observador: `./observar.sh 170 /api/drug /api/roles` |
| **Métrica y panel** | `k8s_deployment_available`, `pharmago_circuit_breaker_state` · "PharmaGo - Infra" → "Réplicas deseadas y disponibles por Deployment"; "PharmaGo - Overview" → "Distribución de Status Codes (%)" |
| **Alerta esperada** | `pg-breaker`, `pg-5xx` |
| **Criterio de éxito** | Lo de la hipótesis. |
| **Criterio de aborto** | Errores en `/api/roles`: `kubectl scale deploy/pharmago-pharmacy-service -n pharmago --replicas=2`. |

**Resultado** (`06-desconexion.txt`, `06-desconexion-grafana-*.png`)

- Inicio 21:51:18; restauración 21:52:20; **2/2 Ready a las 21:52:34 (14 s)**.
- Tráfico concurrente a `/api/drug`: 502 × 3 al principio (pods apagándose), después **503 × 87** en menos de 0,3 s cada una, y 200 de nuevo a las 21:52:30-34.
- `pg-breaker`: **Firing a los 33 s**; `pg-5xx`: Firing a los 55 s; `pg-replicas`: solo Pending durante la restauración. Todas en Normal a las 21:53:50.
- `/api/roles`: **0 no-2xx en 85**.
- `steady-state.sh` durante la falla: **exit 3** (pharmacy 0/2, 4 respuestas 503, `pg-breaker` en Firing).
- **Hipótesis refutada por poco**: `pg-breaker` tardó 33 s contra ≤ 30 s. Lo demás se cumplió.

## E7 · Borrado de un pod

| Campo | Valor |
|---|---|
| **Hipótesis** | Borrar un pod de users: **0 no-2xx**, **MTTR < 15 s**, ninguna alerta en Firing (`pg-replicas` tiene 30 s de ventana; borrar no es reiniciar). |
| **Blast radius** | Una réplica de users. |
| **Comando** | `../k8s/verify/measure-mttr.sh pharmago-users-service` · observador: `./observar.sh 100 /api/drug /` |
| **Métrica y panel** | MTTR de `measure-mttr.sh`; "PharmaGo - Infra" → "Réplicas deseadas y disponibles por Deployment" |
| **Alerta esperada** | Ninguna en Firing |
| **Criterio de éxito** | Lo de la hipótesis. |
| **Criterio de aborto** | La otra réplica no Ready: no borrar. |

**Resultado** (`07-pod-borrado.txt`, `07-pod-borrado-grafana-*.png`)

- Inicio 21:55:34, borrado a las 21:55:44, fin 21:56:20. **MTTR 8,6 s.** `measure-mttr.sh`: 40 de 40 con 2xx; observador: 100 de 100 con 2xx.
- `pg-replicas`: Pending de 21:56:07 a 21:56:18 y **no** disparó. Ninguna otra salió de Normal.
- **Hipótesis confirmada.**

## E8 · Rollout fallido (extra, para el playbook de C20)

| Campo | Valor |
|---|---|
| **Hipótesis** | Desplegar en pharmacy una imagen que no existe deja el rollout trabado sin afectar al usuario (**0 no-2xx**, gracias a `maxUnavailable: 0`), y `rollback.sh` vuelve a la versión anterior en **< 30 s**. Pregunta abierta: ¿qué alerta lo detecta? |
| **Blast radius** | El Deployment de pharmacy. |
| **Comando** | `kubectl set image deploy/pharmago-pharmacy-service pharmago-pharmacy-service=pharmago-pharmacy-service:no-existe -n pharmago`; 45 s después, `../k8s/rollback.sh pharmago-pharmacy-service` · observador: `./observar.sh 150 /api/drug /api/roles` |
| **Métrica y panel** | `kubectl rollout status`; "PharmaGo - Infra" → "Réplicas deseadas y disponibles por Deployment" |
| **Criterio de aborto** | No-2xx en `/api/drug`: `rollback.sh` inmediato. |

**Resultado** (`08-rollout-fallido.txt`, `08-rollout-fallido-grafana-*.png`)

- 21:58:39 `set image`. El pod nuevo quedó en `ErrImageNeverPull`; el Deployment siguió **2/2 disponible** con las réplicas viejas. `kubectl rollout status --timeout=10s` no terminó (exit 1).
- Usuario: **0 no-2xx en 150**. **Ninguna alerta salió de Normal.**
- 21:59:35 `rollback.sh`: rollout completo en **1 s**.
- **Hipótesis confirmada.** Respuesta a la pregunta: ninguna alerta lo detecta; la señal es `deploy.sh` (que vuelve atrás solo a los 180 s) o `kubectl rollout status`.

---

## Tabla resumen

Tiempos desde el inicio de la falla. «Recuperación» es el tiempo hasta que el usuario vuelve a ver 2xx o el Deployment vuelve a 2/2, contado desde que termina la falla o se quita la causa.

| Exp. | Falla | No-2xx que vio el usuario | Alerta (Pending → Firing) | Recuperación | Hipótesis |
|---|---|---|---|---|---|
| E1 | 300 requests a login | 0 / 150 en `/api/drug` | `pg-429` 17 s → 50 s | Inmediata (`pg-429` Normal 70 s después) | Confirmada |
| E2 | CPU al 100 % del límite, gateway | 0 / 200 | `pg-cpu` 33 s → 70 s | Normal 30 s después | **Refutada** (70 s > 60 s) |
| E3a | 240 MB de golpe, pharmacy | 0 / 200 | Ninguna | OOM a los 7 s, sin reinicio | **Refutada** (sin alerta) |
| E3b | 250 MB sostenidos, pharmacy | 0 / 210 | `pg-memory` 27 s → 59 s | Normal 23 s después | Confirmada |
| E4 | 600 MB en disco, users | 0 / 210 | Ninguna (`pg-replicas` solo Pending) | Desalojo a 47 s, 2/2 en 9 s | Confirmada |
| E4c | 400 MB sostenidos en disco | 0 / 210 | `pg-storage` 44 s → 76 s | Normal 47-89 s después | Confirmada (76 s ≈ 75 s) |
| E5a | Red de users cortada, poco tráfico | 15 / 75 en `/api/roles`; 0 / 75 en `/api/drug` | `pg-latency` 32 s → 92 s; sin breaker | 200 a los 3 s | **Refutada** (sin breaker ni 5xx) |
| E5b | Red de users cortada, varios usuarios | 77 / 107 concurrentes en `/api/roles`; 0 / 75 en `/api/drug` | `pg-breaker` 33 s; `pg-5xx` → 61 s | 200 a los 3 s | **Refutada por poco** (33 s > 30 s) |
| E6 | pharmacy a 0 réplicas | 90 / 107 concurrentes en `/api/drug`; 0 / 85 en `/api/roles` | `pg-breaker` 33 s; `pg-5xx` → 55 s | 2/2 en 14 s | **Refutada por poco** (33 s > 30 s) |
| E7 | Borrado de un pod de users | 0 / 140 | Ninguna (`pg-replicas` solo Pending) | MTTR 8,6 s | Confirmada |
| E8 | Imagen inexistente en pharmacy | 0 / 150 | Ninguna | `rollback.sh` en 1 s | Confirmada |

En todos los casos el steady state volvió a dar OK (`steady-state.sh` exit 0) después de la falla, sin intervención manual salvo el rollback de E8.

## Qué se aprendió de las hipótesis refutadas

1. **La detección tiene un piso de unos 30 s, y no se había contado** (E2, E5b, E6). Entre que pasa algo y que Grafana lo evalúa hay una cadena: el kubelet o la app miden (cada 10 s o 5 s), el Collector exporta, Prometheus scrapea cada 5 s y Grafana evalúa cada 10 s. Para una alerta con ventana (`for: 30s`) eso da Firing a los 60-76 s; para una sin ventana (`pg-breaker`), a los ~33 s. Las hipótesis «≤ 30 s» y «≤ 60 s» suponían detección instantánea. Se registra el valor medido en los playbooks como tiempo esperado y **no** se bajan las ventanas: con menos de 30 s, un pico de un instante (como el `pg-cpu` de E3b mientras se reservaba memoria) dispararía.
2. **Las fallas más rápidas que esa cadena no generan alerta** (E3a, E4). Un pico de memoria que el OOM killer corta en 7 s o un disco que el kubelet desaloja en 47 s se resuelven solos antes de que la métrica llegue. No es grave, porque el mecanismo automático actuó y el usuario no vio errores, pero el war room tiene que saber dónde mirar: `memory.events` (OOM) y los eventos `Evicted`. Quedó en los playbooks de memoria y storage.
3. **El circuit breaker necesita tráfico para abrir** (E5a). Con menos de 8 requests en 10 s por réplica del gateway, nunca abre: cada usuario espera los reintentos (hasta 9 s) y la única alerta es `pg-latency`, que llega tarde. Con tráfico de varios usuarios (E5b) abre en 14 s y corta con 503 en milisegundos. En la defensa, para ver el breaker, el war room tiene que mirar con tráfico; si la falla llega con poco tráfico, la señal es la latencia.
4. **La herramienta de medición también puede mentir** (E3a, E5a). `ram-spike.sh` no podía generar la presión que decía (D57) y el timeout de 3 s del observador escondía los 504 del gateway. Se corrigieron los dos antes de repetir.
5. **Un rollout trabado no dispara nada** (E8, hipótesis confirmada pero con hallazgo): `maxUnavailable: 0` protege al usuario tan bien que ninguna métrica cambia. La señal es `deploy.sh`, que vuelve atrás solo a los 180 s.

## Ajustes hechos por lo medido

| Qué | Antes | Después | Motivo medido | Dónde |
|---|---|---|---|---|
| Memoria del `otlp-collector` | límite 256Mi | 512Mi y `GOMEMLIMIT=400MiB` | 92 % en steady state, `pg-memory` en Firing sin falla | D55 |
| Query de `pg-5xx` y `pg-latency` | NaN sin tráfico | vacía sin tráfico | Las dos en Firing en reposo | D56, `docs/alertas.md` |
| `ram-spike.sh` | una sola cadena | bloques de 16 MB | OOM a los 7 s con 240 MB, máximo sostenible 61 % del límite | D57 |
| `observar.sh` | timeout de cliente 3 s | 10 s | Escondía los 504 del gateway (E5a) | este documento |
| Panel "Distribución de Status Codes (%)" | sin datos | `on() group_left` | La división sin etiquetas comunes daba vacío; lo usan el plan y los playbooks | `docs/alertas.md` |
| Panel "Memoria del contenedor contra su límite" | error de series duplicadas | `max by` en el divisor | Al reiniciarse un contenedor cambia su `container_id` | `docs/alertas.md` |

No se cambió ningún umbral ni ventana de alerta: los valores medidos no dieron motivo (ver aprendizaje 1).
