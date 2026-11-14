# Postmortem: <título>

> **Blameless.** Se analiza el sistema, no a las personas: la pregunta es *qué permitió* que pasara y *qué lo hizo más difícil de detectar o mitigar*, no *quién se equivocó*. Se nombran roles, no culpables. Cada acción tiene un responsable y una fecha ([Postmortem culture](https://sre.google/sre-book/postmortem-culture/), D46).

| Campo | Valor |
|---|---|
| Fecha del incidente | <YYYY-MM-DD> |
| Severidad | <SEV1 · SEV2 · SEV3> |
| Duración | <desde la detección hasta el cierre, mm:ss> |
| Tiempo hasta detectar | <desde el inicio real hasta la alerta o la primera señal> |
| Tiempo hasta recuperar (MTTR) | <desde el inicio hasta el steady state> |
| Autores | <nombres> |
| Registro de origen | `docs/incidentes/<registro>.md` |
| Estado | <borrador · revisado> |

## Resumen

<Dos o tres frases: qué pasó, qué vio el usuario y cómo se resolvió.>

## Impacto

- **Usuarios:** <qué no pudieron hacer y durante cuánto tiempo>
- **Requests afectadas:** <cantidad o porcentaje de no-2xx, por código>
- **Componentes:** <microservicios, BD, nodos>
- **Datos:** <si hubo pérdida o inconsistencia; normalmente "ninguna">

## Línea de tiempo (UTC)

| Hora | Evento |
|---|---|
| <hh:mm:ss> | <inicio real de la falla> |
| <hh:mm:ss> | <primera señal o alerta> |
| <hh:mm:ss> | <declaración y severidad> |
| <hh:mm:ss> | <acciones y efectos> |
| <hh:mm:ss> | <recuperación y cierre> |

## Causa raíz y factores contribuyentes

- **Causa raíz:** <la condición técnica que disparó el incidente>
- **Factores contribuyentes:** <qué lo amplió, lo hizo más largo o más difícil de ver: diseño, configuración, falta de telemetría, umbrales>

## Detección

- ¿Qué alerta o panel lo mostró primero, y a los cuántos segundos?
- ¿Hubo una señal antes que no se miró?

## Qué funcionó

- <mecanismos automáticos, telemetría o procedimiento que ayudaron>

## Qué no funcionó o se puede mejorar

- <lo que tardó, confundió o faltó>

## Acciones

| # | Acción | Tipo (prevenir · detectar · mitigar) | Responsable | Fecha | Estado |
|---|---|---|---|---|---|
| 1 | | | | | |
| 2 | | | | | |

## Lecciones

<Qué aprendimos del sistema. Si fue un experimento de caos: ¿se confirmó o se refutó la hipótesis? (D45)>
