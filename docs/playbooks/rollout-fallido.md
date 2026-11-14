# Playbook: rollout fallido (versión nueva que no arranca o falla)

> Convención de los playbooks: lo que va entre comillas dobles es el título exacto de un dashboard o panel de Grafana, y los `pg-*` son los uid de las alertas (`k8s/configmaps/grafana-alerting.yaml`). Lo verifica `k8s/verify/check-playbooks.sh`.

## Síntoma

Después de un despliegue (`k8s/deploy.sh <tag>` o un `kubectl set image`), el pod nuevo no queda Ready: imagen inexistente (`ErrImageNeverPull`), proceso que muere al arrancar (`CrashLoopBackOff`) o readiness que nunca pasa. Con `maxUnavailable: 0` las réplicas viejas **siguen atendiendo** y el rollout queda trabado a mitad de camino. Si la versión nueva arranca pero responde mal, aparecen errores en los endpoints de ese servicio.

## Alerta

Un rollout trabado **no dispara ninguna alerta por sí mismo**: las réplicas disponibles siguen siendo las deseadas (E8). Según cómo falle la versión nueva:

- `pg-restarts`: si el pod nuevo arranca y se cae (`CrashLoopBackOff`).
- `pg-5xx` o `pg-latency`: si la versión nueva queda Ready pero responde mal o lento.
- `pg-replicas`: solo si además se pierde una réplica vieja.

La señal principal es que `deploy.sh` (o `kubectl rollout status`) no termina en 180 s.

## Panel

- "PharmaGo - Infra" → "Réplicas deseadas y disponibles por Deployment": en un rollout trabado sigue 2/2; no muestra el problema, sirve para confirmar que el usuario no está afectado.
- "PharmaGo - Infra" → "Reinicios por contenedor": el pod nuevo reiniciándose.
- "PharmaGo - Overview" → "Tasa de Error por Endpoint (%)": si la versión nueva atiende y falla.

## Severidad inicial

**SEV3** si el rollout está trabado y las réplicas viejas atienden sin errores (sin impacto). **SEV2** si la versión nueva atiende con errores o latencia. **SEV1** si el servicio quedó sin réplicas disponibles.

## Diagnóstico

```bash
# 1. ¿El rollout terminó? (no termina = trabado)
kubectl rollout status deploy/<deployment> -n pharmago --timeout=10s

# 2. Qué versión corre cada pod y en qué estado está el nuevo
kubectl get pods -n pharmago -l app=<deployment> -o custom-columns=POD:.metadata.name,ESTADO:.status.containerStatuses[0].state,IMAGEN:.spec.containers[0].image
kubectl get pods -n pharmago -l app=<deployment>

# 3. Por qué no arranca
kubectl get events -n pharmago --sort-by=.lastTimestamp | grep -E 'ErrImage|BackOff|Unhealthy|Failed' | tail -5
kubectl logs -n pharmago <pod-nuevo> --previous --tail=30

# 4. Historial de revisiones (CHANGE-CAUSE: «deploy.sh <tag>» o «rollback.sh, vuelve a <tag>», C08-ajuste)
kubectl rollout history deploy/<deployment> -n pharmago
```

## Mitigación automática esperada

- **Mecanismo:** `RollingUpdate` con `maxUnavailable: 0`, `maxSurge: 1` y `minReadySeconds: 5` (C08): una réplica vieja se apaga recién cuando la nueva está Ready, así que una versión que no arranca nunca reemplaza a nada. `deploy.sh` espera 180 s por Deployment y, si no termina, hace `kubectl rollout undo` solo y no sigue con los demás.
- **Tiempo medido (E8 de `chaos-engineering/EXPERIMENTOS.md`):** con una imagen inexistente en pharmacy, el pod nuevo quedó en `ErrImageNeverPull` y el Deployment siguió 2/2 disponible. El usuario no vio nada (0 no-2xx en 150 requests) y **ninguna alerta salió de Normal**. `rollback.sh` lo devolvió a la versión anterior en 1 s. En C08, un rollout v1 → v2 → rollback dio 0 no-2xx en 145 requests (`docs/despliegue-seguro.md`).

## Mitigación manual

1. Confirmar que el usuario no está afectado (las réplicas viejas atienden):
   ```bash
   cd "Implementacion K8S/Codigo/chaos-engineering" && ./observar.sh 20 /api/drug /api/roles
   ```
2. Volver a la versión anterior del Deployment afectado (o de los 4, sin argumento):
   ```bash
   cd "Implementacion K8S/Codigo/k8s" && ./rollback.sh <deployment>
   ```
3. Si `rollback.sh` no alcanza (por ejemplo, la revisión anterior también está mal), desplegar explícitamente un tag conocido que funciona:
   ```bash
   kubectl rollout history deploy/<deployment> -n pharmago        # buscar el tag bueno en CHANGE-CAUSE
   ./deploy.sh <tag-bueno>
   ```

## Validación

```bash
kubectl rollout status deploy/<deployment> -n pharmago --timeout=60s    # successfully rolled out
kubectl get deploy -n pharmago -o custom-columns=DEPLOYMENT:.metadata.name,LISTOS:.status.readyReplicas,IMAGEN:.spec.template.spec.containers[0].image
cd "Implementacion K8S/Codigo/chaos-engineering" && ./steady-state.sh
```

## Si no funciona

- Si el pod viejo tampoco arranca después del rollback, el problema no es la versión: base de datos (`docs/playbooks/desconexion.md`) o el nodo (`docs/playbooks/pod-caido.md`, paso 4).
- `rollback.sh` avisa que la anotación `last-applied-configuration` queda vieja (lo hace `kubectl rollout undo`). Es esperable; el próximo `apply-k8s.sh` o `deploy.sh` la corrige.
- Si el historial no coincide con lo que corre (por ejemplo, después de un `kubectl set image` a mano, que no anota CHANGE-CAUSE), confiar en la columna IMAGEN de la validación. `deploy.sh` y `rollback.sh` anotan el tag correcto desde el ajuste de C08.

## Registro

Copiar `docs/plantillas/registro-incidente.md` a `docs/incidentes/<fecha>-rollout.md`. Anotar: Deployment, tag desplegado y tag de vuelta, por qué no arrancó (evento), si hubo impacto en el usuario, hora del rollback y hora en que el rollout quedó completo.
