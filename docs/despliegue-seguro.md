# Despliegue seguro (C08 y C09)

La letra pide que el sistema pueda "reemplazar sus componentes garantizando 100% de disponibilidad" y que se documente y explique la técnica elegida.

## El problema

Antes de C08, actualizar un microservicio podía cortar requests:

- Kubernetes apagaba el pod viejo mientras todavía le llegaba tráfico. El aviso de sacarlo del Service tarda un instante en llegar al gateway y al Ingress, y en ese instante una request puede caer en un pod que se está apagando. C06 lo vio: un 502 justo en el segundo del borrado de un pod de pharmacy.
- Todas las imágenes eran `:latest`, así que no había forma de saber qué versión corría ni a cuál volver.

## La técnica elegida: RollingUpdate

Kubernetes reemplaza los pods de a uno: crea uno nuevo, espera a que esté listo y recién ahí apaga uno viejo.

| Parámetro | Valor | Qué aporta |
|---|---|---|
| `strategy.type` | `RollingUpdate` | Reemplazo gradual, de a un pod. |
| `maxSurge` | 1 | Durante el rollout puede existir un pod de más: primero se agrega el nuevo. |
| `maxUnavailable` | 0 | Nunca hay menos réplicas listas que las pedidas: la capacidad no baja. |
| `readinessProbe` (`/health/ready`, cada 2 s) | de C05 y C06 | El pod nuevo recibe tráfico solo cuando responde y llega a la base. |
| `minReadySeconds` | 5 | El pod nuevo tiene que seguir listo 5 s antes de que se apague uno viejo. Filtra los que arrancan y se caen enseguida. |
| `preStop: sleep 5` | 5 s | Al apagar un pod, espera 5 s antes de cerrar el proceso. En ese tiempo Kubernetes lo saca del Service y el gateway deja de mandarle tráfico. Es lo que corrige el 502 de C06. |
| `terminationGracePeriodSeconds` | 30 | Margen para el `preStop` y para que terminen las requests en vuelo. |
| `revisionHistoryLimit` | 5 | Se guardan las últimas 5 versiones para poder volver atrás. |
| PDB `minAvailable: 1` | de C06 | Un mantenimiento voluntario, como un `drain`, nunca deja un microservicio sin réplicas. |

Además, el gateway (C07) reintenta los GET ante errores de conexión y renueva sus conexiones cada 15 s: si a pesar de todo una request cae en un pod que se está yendo, la repite en la otra réplica.

## Versiones y vuelta atrás

- Cada imagen propia se etiqueta con el SHA corto del commit (`pharmago-api-gateway:3f2a1bc`), con el sufijo `-dirty` si se construyó con cambios sin commitear. Los manifiestos tienen `IMAGE_TAG` y `apply-k8s.sh` lo reemplaza.
- `k8s/deploy.sh <tag>` actualiza users, pharmacy, gateway y ui, uno por uno, y espera a que cada rollout termine. Si uno no termina en 180 s, lo vuelve a la versión anterior y corta, sin tocar los que siguen.
- `k8s/rollback.sh [deployment]` vuelve a la revisión anterior de uno o de los cuatro.
- `kubectl rollout history deployment/<nombre> -n pharmago` muestra qué tag tuvo cada revisión.

## Por qué RollingUpdate y no otra técnica

| Técnica | Costo de recursos | Complejidad | Velocidad del rollback | Encaja acá |
|---|---|---|---|---|
| **RollingUpdate** | 1 pod extra por microservicio, solo durante el rollout | Nativa de Kubernetes, sin piezas nuevas | Rápida: `rollout undo` repite el mismo proceso al revés | **Sí** |
| Blue/Green | El doble de pods durante el cambio | Dos Deployments por microservicio y un cambio de selector en el Service | Instantánea: se vuelve a apuntar al color viejo | No: los nodos tienen poca memoria y duplicar todo no entra |
| Canary | Pocos pods extra | Requiere repartir tráfico por porcentaje (Ingress con anotaciones o un service mesh) y métricas para decidir | Rápida | No: agrega infraestructura que la letra no pide |

RollingUpdate cumple el "100 % de disponibilidad" con lo que ya trae Kubernetes, sin duplicar recursos en un cluster de 5 nodos de 4 GB, y el rollback se apoya en el historial de revisiones del propio Deployment.

## Cómo se demuestra

- `k8s/verify/test-rollout.sh <tag_v2>`: mientras corre `deploy.sh` y después `rollback.sh`, un loop pide 1 request por segundo por el Ingress, rotando entre la UI, pharmacy y users. Falla si aparece alguna respuesta no-2xx. Va a 1 por segundo para no confundir un 429 del rate limit con una caída.
- `k8s/verify/measure-mttr.sh <deployment> [--crash]`: borra una réplica, o mata su proceso, y mide cuánto tarda en volver y si el usuario vio errores. Los resultados están en `docs/mttr.md`.

## Resultado

- **Verificado en local** (`docs/evidencia/C08/`): los cuatro Deployments tienen la estrategia, el `preStop`, `minReadySeconds`, el tag reemplazado y el límite de almacenamiento efímero. No queda ninguna imagen `:latest`. La lógica de `deploy.sh` y `rollback.sh` respeta el orden, vuelve atrás si un rollout se traba y valida los argumentos.
- **Pendiente en el cluster** (`docs/evidencia/C09/cluster-pendiente.txt`): correr `test-rollout.sh` y `measure-mttr.sh` con el cluster levantado. El criterio es 0 respuestas no-2xx en v1 → v2 → rollback, y menos de 15 s para volver a Ready al borrar un pod.
- **Medición previa, sin `preStop` (C06):** en 5 borrados de pod hubo 1 error (un 502 en el segundo del borrado) y la vuelta a Ready tardó entre 5,7 y 9,0 s.
