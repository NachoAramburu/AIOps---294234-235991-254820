# Registro de incidente

> Ensayo de C20: se siguió `docs/playbooks/memoria.md` paso a paso durante un experimento real. La falla la inyectó un script (`ram-spike.sh`, como haría el script de los docentes) y la respuesta la ejecutó la IA (Claude Code) en el rol de Ops, con los comandos exactos del playbook. IC y Comms no participaron: las decisiones que le tocan al IC se tomaron según lo que dice el playbook y quedan anotadas como tales. Salidas completas: `docs/evidencia/C20/02-ensayo-playbook-memoria.txt` y `02b-ensayo-accion-corregida.txt`.

## Datos generales

| Campo | Valor |
|---|---|
| Incidente | Memoria de un pod de pharmacy al 94 % de su límite |
| Fecha | 2026-11-14 |
| Detectado (UTC) | 22:06:26 |
| Detectado por | `pg-memory` (Firing) |
| Severidad inicial | SEV2 (memoria > 85 % del límite durante 30 s, `docs/plan-incidentes.md` §3) |
| Severidad final | SEV3 (sin impacto en el usuario en ningún momento) |
| Roles | IC: según playbook (ensayo) · Ops: Claude Code · Comms: no participó (registro automático con hora) |
| Playbook usado | `docs/playbooks/memoria.md` |
| Cerrado (UTC) | 22:08:15 |
| Duración | 01:49 desde la detección (02:48 desde la inyección, 22:05:27) |

## Línea de tiempo

| Hora UTC | Señal (qué se vio, con número) | Severidad | Hipótesis | Acción (quién) | Resultado |
|---|---|---|---|---|---|
| 22:05:04 | Steady state OK (exit 0) | — | — | Ops: `./steady-state.sh` (Prepare) | Todo sano |
| 22:05:27 | (falla inyectada, Ops no sabe cuál) | — | — | Script: `ram-spike.sh pharmago-pharmacy-service 250 300` | — |
| 22:05:54 | `pg-memory` Pending | — | — | Ops observa | — |
| 22:06:26 | `pg-memory` Firing, a los 59 s de la falla | SEV2 | Sobrecarga de memoria | IC (playbook): SEV2, playbook `memoria.md` | — |
| 22:06:26 | Panel "Memoria del pod contra su límite": `pharmago-pharmacy-service-...-l6plc` en 0,937 | SEV2 | Un solo pod de pharmacy | Ops: query del panel en Prometheus | Blanco identificado |
| 22:06:26 | `kubectl top`: l6plc 359Mi (la otra réplica 85Mi) | SEV2 | — | Ops: diagnóstico 1 | Confirma el pod |
| 22:06:26 | `/proc`: PID 75 `sh -s chaos_ram 250 300` con 273 MB; `dotnet` (PID 1) 106 MB | SEV2 | Proceso ajeno a la app | Ops: diagnóstico 2 | Causa: proceso ajeno |
| 22:06:27 | `memory.events`: `oom_kill 0`; reinicios 0 | SEV2 | Todavía no llegó al límite | Ops: diagnóstico 3 y 4 | Sin OOM ni reinicio |
| 22:06:27 | 1 request/s durante 20 s: 0 no-2xx | SEV3 | Sin impacto visible | Ops: diagnóstico 5 (`observar.sh`) | Baja a SEV3 |
| 22:06:49 | — | SEV3 | — | Ops: mitigación manual paso 2, `kubectl exec ... -- kill 75` | **Falló**: exit 127, `kill` no existe como binario en la imagen |
| 22:07:25 | — | SEV3 | `kill` es un builtin de la shell | Ops: `kubectl exec ... -- sh -c 'kill 75'` | OK: queda solo `dotnet` con 99 MB |
| 22:07:53 | `pg-memory` vuelve a Normal (28 s después del kill efectivo) | SEV3 | — | Ops observa | Alerta resuelta |
| 22:08:15 | Steady state OK (exit 0) | SEV3 | — | Ops: `./steady-state.sh` | Cierre |

## Validación de cierre (steady state)

- [x] Los 4 microservicios en 2/2 y la BD en 1/1 (`kubectl get deploy -n pharmago`)
- [x] Los 5 nodos Ready (`kubectl get nodes`)
- [x] 0 respuestas no-2xx en 20 s de loop a 1 request/s
- [x] Sin alertas *Firing* en Grafana (Normal 111, Pending 0)
- [x] `steady-state.sh` con salida 0

## Mensajes enviados

No se enviaron (ensayo sin Comms). Con las plantillas de `docs/plan-incidentes.md` §8 habrían sido:

```
[INCIDENTE] SEV2 · 22:06:26 UTC
Qué vemos: pg-memory Firing; pod pharmacy l6plc al 94 % de su límite de memoria
Impacto: ninguno visible (0 no-2xx)
Hipótesis inicial: sobrecarga de memoria en un pod de pharmacy
Roles: IC Martin · Ops Ignacio · Comms Franco
Próxima actualización: 22:08 UTC

[CERRADO] SEV3 · 22:08:15 UTC · duración 01:49
Causa: proceso ajeno a la app (PID 75, 273 MB) dentro del pod de pharmacy
Mitigación: manual (kill del proceso)
Validación: steady state OK (Deployments 2/2, 5 nodos Ready, 0 no-2xx en 20 s, sin alertas)
Seguimiento: corregir el comando kill en los playbooks de memoria y CPU
```

## Para el postmortem

- **Qué ayudó a detectar o mitigar:** la alerta disparó en 59 s, igual que en E3b; el panel y `kubectl top` señalaron el mismo pod; el comando de `/proc` del playbook identificó el proceso sin herramientas extra; `observar.sh` permitió bajar a SEV3 con un dato (0 no-2xx).
- **Qué estorbó o faltó:** el comando de mitigación del playbook (`kubectl exec <pod> -- kill <pid>`) no funcionaba: las imágenes no traen el binario `kill`. Costó 36 s darse cuenta y corregirlo. **Corregido** en `docs/playbooks/memoria.md` y `docs/playbooks/cpu.md` (`sh -c 'kill <pid>'`).
- **Preguntas abiertas:** ensayar el mismo playbook con los 3 roles (pendiente de los integrantes; lo pide la guía antes de escribir «revisado» y es parte de C23).
