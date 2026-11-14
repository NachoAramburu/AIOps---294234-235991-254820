# Plan de contención de incidentes operacionales

Letra: *"implementar un plan de contención de incidentes operacionales"* y, en la defensa, *"llevar adelante el plan de mitigación de incidentes operacionales diseñado durante el curso"*.

Este documento es para usar **durante** el incidente: quién hace qué, qué se mira y en qué orden. El detalle de cada falla está en los playbooks (`docs/playbooks/`) y las plantillas en `docs/plantillas/`.

> **Estado de los vínculos (14/11).** Las alertas `pg-*` se provisionan en el bloque B6 (C13) y los playbooks, `steady-state.sh` y `EXPERIMENTOS.md` en el bloque B7 (C18 y C20). Acá se nombran por el uid y el nombre que tienen en el plan. Lo marcado *(B6)* o *(B7)* todavía no existe en el repo. B7 revisa que este plan nombre las alertas y paneles reales. Todo lo demás existe y está verificado en `docs/evidencia/C19/`.

## 1. Alcance

- **Sistema:** PharmaGo en Minikube, namespace `pharmago`: UI, gateway, users, pharmacy y la base de datos, más la observabilidad (Collector, Prometheus, Grafana, Jaeger, Elasticsearch, Kibana).
- **Incidente:** cualquier degradación que vea el usuario (errores, lentitud, caída) o que lo ponga en riesgo (saturación, réplicas faltantes, nodo NotReady).
- **Fuera de alcance:** cambios de funcionalidad de negocio. En un incidente no se edita código: se mitiga con lo que ya está desplegado (escalar, reiniciar, rollback, quitar la causa).

## 2. Ciclo del incidente

Ciclo del curso: Prepare, Detect, Respond, Recover, Learn (D46).

| Fase | Qué hacemos | Con qué |
|---|---|---|
| **Prepare** | Antes de la defensa: cluster arriba, app accesible, observabilidad abierta y steady state verificado. Roles asignados, plantillas a mano. | `minikube status`, `minikube tunnel` (PowerShell como administrador), `k8s/port-forward.sh`, Grafana, `chaos-engineering/steady-state.sh` *(B7)*, sección 4 |
| **Detect** | Una alerta de Grafana pasa a *Firing*, o un panel muestra un cambio de Golden Signals. Comms anota la hora UTC. | Grafana → Alerting *(B6)*; dashboards "PharmaGo - Overview" y "PharmaGo - Infra" |
| **Respond** | El IC asigna severidad y playbook. Ops confirma con telemetría y diagnostica. Primero se **espera el mecanismo automático** el tiempo que dice el playbook; si no alcanza, se mitiga a mano. | `docs/playbooks/*.md` *(B7)*, `kubectl`, Jaeger, Kibana, sección 7 |
| **Recover** | Se valida que el sistema volvió al steady state y se cierra el incidente. | `steady-state.sh` *(B7)*; mientras tanto, el chequeo manual de la sección 6 |
| **Learn** | Registro completo y postmortem blameless: qué permitió la falla, no quién la causó. Acciones con responsable. | `docs/plantillas/registro-incidente.md`, `docs/plantillas/postmortem.md`, `docs/incidentes/` |

## 3. Severidades

Los criterios se miden en los paneles y alertas que se nombran. Ante la duda, se elige la severidad **más alta** y se baja después.

