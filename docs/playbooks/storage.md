# Playbook: sobrecarga de storage (disco efímero del pod)

> Convención de los playbooks: lo que va entre comillas dobles es el título exacto de un dashboard o panel de Grafana, y los `pg-*` son los uid de las alertas (`k8s/configmaps/grafana-alerting.yaml`). Lo verifica `k8s/verify/check-playbooks.sh`.

## Síntoma

Un pod escribe en su sistema de archivos (capa escribible del contenedor, por ejemplo `/tmp`). Cada microservicio tiene `limits.ephemeral-storage: 512Mi`: si lo supera, el kubelet **desaloja** el pod (`Evicted`) y el Deployment crea otro. Mientras la otra réplica esté sana el usuario no ve errores.

## Alerta

- `pg-storage`: un pod del namespace usa más de 300 MiB de disco efímero durante 30 s.
- Si el desalojo y el reemplazo tardan más de 30 s: `pg-replicas`.

## Panel

- "PharmaGo - Infra" → "Filesystem por pod (ephemeral-storage usado)": el pod que crece.
- "PharmaGo - Infra" → "Réplicas deseadas y disponibles por Deployment": el hueco mientras se reemplaza un pod desalojado.
- "PharmaGo - Infra" → "Presión de memoria o disco por nodo": si el problema es del nodo y no de un pod.

## Severidad inicial

**SEV3** mientras crece sin llegar al límite (criterio del plan). Sube a **SEV2** si hay un pod desalojado y el Deployment no vuelve a 2/2 en 30 s, o si las dos réplicas crecen a la vez.

## Diagnóstico

```bash
# 1. ¿Hubo desalojo? (el pod queda en Failed con motivo Evicted)
kubectl get pods -n pharmago --field-selector=status.phase=Failed
kubectl get events -n pharmago --sort-by=.lastTimestamp | grep -E 'Evicted|ephemeral' | tail -5

# 2. Qué ocupa el disco dentro del pod sospechoso
kubectl exec -n pharmago <pod> -- du -sh /tmp /app 2>/dev/null
kubectl exec -n pharmago <pod> -- sh -c 'find / -xdev -size +50M 2>/dev/null | head'

# 3. Lo que ve el kubelet (dato que usa la métrica y el desalojo)
kubectl get --raw "/api/v1/nodes/<nodo>/proxy/stats/summary" | grep -A3 '"ephemeral-storage"' | head -20

# 4. ¿El usuario lo nota?
cd "Implementacion K8S/Codigo/chaos-engineering" && ./observar.sh 30 /api/roles /api/drug
```

## Mitigación automática esperada

- **Mecanismo:** el límite de `ephemeral-storage` hace que el kubelet desaloje al pod que se pasa (el disco no se llena para los demás). El Deployment crea un reemplazo con el disco limpio; la otra réplica atiende mientras tanto.
- **Tiempo medido (E4 de `chaos-engineering/EXPERIMENTOS.md`):**
  - Llenado brusco de 600 MB (E4): el kubelet desalojó el pod a los 47 s, el reemplazo quedó Ready 9 s después del desalojo y el usuario no vio errores (0 no-2xx en 210 requests). `pg-replicas` llegó a Pending unos segundos y no disparó. **`pg-storage` no disparó**: el kubelet calcula el uso de disco con retraso (15 s después de escribir 200 MB informaba 101 MiB) y el pod se fue antes de que el dato llegara a Prometheus. Ante un llenado brusco, la señal es el evento `Evicted`.
  - Llenado sostenido de 400 MB, bajo el límite (E4c): `pg-storage` pasó a Pending a los 44 s y a Firing a los 76 s, y volvió a Normal entre 47 y 89 s después de borrar el archivo. 0 no-2xx.

## Mitigación manual

1. Si hay un pod desalojado, confirmar que el Deployment ya está 2/2 (`kubectl get deploy -n pharmago`). El pod `Failed` no ocupa recursos, pero conviene borrarlo para no confundir:
   ```bash
   kubectl delete pod -n pharmago <pod-desalojado>
   ```
2. Si el pod sigue vivo y crece (sin llegar a 512Mi), identificar el archivo (diagnóstico 2). Si es ajeno a la app, borrarlo:
   ```bash
   kubectl exec -n pharmago <pod> -- rm -f <archivo>
   ```
3. Si no se puede identificar o la app escribe sin parar, reemplazar el pod (el disco del nuevo está limpio):
   ```bash
   kubectl delete pod -n pharmago <pod>
   ```

## Validación

```bash
kubectl get pods -n pharmago --field-selector=status.phase=Failed   # No resources found
cd "Implementacion K8S/Codigo/chaos-engineering" && ./steady-state.sh
```

`pg-storage` puede tardar hasta 1,5 min en volver a Normal después de borrar el archivo (E4c), por el retraso del kubelet. Repetir `steady-state.sh` hasta `RESULTADO: steady state OK`.

## Si no funciona

- Si los pods de reemplazo también se desalojan, la app escribe sin control: rollback (`docs/playbooks/rollout-fallido.md`).
- Si el panel "Presión de memoria o disco por nodo" muestra presión de disco en un nodo, el problema es del nodo (disco del host compartido por los 5 nodos de Minikube): liberar espacio en el disco del host y registrarlo; no es una falla de un pod.
- Si un pod queda en `Pending` por falta de disco, ver `kubectl describe pod -n pharmago <pod>`.

## Registro

Copiar `docs/plantillas/registro-incidente.md` a `docs/incidentes/<fecha>-storage.md`. Anotar: pod y archivo, si hubo desalojo (hora del evento `Evicted`), tiempo hasta 2/2, acción tomada y hora en que `pg-storage` volvió a Normal.
