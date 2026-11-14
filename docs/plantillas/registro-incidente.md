# Registro de incidente

> Lo completa **Comms** en vivo. Copiá este archivo a `docs/incidentes/<YYYY-MM-DD>-<tema>.md` al declarar el incidente. Horas en UTC (`date -u +%T`). Frases cortas y con números: es la fuente del postmortem.

## Datos generales

| Campo | Valor |
|---|---|
| Incidente | <título corto, p. ej. "5xx en /api/drug"> |
| Fecha | <YYYY-MM-DD> |
| Detectado (UTC) | <hh:mm:ss> |
| Detectado por | <alerta uid / panel / persona> |
| Severidad inicial | <SEV1 · SEV2 · SEV3> (criterios en `docs/plan-incidentes.md` §3) |
| Severidad final | <SEV1 · SEV2 · SEV3> |
| Roles | IC: <nombre> · Ops: <nombre> · Comms: <nombre> |
| Playbook usado | `docs/playbooks/<archivo>.md` |
| Cerrado (UTC) | <hh:mm:ss> |
| Duración | <mm:ss> |

## Línea de tiempo

Una fila por hecho, decisión o acción. Si una acción no funcionó, se anota igual.

| Hora UTC | Señal (qué se vio, con número) | Severidad | Hipótesis | Acción (quién) | Resultado |
|---|---|---|---|---|---|
| <hh:mm:ss> | <p. ej. "pg-5xx Firing: 5xx gateway 32 %"> | SEV2 | <p. ej. "pharmacy sin BD"> | <p. ej. "Ops: kubectl get deploy -n pharmago"> | <p. ej. "pharmago-db 0/1"> |
| | | | | | |
| | | | | | |

## Validación de cierre (steady state)

- [ ] Los 4 microservicios en 2/2 y la BD en 1/1 (`kubectl get deploy -n pharmago`)
- [ ] Los 5 nodos Ready (`kubectl get nodes`)
- [ ] 0 respuestas no-2xx en 20 s de loop a 1 request/s
- [ ] Sin alertas *Firing* en Grafana
- [ ] `steady-state.sh` con salida 0 (cuando exista)

## Mensajes enviados

Pegá los mensajes de inicio, actualización y cierre (plantillas en `docs/plan-incidentes.md` §8).

## Para el postmortem

- Qué ayudó a detectar o mitigar:
- Qué estorbó o faltó:
- Preguntas abiertas:
