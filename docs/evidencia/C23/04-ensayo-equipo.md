# Ensayo con los 3 integrantes (C23)

Estado: PENDIENTE. Se completa el día del ensayo.

- Fecha y hora UTC de inicio:
- Máquina: PC de
- IC: Martin Roux · Ops: Ignacio Aramburu · Comms: Franco
- Arranque: `./full-up.sh` (duración: ) o cluster ya levantado

## Los 6 tipos de falla

Ops lanza cada script desde `Implementacion K8S/Codigo/chaos-engineering/`, con el tráfico de fondo de `docs/runbook-defensa.md` (sección 5, paso 0). Comms anota las horas UTC. Los tiempos se cuentan desde el inicio de la falla.

| Falla | Comando | Inicio (UTC) | Alerta en Firing (s) | Causa identificada por el IC (s) | Recuperación: steady state OK (s) | Playbook usado | Observaciones |
|---|---|---|---|---|---|---|---|
| Requests | `./load-requests.sh 300 20` | | | | | `requests.md` | |
| CPU | `./cpu-spike.sh pharmago-api-gateway 120 4` | | | | | `cpu.md` | |
| Memoria | `./ram-spike.sh pharmago-pharmacy-service 250 150` | | | | | `memoria.md` | |
| Storage | `./volume-spike.sh pharmago-users-service 400 150` | | | | | `storage.md` | |
| Red | `./network-chaos.sh pharmago-users-service 60` | | | | | `red.md` | |
| Desconexión | `./disconnect.sh pharmago-pharmacy-service 60` | | | | | `desconexion.md` | |

Referencia del ensayo técnico (sección 7 del runbook): alertas en Firing entre 28 y 100 s según la falla.

## Fallo sorpresa

Un integrante elige y lanza una falla sin decir cuál (puede cambiar el microservicio, la duración o combinar dos). El resto la diagnostica con la sección 5 del runbook, sin mirar la terminal de quien la lanzó.

- Quién la eligió:
- Qué lanzó (se revela al final):
- Inicio (UTC):
- Primera señal vista y dónde:
- Pasos del protocolo seguidos:
- Diagnóstico del IC y a los cuántos segundos:
- ¿Acertó?:
- Mitigación ordenada y resultado:
- Steady state OK a los:

## Qué se aprendió

-
