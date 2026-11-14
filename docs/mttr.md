# MTTR: tiempo hasta recuperar el servicio (C09)

La primera actividad de la letra es "reducir el MTTR de un conjunto de fallos en tiempo de ejecución al mínimo posible, idealmente al orden de pocos segundos".

**Cómo se mide.** El MTTR va desde que se inyecta la falla hasta que el Deployment vuelve a tener todas sus réplicas Ready. Al mismo tiempo, un loop de 1 request por segundo cuenta las respuestas que no son 2xx: eso es lo que ve el usuario. Lo hace `k8s/verify/measure-mttr.sh`. La resolución es de 1 s, la del loop.

## Resultados

| Falla | MTTR medido | Errores vistos por el usuario | Mecanismo que lo explica | De dónde sale |
|---|---|---|---|---|
| Borrado de un pod del gateway | 5,7 s | 0 de 40 | 2 réplicas: la otra atiende. Readiness cada 2 s. Startup sin espera inicial | C06, `docs/evidencia/C06/05` |
| Borrado de un pod de users | 7,2 a 7,3 s | 0 de 40 | Igual que arriba | C06, `docs/evidencia/C06/06` y `08` |
| Borrado de un pod de pharmacy | 8,0 a 9,0 s | 1 de 80 (un 502) | Igual que arriba; el 502 se explica abajo | C06, `docs/evidencia/C06/07` y `09` |
| Borrado del pod de la UI con **1** réplica | unos 14 s | 14 de 40 | Sin otra réplica, el usuario espera a que arranque el pod nuevo. Es la línea de base | C04-verificación, `docs/evidencia/C04/11` |
| Base de datos inaccesible | `/health/ready` responde 503 en unos 3,9 s | Sí, mientras dure la caída | La readiness saca de servicio a los pods que no llegan a la base; el breaker del gateway corta las requests al instante | C05 (local) |
| Servicio caído detrás del gateway | No reemplaza al servicio: el circuito abre cuando fallan al menos la mitad de 8 o más requests en 10 s, y prueba de nuevo cada 5 s | 503 inmediato con `Retry-After`, en vez de esperas largas | Circuit breaker de C07 | C07, `docs/evidencia/C07/01` (local) |
| Borrado de un pod del gateway, **con** `preStop` y reintento de GET | 4,1 s | 0 de 40 | `preStop` de C08 y reintento de C07; la otra réplica atiende | B1-verificación, `docs/evidencia/C09/03-cluster-mttr.txt` |
| Borrado de un pod de users, ídem | 5,4 s | 0 de 40 | Ídem | ídem |
| Borrado de un pod de pharmacy, ídem | 6,7 s | 0 de 40 | Ídem. El 502 de C06 no se repitió | ídem |
| Borrado de un pod de la UI con 2 réplicas | 5,4 s | 0 de 40 | 2 réplicas de C06 y `preStop` de C08 (contra 14 s y 14 errores con 1 réplica) | ídem |
| Proceso que muere en el gateway (`--crash`, `kill 1`) | 4,4 s | 0 de 40 | El kubelet reinicia el contenedor; la otra réplica atiende | ídem |
| Proceso que muere en users (`--crash`) | 8,8 s | 0 de 40 | Ídem | ídem |
| Proceso que muere en pharmacy (`--crash`) | 7,4 s | 0 de 40 | Ídem | ídem |
| Proceso que muere en la UI (`--crash`) | 3,0 s | 0 de 40 | Ídem (nginx arranca en menos de 1 s) | ídem |

Medido el 2026-11-14 en el cluster de 5 nodos de la PC de Martin (imágenes `be11702`), con `minikube tunnel`. En los 8 casos: 0 respuestas no-2xx y MTTR menor a 15 s. La resolución es de 1 s.

## El error de C06, explicado

En la quinta prueba de borrado de pod de C06 apareció un 502 justo en el segundo del borrado. Cuando Kubernetes decide apagar un pod pasan dos cosas al mismo tiempo: le manda la señal de apagado y empieza a sacarlo del Service. La segunda tarda un instante en llegar al gateway, y si en ese instante el gateway le manda una request a un pod que ya se está cerrando, la conexión falla y YARP responde 502.

Dos cambios de este bloque lo corrigen:

1. **`preStop: sleep 5` (C08):** el pod espera 5 s antes de cerrar el proceso. Para entonces ya salió del Service y no le llega tráfico nuevo.
2. **Reintento de GET ante errores de conexión (C07):** si igual se pierde una conexión, el gateway repite la request y la toma la otra réplica. Además renueva sus conexiones cada 15 s, así no queda pegado a un pod que se fue.

## Qué limita bajarlo más

- **Arranque del proceso .NET:** el pod nuevo tarda unos segundos en responder. Con 2 réplicas no lo ve el usuario, pero sí define el MTTR medido.
- **Período de las probes:** readiness cada 2 s, con 2 fallas para sacar un pod. Bajarlo más genera falsos positivos cuando hay carga de CPU.
- **`minReadySeconds: 5`:** durante un rollout, cada pod nuevo espera 5 s a propósito. Hace el rollout más lento pero más seguro; no afecta al borrado de un pod.
- **La base de datos es una sola** (decisión D04): si se cae, ningún mecanismo de la app la reemplaza. El sistema la detecta en segundos y vuelve solo cuando la base vuelve.
