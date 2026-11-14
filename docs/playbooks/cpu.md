# Playbook: sobrecarga de CPU

> Convención de los playbooks: lo que va entre comillas dobles es el título exacto de un dashboard o panel de Grafana, y los `pg-*` son los uid de las alertas (`k8s/configmaps/grafana-alerting.yaml`). Lo verifica `k8s/verify/check-playbooks.sh`.

## Síntoma

Un pod usa todo el CPU que le permite su límite (`limits.cpu`: 500m en gateway, users y pharmacy; 200m en la UI). El kernel lo frena (throttling). La latencia puede subir, pero mientras la otra réplica esté sana el usuario no ve errores.

## Alerta

- `pg-cpu`: un pod del namespace por encima del 80 % de su límite de CPU durante 30 s.
- Si la latencia llega a afectar al usuario: `pg-latency` (P95 del gateway > 1000 ms durante 1 min) o `pg-latency-anomaly`.

## Panel

- "PharmaGo - Infra" → "CPU del contenedor contra su límite": el contenedor que está cerca del 100 % es el blanco (la línea roja es el 80 % de la alerta).
- "PharmaGo - Infra" → "CPU por pod (núcleos)": cuántos núcleos usa (el límite de 500m es 0,5).
- "PharmaGo - Infra" → "CPU por nodo (núcleos en uso)": si el nodo entero está cargado.
- "PharmaGo - Overview" → "Latencia Promedio por Endpoint": si el usuario ya lo nota.

## Severidad inicial

**SEV2** (criterio del plan: CPU > 80 % del límite durante 30 s). Sube a **SEV1** si además hay 5xx en el gateway (`pg-5xx`). Baja a **SEV3** si la latencia sigue normal y la causa es conocida (por ejemplo, un proceso de prueba).

## Diagnóstico

```bash
# 1. Qué pod y cuánto (el panel lo muestra; desde la terminal)
kubectl top pod -n pharmago --sort-by=cpu | head -8

# 2. Qué proceso consume dentro del pod (las imágenes no traen top: se lee /proc)
kubectl exec -n pharmago <pod> -- sh -c 'for p in /proc/[0-9]*; do printf "%s %s\n" "${p#/proc/}" "$(tr "\0" " " < $p/cmdline)"; done' | head -20

# 3. ¿El usuario lo nota? Latencia y errores a 1 request/s
cd "Implementacion K8S/Codigo/chaos-engineering" && ./observar.sh 30 /api/drug /api/roles

# 4. ¿La readiness lo sacó del balanceo?
kubectl get pods -n pharmago -o wide | grep <deployment>
kubectl get events -n pharmago --sort-by=.lastTimestamp | grep -i unhealthy | tail -5
```

## Mitigación automática esperada

- **Mecanismo:** el límite de CPU contiene el problema dentro del pod (no le roba CPU al resto del nodo). Si el pod deja de responder a la readiness (period 2 s, failureThreshold 2, D12), sale del Service y atiende la otra réplica. El gateway corta cada intento a los 3 s y reintenta los GET (D13).
- **Tiempo medido (E2 de `chaos-engineering/EXPERIMENTOS.md`):** con 4 hilos durante 120 s en un pod del gateway, el pod llegó a 0,5 núcleos (100 % del límite). `pg-cpu` pasó a Pending a los 33 s y a Firing a los 70 s, y volvió a Normal 30 s después de que terminó la carga. El usuario no lo notó: 0 no-2xx en 200 requests y P95 de 60 ms (máximo 186 ms). La readiness no llegó a sacar al pod.
- Ningún mecanismo **termina** el proceso que consume CPU: el throttling solo lo contiene.

## Mitigación manual

1. Identificar el pod (diagnóstico 1) y si el consumo es de la app o de un proceso ajeno (diagnóstico 2).
2. Si es un proceso ajeno a la app (por ejemplo `sh`, `yes`, `timeout`), matarlo sin reiniciar el pod:
   ```bash
   kubectl exec -n pharmago <pod> -- sh -c 'kill <pid>'    # kill es de la shell: la imagen no trae el binario
   ```
3. Si es la app o no se puede identificar, reemplazar el pod (la otra réplica atiende mientras tanto; `maxUnavailable: 0` y PDB):
   ```bash
   kubectl delete pod -n pharmago <pod>
   ```
4. Si las dos réplicas están saturadas por carga real, escalar para repartir:
   ```bash
   kubectl scale deploy/<deployment> -n pharmago --replicas=3
   ```
   y volver a 2 al cerrar.

## Validación

```bash
kubectl top pod -n pharmago --sort-by=cpu | head -5    # el pod volvió a unos pocos milicores
cd "Implementacion K8S/Codigo/chaos-engineering" && ./steady-state.sh
```

`pg-cpu` tarda unos 30 s en volver a Normal después de que baja el consumo (E2). Repetir `steady-state.sh` hasta `RESULTADO: steady state OK`.

## Si no funciona

- Si al borrar el pod el nuevo vuelve a saturarse, la carga es real: escalar (paso 4) y revisar en "PharmaGo - Overview" → "Peticiones por Segundo por Endpoint" si hay una ráfaga (seguir `docs/playbooks/requests.md`).
- Si el que satura es el nodo entero ("CPU por nodo (núcleos en uso)") y no un pod, revisar con `kubectl top pod -A --sort-by=cpu` qué más corre en ese nodo.
- Si empezó después de un despliegue, volver a la versión anterior: `docs/playbooks/rollout-fallido.md`.

## Registro

Copiar `docs/plantillas/registro-incidente.md` a `docs/incidentes/<fecha>-cpu.md`. Anotar: pod y proceso, pico de CPU contra el límite, si hubo impacto en latencia o errores, acción tomada y hora en que `pg-cpu` volvió a Normal.