| Severidad | Criterio medible (cualquiera alcanza) | Respuesta | A quién involucra |
|---|---|---|---|
| **SEV1: servicio caído** | 5xx del gateway > 50 % durante 1 min · un microservicio o la BD con 0 réplicas disponibles · circuit breaker abierto más de 30 s (`pharmago_circuit_breaker_state == 1`) · nodo NotReady | Inmediata, en menos de 1 min. Actualización cada 1 min | Los 3. Ops no toma otra tarea hasta mitigar |
| **SEV2: degradado** | 5xx del gateway entre 5 % y 50 % durante 30 s (`pg-5xx` *(B6)*) · P95 del gateway > 1000 ms durante 1 min (`pg-latency` *(B6)*) · réplicas disponibles < deseadas durante 30 s (`pg-replicas` *(B6)*) · CPU > 80 % o memoria > 85 % del límite durante 30 s (`pg-cpu`, `pg-memory` *(B6)*) | En menos de 2 min. Actualización cada 2 min | IC y Ops. Comms registra |
| **SEV3: sin impacto visible** | Un pod se reinició y volvió solo (`pg-restarts` *(B6)*) · 429 del rate limit (`pg-429` *(B6)*): es la protección funcionando · storage del pod creciendo sin llegar al límite (`pg-storage` *(B6)*) · anomalía de latencia sin errores (`pg-latency-anomaly` *(B6)*) | En menos de 5 min o al terminar lo urgente. Se registra | Ops verifica, Comms registra |

**Escalar:** si una SEV2 o SEV3 sigue sin mejorar después del tiempo de mitigación automática del playbook, sube un nivel. **Bajar:** cuando el criterio deja de cumplirse durante 1 min y la causa está identificada.

## 4. Roles

