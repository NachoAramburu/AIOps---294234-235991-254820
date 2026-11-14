# Postmortem: base de datos desconectada (experimento de caos de C17)

> **Ejemplo completado con datos reales.** El incidente es el experimento `./disconnect.sh pharmago-db 45` del bloque B2, medido con un loop de 1 GET/s a `/api/drug`. La evidencia está en `docs/evidencia/C17/03-disconnect-db.txt`. Todavía no existe `chaos-engineering/EXPERIMENTOS.md` (bloque B7): cuando esté, este postmortem se puede vincular al experimento de desconexión de ahí. Fue un experimento planificado, no un incidente con roles: las secciones de detección y acciones dicen cómo se vería con el plan de `docs/plan-incidentes.md`.

| Campo | Valor |
|---|---|
| Fecha del incidente | 2026-11-14 |
| Severidad | SEV1 (BD con 0 réplicas; el 100 % de `/api/drug` con 5xx durante más de 1 min) |
| Duración | 95 s con errores para el usuario (04:48:44 a 04:50:19) |
| Tiempo hasta detectar | 5 s hasta el primer error visible (no había alertas todavía: llegan en B6) |
| Tiempo hasta recuperar (MTTR) | 112 s desde la falla hasta pharmacy 2/2 Ready. 53 s desde que se restauró la BD hasta el primer 200 |
| Autores | Equipo (datos del experimento de Martin Roux; redacción en C19) |
| Registro de origen | `docs/evidencia/C17/03-disconnect-db.txt` |
| Estado | borrador |

## Resumen

La base de datos se escaló a 0 réplicas durante 45 s. A los 5 s, pharmacy empezó a devolver 500. A los 7 s sus dos pods salieron de Ready, y desde los 17 s el gateway respondió 503 rápido, con el circuit breaker de `pharmacy-cluster` alternando entre abierto y medio abierto. Al restaurar la BD, SQL Server tardó 45 s en arrancar y el servicio volvió solo 8 s después, sin ninguna acción manual.

## Impacto

- **Usuarios:** no pudieron listar medicamentos (`/api/drug`) durante 95 s.
- **Requests afectadas:** las 64 requests entre 04:48:44 y 04:50:18 fallaron (100 %): 6 × 500, 4 × 502 y 54 × 503 (49 mientras corría el script y 5 después de que terminó).
- **Componentes:** `pharmago-db` (0/1) y `pharmago-pharmacy-service` (0/2 Ready). users no recibió tráfico en la prueba, pero también depende de la BD.
- **Datos:** ninguna pérdida. Solo hubo lecturas (`GET`), y el volumen persistente de SQL Server se mantuvo.

## Línea de tiempo (UTC)

| Hora | Evento |
|---|---|
| 04:48:39 | `disconnect.sh` escala `pharmago-db` a 0 réplicas (inicio real de la falla) |
| 04:48:44 | Primer 500 en `/api/drug`: pharmacy no llega a la BD |
| 04:48:46 | Los 2 pods de pharmacy salen de Ready: `/health/ready` consulta la BD (C05, readiness cada 2 s con 2 fallas, D12) |
| 04:48:48 a 04:48:54 | 500 y 502 mezclados: el gateway reintenta los GET y algunas conexiones se cortan |
| 04:48:56 | Primeros 503: sin pods Ready detrás del gateway y circuito de `pharmacy-cluster` abierto |
| 04:49:03 a 04:50:17 | Todo 503. En los logs del gateway, el circuito alterna "open for 5s" y "half-open" (D13) |
| 04:49:26 | `disconnect.sh` restaura `pharmago-db` a 1 réplica |
| 04:50:11 | `pharmago-db` 1/1 Ready: SQL Server tardó 45 s en arrancar |
| 04:50:18 | Primer pod de pharmacy Ready otra vez |
| 04:50:19 | Primer 200: el circuito pasa a "closed" |
| 04:50:31 | pharmacy 2/2 Ready: steady state recuperado |

