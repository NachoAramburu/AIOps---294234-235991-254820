# Playbook: pod caído (borrado, reiniciado o en CrashLoop)

> Convención de los playbooks: lo que va entre comillas dobles es el título exacto de un dashboard o panel de Grafana, y los `pg-*` son los uid de las alertas (`k8s/configmaps/grafana-alerting.yaml`). Lo verifica `k8s/verify/check-playbooks.sh`.

## Síntoma

Una réplica de un microservicio desaparece (borrada, desalojada, su nodo la perdió) o su proceso muere y el kubelet la reinicia. Con 2 réplicas el usuario no lo nota: la otra atiende mientras el Deployment repone la que falta. Es un problema si el pod no vuelve (`CrashLoopBackOff`, `Pending`) o si caen las dos.

## Alerta

- `pg-replicas`: réplicas disponibles menos que las deseadas durante 30 s (un reemplazo normal tarda menos y no la dispara).
- `pg-restarts`: un contenedor se reinició (proceso caído, OOM de la app o liveness fallida).

## Panel

- "PharmaGo - Infra" → "Réplicas deseadas y disponibles por Deployment": el hueco entre deseadas y disponibles.
- "PharmaGo - Infra" → "Reinicios por contenedor": qué contenedor se reinició.
- "PharmaGo - Infra" → "Pods del namespace pharmago" (fila con CPU, memoria y filesystem por pod): si el pod nuevo arranca bien.

## Severidad inicial

**SEV3** si el pod volvió solo (`pg-restarts` aislado, `pg-replicas` que no llega a Firing). **SEV2** si `pg-replicas` llega a Firing (el reemplazo tarda más de 30 s). **SEV1** si un microservicio queda con 0 disponibles (seguir `docs/playbooks/desconexion.md`).

## Diagnóstico

```bash
# 1. Estado de los pods y reinicios
kubectl get pods -n pharmago -o wide
kubectl get deploy -n pharmago

# 2. Por qué se fue o se reinició
kubectl get events -n pharmago --sort-by=.lastTimestamp | tail -15
kubectl get pod -n pharmago <pod> -o jsonpath='{.status.containerStatuses[0].restartCount} {.status.containerStatuses[0].lastState.terminated.reason} {.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'

# 3. Logs del contenedor anterior (si se reinició) y del actual
kubectl logs -n pharmago <pod> --previous --tail=30
kubectl logs -n pharmago <pod> --tail=30

# 4. Si está Pending: por qué no se programa (affinity por node-type, recursos)
kubectl describe pod -n pharmago <pod> | tail -15
```

## Mitigación automática esperada

- **Mecanismo:** el Deployment repone la réplica que falta; el kubelet reinicia el contenedor cuyo proceso muere o cuya liveness falla (period 3 s, failureThreshold 2). La readiness (period 2 s) saca del Service al pod que no está listo y la otra réplica atiende; `preStop: sleep 5` evita cortar requests en vuelo y el gateway reintenta los GET (D12, D13, C08). El PodDisruptionBudget impide que un drenaje voluntario saque las 2 réplicas a la vez.
- **Tiempo medido (E7 de `chaos-engineering/EXPERIMENTOS.md`):** borrar un pod de users dio un MTTR de 8,6 s (falla → 2/2 Ready) con 0 no-2xx en 140 requests. `pg-replicas` llegó a Pending unos segundos y no disparó. `docs/mttr.md` tiene los demás casos: borrado de 4,1 a 6,7 s y proceso caído (`kill 1`) de 3,0 a 8,8 s, siempre con 0 no-2xx.

## Mitigación manual

1. Si el pod volvió solo y el Deployment está 2/2: no hacer nada más que registrar la causa (diagnóstico 2 y 3).
2. Si un pod quedó trabado en `Terminating` o `Unknown`:
   ```bash
   kubectl delete pod -n pharmago <pod> --grace-period=0 --force
   ```
3. Si está en `CrashLoopBackOff`, mirar `--previous` (diagnóstico 3). Si empezó después de un despliegue, volver atrás: `docs/playbooks/rollout-fallido.md`. Si no, reiniciar el Deployment para descartar un estado corrupto:
   ```bash
   kubectl rollout restart deploy/<deployment> -n pharmago
   ```
4. Si está `Pending` porque su nodo no está Ready, recuperar el nodo: `minikube node start <nodo>` (las réplicas de cada servicio viven en un solo nodo, D03).

## Validación

```bash
kubectl get deploy -n pharmago      # 2/2 en los 4 microservicios
cd "Implementacion K8S/Codigo/chaos-engineering" && ./steady-state.sh
```

`pg-restarts` mira los últimos 2 min: sigue en Firing hasta 2 min después de un reinicio aunque todo esté bien. Si es la única alerta y el resto del steady state da OK, el incidente está mitigado; se valida de nuevo cuando vuelve a Normal.

## Si no funciona

- Si los pods nuevos tampoco arrancan, el problema no es el pod sino la versión, la configuración o la base: `docs/playbooks/rollout-fallido.md` o `docs/playbooks/desconexion.md` (base de datos).
- Para medir y demostrar la recuperación: `k8s/verify/measure-mttr.sh <deployment>` (o `--crash`).

## Registro

Copiar `docs/plantillas/registro-incidente.md` a `docs/incidentes/<fecha>-pod-caido.md`. Anotar: pod, motivo (evento, `lastState.terminated.reason`, exit code), si el usuario vio errores, tiempo hasta 2/2 y acción tomada.
