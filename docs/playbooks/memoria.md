# Playbook: sobrecarga de memoria

> Convención de los playbooks: lo que va entre comillas dobles es el título exacto de un dashboard o panel de Grafana, y los `pg-*` son los uid de las alertas (`k8s/configmaps/grafana-alerting.yaml`). Lo verifica `k8s/verify/check-playbooks.sh`.

## Síntoma

La memoria de un pod se acerca a su límite (`limits.memory`: 384Mi en gateway, users y pharmacy; 256Mi en la UI). Si lo supera, el OOM killer del kernel mata el proceso más grande del contenedor. El usuario en general no ve errores mientras la otra réplica esté sana.

## Alerta

- `pg-memory`: un pod del namespace por encima del 85 % de su límite de memoria durante 30 s.
- Si el que muere es el proceso principal (la app), el contenedor se reinicia y dispara `pg-restarts`.

## Panel

- "PharmaGo - Infra" → "Memoria del pod contra su límite": el pod cerca del 100 % (la línea roja es el 90 %).
- "PharmaGo - Infra" → "Memoria del contenedor contra su límite": lo mismo por contenedor.
- "PharmaGo - Infra" → "Memoria por pod (working set)": valor absoluto, para ver si sube de golpe o de a poco.
- "PharmaGo - Infra" → "Reinicios por contenedor": si el OOM mató a la app.

## Severidad inicial

**SEV2** (criterio del plan: memoria > 85 % del límite durante 30 s). Sube a **SEV1** si las dos réplicas del mismo servicio están arriba del 85 % o se reinician a la vez (`pg-restarts` en las dos), porque ahí sí hay riesgo de que no quede ninguna Ready.

## Diagnóstico

```bash
# 1. Qué pod y cuánto
kubectl top pod -n pharmago --sort-by=memory | head -8

# 2. Qué proceso ocupa la memoria (VmRSS en kB; las imágenes no traen ps)
kubectl exec -n pharmago <pod> -- sh -c 'for p in /proc/[0-9]*; do printf "%s %s %s\n" "${p#/proc/}" "$(grep VmRSS $p/status 2>/dev/null)" "$(tr "\0" " " < $p/cmdline)"; done' | sort -k3 -n -r | head

# 3. ¿Hubo OOM? oom_kill cuenta procesos matados dentro del contenedor
kubectl exec -n pharmago <pod> -- grep oom /sys/fs/cgroup/memory.events

# 4. ¿Se reinició la app? (OOMKilled en el último estado)
kubectl get pod -n pharmago <pod> -o jsonpath='{.status.containerStatuses[0].restartCount} {.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'

# 5. ¿El usuario lo nota?
cd "Implementacion K8S/Codigo/chaos-engineering" && ./observar.sh 30 /api/drug /api/roles
```

## Mitigación automática esperada

- **Mecanismo:** el límite de memoria aísla al pod. Si se supera, el OOM killer del kernel mata el proceso más grande **dentro de ese contenedor**. En este cluster `memory.oom.group` está apagado (cri-dockerd), así que no mata al contenedor entero: si el que crece es un proceso ajeno, la app sigue viva; si es la app, el kubelet la reinicia y la otra réplica atiende.
- **Tiempo medido (E3 de `chaos-engineering/EXPERIMENTOS.md`):**
  - Presión sostenida (E3b, 250 MB en un pod de pharmacy): la memoria del pod quedó en 89 % del límite. `pg-memory` pasó a Pending a los 27 s y a Firing a los 59 s, y volvió a Normal 23 s después de liberar la memoria. 0 no-2xx en 210 requests, sin reinicios.
  - Pico brusco por encima del límite (E3a): el OOM killer mató el proceso del experimento a los 7 s (`oom_kill 1`). La app no se reinició y **ninguna alerta disparó**: el pico duró menos de lo que tarda la métrica en llegar a Prometheus (~30 s). Esa falla solo se ve en `memory.events` (diagnóstico 3).

## Mitigación manual

1. Identificar el pod y el proceso (diagnóstico 1 y 2).
2. Si el proceso que crece es ajeno a la app, matarlo; la memoria se libera al instante:
   ```bash
   kubectl exec -n pharmago <pod> -- sh -c 'kill <pid>'    # kill es de la shell: la imagen no trae el binario
   ```
3. Si es la app (fuga de memoria), reemplazar el pod antes de que el OOM la mate en medio de una request:
   ```bash
   kubectl delete pod -n pharmago <pod>
   ```
   La otra réplica atiende; el reemplazo queda Ready en unos 7 a 9 s (`docs/mttr.md`).
4. Si las dos réplicas crecen igual después de un despliegue, es la versión nueva: `docs/playbooks/rollout-fallido.md`.

## Validación

```bash
kubectl top pod -n pharmago --sort-by=memory | head -5   # el pod volvió a su valor normal (≈ 75-100Mi en los servicios .NET)
cd "Implementacion K8S/Codigo/chaos-engineering" && ./steady-state.sh
```

`pg-memory` vuelve a Normal unos 20-30 s después de que baja la memoria (E3b). Repetir `steady-state.sh` hasta `RESULTADO: steady state OK`.

## Si no funciona

- Si el pod nuevo vuelve a crecer, es la app: rollback (`docs/playbooks/rollout-fallido.md`) y registrar la fuga para el postmortem.
- Si `pg-memory` dispara para un pod de observabilidad (por ejemplo `otlp-collector` u `otel-agent`), no es la app: revisar sus límites. Así se encontró en C18 que el Collector estaba al 92 % de 256Mi (D55).
- Si hay reinicios en loop (`CrashLoopBackOff`), seguir `docs/playbooks/pod-caido.md`.

## Registro

Copiar `docs/plantillas/registro-incidente.md` a `docs/incidentes/<fecha>-memoria.md`. Anotar: pod y proceso, pico de memoria contra el límite, si hubo OOM (`oom_kill`) o reinicio, acción tomada y hora en que `pg-memory` volvió a Normal.
