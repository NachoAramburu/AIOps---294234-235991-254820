# Chaos Engineering

Scripts para inyectar los 6 tipos de falla que pide la letra: requests, CPU, memoria, storage, red y desconexión de componentes internos.

## Reglas comunes

- Corren desde **Git Bash**, en cualquier directorio, contra el contexto `minikube` y el namespace `pharmago`. Si el contexto de `kubectl` es otro, abortan.
- Validan los argumentos y, si faltan, muestran el uso.
- Imprimen `[inicio]` y `[fin]` en UTC, para ubicar el experimento en Grafana.
- **Dejan todo como estaba**, también si se cortan con Ctrl+C (`trap`): matan los procesos que lanzaron dentro del pod, borran archivos y NetworkPolicies, y restauran las réplicas.
- Las funciones comunes están en `lib.sh`.
- `load-requests.sh` entra por `http://127.0.0.1`, así que necesita `minikube tunnel` abierto en PowerShell como administrador.

## Scripts

| Script | Falla | Uso | Qué se espera ver |
|---|---|---|---|
| `load-requests.sh` | Inyección de requests | `./load-requests.sh <cantidad> <concurrencia> [url]` | Por defecto, POST a `/api/login` con credenciales inválidas. Imprime el conteo por código HTTP. El rate limit del gateway corta con **429** |
| `cpu-spike.sh` | Sobrecarga de CPU | `./cpu-spike.sh <deployment> <segundos> [hilos=4]` | Loops con `timeout` dentro de un pod: terminan solos y no quedan vivos. El contenedor llega a su `limits.cpu` y se ve throttling |
| `ram-spike.sh` | Sobrecarga de memoria | `./ram-spike.sh <deployment> <MB> <segundos>` | Retiene memoria real en variables de shell, de a bloques de 16 MB (no en `/dev/shm`; D57). La memoria del pod sube en Grafana o Prometheus y baja al terminar. Con un pod de ~80Mi y límite de 384Mi, 250 MB lo dejan en ~89 % y disparan `pg-memory` |
| `volume-spike.sh` | Sobrecarga de storage | `./volume-spike.sh <deployment> <MB> <segundos>` | Escribe en `/tmp/chaos_fill` y lo borra al final. Con más de 512 MB (límite de `ephemeral-storage`), el kubelet desaloja el pod, el Deployment crea otro y el script borra el pod terminado |
| `network-chaos.sh` | Interrupción de tráfico de red | `./network-chaos.sh <deployment> <segundos>` | Aplica la NetworkPolicy `chaos-deny-<deployment>`, que niega todo el tráfico de entrada y salida (la hace cumplir Calico). La borra al final. Si ya hay una policy `chaos-`, aborta |
| `disconnect.sh` | Desconexión de un componente interno | `./disconnect.sh <deployment> <segundos>` | Escala a 0 y restaura las réplicas originales con `rollout status`. Solo acepta `pharmago-db`, `pharmago-users-service`, `pharmago-pharmacy-service` y `pharmago-api-gateway` |
| `run-all.sh` | Los 6 en secuencia | `./run-all.sh [--segundos N]` (por defecto 30) | Entre cada experimento espera a que todos los Deployments vuelvan a Ready. Al final imprime una tabla con tipo, inicio, fin y estado final |
| `steady-state.sh` | (verificación) | `./steady-state.sh [segundos=20]` | Antes y después de cada experimento: Deployments 2/2 (BD 1/1), nodos Ready, 0 no-2xx en un loop a 1 request/s y ninguna alerta de Grafana en Firing. Sale con 0 solo si todo está bien (C18) |
| `observar.sh` | (observación) | `./observar.sh <segundos> [ruta ...]` | Durante un experimento: 1 request/s por el Ingress con hora UTC y el estado de las alertas cada 5 s; al final, conteo por código y a los cuántos segundos pasó cada alerta a Pending y a Firing (C18) |

## Ejemplos

```bash
cd "Implementacion K8S/Codigo/chaos-engineering"
./load-requests.sh 300 20
./cpu-spike.sh pharmago-api-gateway 60 4
./ram-spike.sh pharmago-pharmacy-service 150 60
./volume-spike.sh pharmago-users-service 200 60
./network-chaos.sh pharmago-users-service 45
./disconnect.sh pharmago-db 45
./run-all.sh --segundos 30
```

## Experimentos

Los experimentos con hipótesis, métrica, criterio de éxito y resultados medidos están en [`EXPERIMENTOS.md`](EXPERIMENTOS.md) (C18). Los playbooks de cada tipo de falla, en `docs/playbooks/` (C20).

## Qué observar

- **Grafana**, dashboard "PharmaGo - Infra": paneles de CPU y memoria por pod, con la ventana entre `[inicio]` y `[fin]`.
- `kubectl get pods -n pharmago -o wide -w`: reinicios, desalojos y pods nuevos.
- `kubectl logs -n pharmago -l app=pharmago-api-gateway | grep circuit_breaker`: transiciones del circuit breaker (open, half-open, closed).
- Un loop de 1 request por segundo por el Ingress (`/api/drug` para pharmacy, `/api/roles` para users, `/` para la UI) muestra lo que ve el usuario. A más de 1 por segundo aparecen 429 del rate limit.

## Comportamientos para tener en cuenta

- **Memoria por encima del límite:** el OOM killer mata el proceso más grande del contenedor, que es el del experimento. La app sigue viva y el pod no se reinicia, porque el runtime del cluster no activa `memory.oom.group`.
- **Red:** Calico deja seguir las conexiones ya establecidas. El corte se nota cuando el gateway abre conexiones nuevas, en pocos segundos.
- **Rate limit:** es por réplica del gateway (en memoria). Con 2 réplicas, el límite efectivo es el doble.