## Causa raíz y factores contribuyentes

- **Causa raíz:** la única réplica de la base de datos dejó de estar disponible. Es el punto único de falla aceptado en D04: ningún mecanismo de la app puede reemplazarla.
- **Factores contribuyentes:**
  - El arranque de SQL Server (45 s) duplica el tiempo sin servicio: la caída duró 45 s y la recuperación de la BD otros 45 s.
  - Los primeros 10 s el usuario vio 500 y 502, no 503. Hasta que la readiness sacó a los pods y el breaker juntó 8 requests fallidas en 10 s, el gateway seguía mandando tráfico a pharmacy (D13: el breaker abre con el 50 % de un mínimo de 8 requests en 10 s; a 1 request/s tarda en juntarlas).

## Detección

- **Hoy:** el error se vio a los 5 s en el loop. En el gateway, los logs `circuit_breaker cluster=pharmacy-cluster state=open` lo confirman.
- **Con el plan:** deberían disparar `pg-5xx` (5xx > 5 % durante 30 s), `pg-breaker` (`pharmago_circuit_breaker_state == 1`) y `pg-replicas` (`pharmago-db` 0 de 1), las tres de B6. En Infra se vería "Réplicas deseadas y disponibles por Deployment" con `pharmago-db` en 0. El triage de `docs/plan-incidentes.md` §7 lleva a la fila "500 en pharmacy y users a la vez".

## Qué funcionó

- **Readiness con chequeo de BD (C05):** sacó a pharmacy del balanceo en unos 7 s.
- **Circuit breaker (C07):** con el servicio caído, el usuario recibió 503 rápido en vez de esperar timeouts. El ciclo abierto → medio abierto cada 5 s fue probando hasta que la BD volvió.
- **Recuperación automática:** después de restaurar la BD no hizo falta reiniciar nada. pharmacy volvió sola y el circuito se cerró.
- **Telemetría para reconstruir lo que pasó:** el loop con hora, el Ready de los pods y los logs del breaker alcanzaron para armar esta línea de tiempo al segundo.

## Qué no funcionó o se puede mejorar

- No había alertas: la detección dependió de mirar el loop (se resuelve en B6).
- Mezcla de 500, 502 y 503 al principio: puede confundir el diagnóstico si no se sabe que es la transición antes de que abra el breaker.
- El tiempo de recuperación lo domina SQL Server, y no hay forma de acortarlo sin una segunda réplica (fuera del alcance, D04).

## Acciones

| # | Acción | Tipo | Responsable | Fecha | Estado |
|---|---|---|---|---|---|
| 1 | Provisionar `pg-5xx`, `pg-breaker` y `pg-replicas` y verificar que disparen con este mismo experimento | Detectar | Martin Roux (B6) | 2026-11-15 | Pendiente |
| 2 | Playbook `docs/playbooks/desconexion.md` con el tiempo esperado de recuperación de la BD (unos 45 s + 8 s) para no actuar antes de tiempo | Mitigar | Ignacio Aramburu (B7) | 2026-11-15 | Pendiente |
| 3 | Repetir el experimento en `EXPERIMENTOS.md` con hipótesis y `steady-state.sh` antes y después | Detectar | Ignacio Aramburu (B7) | 2026-11-15 | Pendiente |
| 4 | Documentar en el runbook de defensa que la caída de la BD es SEV1 esperada y cuánto tarda en volver | Mitigar | Martin Roux (B8) | 2026-11-16 | Pendiente |

## Lecciones

- La hipótesis implícita, que sin BD el sistema degrada de forma controlada y vuelve solo, **se confirmó**. No colgó al usuario, no hubo reinicios en cascada y no hizo falta intervenir.
- El límite del sistema está en la BD única, no en la app. En la defensa, si se cae la BD, lo correcto es restaurarla y **esperar** unos 50 s, no reiniciar los microservicios: un reinicio no acelera nada y suma ruido.