Patrón del curso: Incident Commander, Ops y Comms (D46, [Managing incidents](https://sre.google/sre-book/managing-incidents/)). Asignación para la defensa, por sorteo:

| Rol | Persona | Qué hace | Qué **no** hace |
|---|---|---|---|
| **Incident Commander (IC)** | Martin Roux | Declara el incidente y su severidad, elige el playbook, decide cada acción ("Ops, escalá users a 3"), pide el estado a intervalos fijos y declara el cierre. Habla con los docentes. | No teclea comandos: si ejecuta, pierde la visión del conjunto |
| **Ops** | Ignacio Aramburu | Ejecuta el diagnóstico y la mitigación del playbook, mira la telemetría y reporta hechos con números ("5xx en 30 %, pharmacy 0/2 Ready"). Confirma cada orden antes y después de ejecutarla. | No decide solo una acción que cambie el cluster; la propone al IC |
| **Comms** | Franco (francokbd) | Lleva el reloj UTC y el registro (`registro-incidente.md`) en vivo, escribe los mensajes de inicio, actualización y cierre, y le recuerda al IC cuándo toca actualizar. Abre el postmortem al cierre. | No opina sobre la mitigación salvo que el IC pregunte |

**Si falta uno:**

- **Falta Comms:** el IC suma Comms y lleva el registro con frases cortas. Ops sigue igual.
- **Falta el IC:** Comms pasa a IC y suma Comms. Ops sigue igual, porque es el que más contexto técnico tiene en el momento.
- **Falta Ops:** el IC pasa a Ops y Comms pasa a IC. Así siempre hay alguien que decide y no teclea.
- **Regla fija:** quien ejecuta comandos nunca es el que decide sin consultar. Con 2 personas, una hace IC y Comms, y la otra Ops.

## 5. War room

### Qué abre cada rol

| Rol | Pantallas |
|---|---|
| IC | Grafana "PharmaGo - Overview" (Golden Signals de la app) y Grafana → Alerting *(B6)* con la lista de alertas. El playbook del incidente abierto. |
| Ops | Terminal con `kubectl get pods -n pharmago -o wide -w`; una segunda terminal libre para diagnosticar; Grafana "PharmaGo - Infra" (nodo, pod y contenedor); Jaeger (`http://127.0.0.1:16686`) y Kibana (`http://127.0.0.1:5601`, índice `pharmago-logs-*`) cuando hace falta. |
| Comms | `docs/plantillas/registro-incidente.md` copiado a `docs/incidentes/<fecha>-<tema>.md`, reloj en UTC (`date -u +%T`) y la app (`http://127.0.0.1/`) para ver lo mismo que el usuario. |

### Cómo se habla

- **Circuito cerrado:** el IC ordena con nombre y acción; Ops repite y confirma al terminar. Por ejemplo: "Ops: rollback de pharmacy" → "Rollback de pharmacy, voy" → "Rollback hecho, pharmacy 2/2 Ready".
- **Hechos con números, no impresiones:** "5xx en 40 % desde 14:02:10", no "anda mal".
- **Una sola conversación:** si dos personas hablan a la vez, el IC corta y ordena.
- **Estado a intervalos fijos:** SEV1 cada 1 min, SEV2 cada 2 min, SEV3 al cerrar. Comms avisa "toca estado" y el IC lo dice en voz alta: severidad, qué se sabe, qué se está haciendo y próximo paso.

## 6. Flujo: de la alerta al cierre

```
Alerta Firing (Grafana)  o  cambio en un panel
        │  Comms anota hora UTC y señal
        ▼
IC: declara incidente, severidad (sección 3) y playbook (tabla de abajo)
        ▼
Ops: confirma en el panel del playbook ──── ¿falso positivo? ── sí ──► registrar y cerrar como SEV3
        │ no
        ▼
Esperar la mitigación automática el tiempo que dice el playbook (probes, réplicas, breaker, desalojo)
        │
        ├── se recupera ─────────────────────────────┐
        ▼                                            │
Mitigación manual del playbook, ordenada por el IC   │
        │                                            │
        ▼                                            ▼
Validación: steady state ── no ──► volver a diagnosticar (o subir severidad)
        │ sí
        ▼
IC declara cierre; Comms envía mensaje de cierre y completa el registro
        ▼
Postmortem blameless (docs/plantillas/postmortem.md)
```

**Steady state, para validar** (lo automatiza `steady-state.sh` *(B7)*; mientras tanto se chequea a mano):

1. `kubectl get deploy -n pharmago`: los 4 microservicios 2/2 y la BD 1/1.
2. `kubectl get nodes`: los 5 nodos Ready.
3. 20 s de loop a 1 request/s por el Ingress (`/api/drug`, `/api/roles`, `/`): 0 respuestas no-2xx.
4. Grafana → Alerting: sin alertas *Firing* *(B6)*.

**Alerta, playbook y mecanismo automático** (las alertas son de B6 y los playbooks de B7; los tiempos son los medidos hasta hoy):

| Alerta (uid, B6) | Playbook (B7) | Mecanismo automático que se espera | Tiempo de referencia |
|---|---|---|---|
| `pg-429` | `docs/playbooks/requests.md` | Rate limit del gateway: corta con 429 | Inmediato (`RATE_LIMITING_GUIDE.md`) |
| `pg-cpu` | `docs/playbooks/cpu.md` | Throttling en el límite de CPU; la readiness saca al pod si deja de responder | Readiness: unos 4 s (D12) |
| `pg-memory` | `docs/playbooks/memoria.md` | El OOM killer mata el proceso que se pasa del límite | Ver C16: la app sigue viva |
| `pg-storage` | `docs/playbooks/storage.md` | Desalojo por `ephemeral-storage` > 512Mi y reemplazo del pod | C16: el pod de reemplazo queda Ready |
| `pg-5xx`, `pg-breaker` | `docs/playbooks/red.md` o `desconexion.md` | Circuit breaker: 503 rápido; readiness fuera de balanceo | Breaker abierto 5 s por ciclo (D13); readiness unos 6 s (C17) |
| `pg-replicas`, `pg-restarts` | `docs/playbooks/pod-caido.md` | Reemplazo o reinicio del pod; la otra réplica atiende | MTTR de 3,0 a 8,8 s, 0 errores (`docs/mttr.md`) |
| `pg-latency`, `pg-latency-anomaly` | Según la causa (Jaeger: qué tramo tarda) | Timeout de 3 s por intento y reintento de GET (D13) | 3 s por intento |
| (rollout que no termina) | `docs/playbooks/rollout-fallido.md` | `deploy.sh` vuelve atrás solo si el rollout no termina en 180 s | 180 s (`k8s/deploy.sh`) |

## 7. Ante el script de los docentes (falla desconocida)

No sabemos qué va a romper. Se diagnostica **de afuera hacia adentro** con los Golden Signals, en este orden, sin saltar pasos. Ops mira y reporta; el IC decide.

1. **Errores (lo que ve el usuario).** Overview: "Tasa de Error por Endpoint (%)" y "Distribución de Status Codes (%)". ¿Qué código aparece?
   - **429:** rate limit, inyección de requests → `requests.md`. SEV3, salvo que bloquee a usuarios legítimos.
   - **503:** circuito abierto o ningún pod Ready detrás del gateway. `kubectl logs -n pharmago -l app=pharmago-api-gateway --since=5m | grep circuit_breaker` dice qué cluster (`users-cluster` o `pharmacy-cluster`).
   - **500 o 502:** el servicio responde mal o la conexión se corta. Ver qué endpoint (`/api/drug` es pharmacy; `/api/login` y `/api/roles` son users).
2. **Latencia.** Overview: "Latencia Promedio por Endpoint". Si sube, Jaeger: abrí una traza lenta y mirá qué tramo ocupa el tiempo (gateway, servicio o `PharmaDb`). Si el tramo de SQL es el lento o tiene error, el problema es la base.
3. **Tráfico.** Overview: "Throughput Total" y "Peticiones por Segundo por Endpoint". Un salto brusco indica inyección de requests; una caída a 0 indica corte (red, desconexión o Ingress).
4. **Saturación.** Infra: "CPU del contenedor contra su límite", "Memoria del pod contra su límite", "Filesystem por pod" y "Red por nodo". El pod que está cerca del 100 % es el blanco.
5. **Estado de Kubernetes.** Infra: "Réplicas deseadas y disponibles por Deployment", "Reinicios por contenedor" y "Nodos Ready". En la terminal: `kubectl get pods -n pharmago -o wide` y `kubectl get events -n pharmago --sort-by=.lastTimestamp | tail -20`. Buscar `Evicted`, `OOMKilled`, `CrashLoopBackOff`, `Pending` o una réplica en 0 (desconexión, D42).
6. **Red.** `kubectl get networkpolicy -n pharmago`: una policy `chaos-*` o desconocida que niega tráfico corta la red (D41). Los pods pueden seguir Ready aunque el usuario vea errores (C17).

**Tabla de triage rápido:**

| Síntoma combinado | Falla probable | Confirmar con |
|---|---|---|
| Muchos 429, CPU del gateway alta | Inyección de requests | Overview: 429 por endpoint |
| Un pod al 100 % de CPU, latencia sube, sin errores | Sobrecarga de CPU | Infra: CPU contra límite |
| Memoria del pod contra límite cerca de 1, después baja de golpe | Sobrecarga de memoria (OOM) | Infra: memoria; eventos |
| Filesystem por pod crece; pod `Evicted` | Sobrecarga de storage | Infra: filesystem por pod; eventos |
| 502/504 o 000 en un servicio, pods Ready, NetworkPolicy presente | Interrupción de red | `kubectl get netpol` |
| Réplicas disponibles en 0, 503 con breaker abierto | Desconexión de un componente | Infra: réplicas; `kubectl get deploy` |
| 500 en pharmacy y users a la vez, readiness falla en los dos | Base de datos caída | `kubectl get deploy pharmago-db`; Jaeger: span `PharmaDb` con error |

**Mitigaciones manuales disponibles** (siempre las ordena el IC):

| Acción | Comando | Cuándo |
|---|---|---|
| Ver estado | `kubectl get pods,deploy -n pharmago -o wide` | Siempre primero |
| Reiniciar un microservicio sin cortar | `kubectl rollout restart deploy/<nombre> -n pharmago` | Pods vivos pero en mal estado |
| Restaurar réplicas | `kubectl scale deploy/<nombre> -n pharmago --replicas=2` (la BD: 1) | Alguien escaló a 0 |
| Quitar un corte de red | `kubectl delete networkpolicy <nombre> -n pharmago` | Policy que niega tráfico |
| Borrar un pod trabado | `kubectl delete pod <pod> -n pharmago` | Pod en `Terminating`, `Evicted` o colgado |
| Volver a la versión anterior | `k8s/rollback.sh [deployment]` | Empezó después de un despliegue |
| Medir recuperación | `k8s/verify/measure-mttr.sh <deployment>` | Para demostrar el MTTR |

## 8. Comunicación

Los mensajes los escribe Comms y los dice o aprueba el IC. Van al registro del incidente y, en la defensa, se leen en voz alta a los docentes.

**Inicio**

```
[INCIDENTE] <SEV1|SEV2|SEV3> · <hh:mm:ss UTC>
Qué vemos: <señal con número, p. ej. "5xx del gateway en 35 % desde 14:02:10">
Impacto: <qué no puede hacer el usuario, p. ej. "no carga el listado de medicamentos">
Hipótesis inicial: <falla probable>
Roles: IC Martin · Ops Ignacio · Comms Franco
Próxima actualización: <hh:mm UTC>
```

**Actualización**

```
[ACTUALIZACIÓN] <SEV> · <hh:mm:ss UTC>
Estado: <investigando | mitigando | monitoreando>
Sabemos: <hechos nuevos>
Hicimos: <acción y resultado>
Próximo paso: <acción>  ·  Próxima actualización: <hh:mm UTC>
```

**Cierre**

```
[CERRADO] <SEV> · <hh:mm:ss UTC> · duración <mm:ss>
Causa: <qué falló>
Mitigación: <automática (mecanismo) | manual (acción)>
Validación: steady state OK (Deployments 2/2, 5 nodos Ready, 0 no-2xx en 20 s, sin alertas)
Seguimiento: postmortem en docs/incidentes/<archivo>.md
```

## 9. Riesgos aceptados

Se conocen de antemano. No son fallas del plan: el plan dice qué hacer cuando ocurren.

| Riesgo | Por qué se acepta | Qué hacer si ocurre |
|---|---|---|
| **Base de datos única** (D04) | Replicar SQL Server Express queda fuera del alcance. | La app lo detecta en segundos (readiness y breaker) y devuelve 503 rápido. Restaurar la BD (`kubectl scale deploy/pharmago-db --replicas=1`) y esperar: SQL Server tarda unos 45 s y el servicio vuelve solo unos 8 s después (C17). SEV1 mientras dure. |
| **Réplicas en el mismo nodo** (D03) | La separación por nodo de la letra no deja lugar para repartirlas. | Si cae un nodo entero, cae su microservicio. Ver "Nodos Ready" e intentar recuperar el nodo (`minikube node start <nodo>`). SEV1. |
| **Jaeger en memoria** (D34) | Simplicidad. | Si se reinicia, se pierden las trazas anteriores. Usar Kibana y Prometheus. |
| **Rate limit por réplica** (C16) | Contador en memoria de cada réplica del gateway. | El límite efectivo es el doble del configurado. Tenerlo en cuenta al leer los 429. |
| **Un solo Collector** | Simplicidad. | Si se cae, las métricas y trazas dejan de llegar (el panel queda en "No data"), pero la app sigue. `kubectl rollout restart deploy/otlp-collector -n pharmago`. |

## Fuentes

- D45: steady state, hipótesis falsable y blast radius ([Principles of Chaos](https://principlesofchaos.org/)).
- D46: roles IC, Ops y Comms y postmortem blameless ([Managing incidents](https://sre.google/sre-book/managing-incidents/), [Postmortem culture](https://sre.google/sre-book/postmortem-culture/)).
- Golden Signals: [Monitoring distributed systems](https://sre.google/sre-book/monitoring-distributed-systems/) (citado en D36).
- Mecanismos: D12 (probes), D13 (circuit breaker, reintentos y timeout), D41 (caos de red), D42 (desconexión), `docs/mttr.md`, `docs/resiliencia.md`, `docs/metricas.md` y `docs/trazas.md`.
