# Playbook: desconexión de un componente interno

> Convención de los playbooks: lo que va entre comillas dobles es el título exacto de un dashboard o panel de Grafana, y los `pg-*` son los uid de las alertas (`k8s/configmaps/grafana-alerting.yaml`). Lo verifica `k8s/verify/check-playbooks.sh`.

## Síntoma

Un componente interno desaparece: un microservicio o la base de datos queda con **0 réplicas** (alguien lo escaló a 0, o todos sus pods cayeron). Los endpoints que dependen de él devuelven **503** (breaker abierto o ningún pod detrás del Service); los demás siguen bien. Si es la base de datos, fallan users y pharmacy a la vez.

## Alerta

- `pg-breaker`: el gateway abrió el circuito hacia el cluster del servicio desconectado.
- `pg-5xx`: más del 5 % de las respuestas del gateway son 5xx durante 30 s.
- `pg-replicas` **no** dispara si lo escalaron a 0: las réplicas deseadas también bajan (`docs/alertas.md`, limitaciones). Sí dispara si los pods caen solos y el Deployment no logra reponerlos en 30 s.

## Panel

- "PharmaGo - Infra" → "Réplicas deseadas y disponibles por Deployment": la serie del componente en 0 (deseadas y disponibles).
- "PharmaGo - Overview" → "Distribución de Status Codes (%)": aparecen 503.
- "PharmaGo - Overview" → "Tasa de Error por Endpoint (%)": qué endpoints fallan (`/api/drug` es pharmacy; `/api/roles` y `/api/login` son users; todos, la base).

## Severidad inicial

**SEV1**: un microservicio o la base con 0 réplicas disponibles es servicio caído (criterio del plan).

## Diagnóstico

```bash
# 1. Qué Deployment está en 0 (READY 0/0 o 0/N)
kubectl get deploy -n pharmago

# 2. ¿Lo escalaron o se cayó? (ScalingReplicaSet = alguien cambió las réplicas)
kubectl get events -n pharmago --sort-by=.lastTimestamp | grep -E 'ScalingReplicaSet|Killing|FailedCreate' | tail -8

# 3. Qué cluster tiene el breaker abierto
kubectl logs -n pharmago -l app=pharmago-api-gateway --since=5m | grep circuit_breaker | tail -3

# 4. Si fallan users y pharmacy: ¿es la base? (traza en Jaeger con span PharmaDb en error; readiness de los dos)
kubectl get deploy pharmago-db -n pharmago
kubectl get events -n pharmago --sort-by=.lastTimestamp | grep -i 'readiness' | tail -5
```

## Mitigación automática esperada

- **Mecanismo:** si los pods caen solos, el Deployment los repone (ver `docs/playbooks/pod-caido.md`). Si **lo escalaron a 0**, ningún mecanismo lo devuelve: Kubernetes respeta las réplicas deseadas. Mientras tanto, el circuit breaker del gateway corta las requests a ese servicio con 503 inmediato (D13) y la readiness de los otros servicios no cambia: el resto de la app sigue funcionando.
- **Tiempo medido (E6 de `chaos-engineering/EXPERIMENTOS.md`, pharmacy a 0 durante 60 s con ~1,4 requests/s a `/api/drug`):** los primeros errores llegaron 7 s después de escalar (3 respuestas 502 mientras los pods se apagaban y después 503). `pg-breaker` se vio en Firing a los 33 s y `pg-5xx` a los 55 s. Las respuestas 503 tardaron menos de 0,3 s. `/api/roles` siguió con 0 no-2xx en 85 requests. Al restaurar, pharmacy volvió a 2/2 en 14 s y todas las alertas estaban en Normal 76 s después.
- Base de datos: SQL Server tarda unos 45 s en arrancar y los servicios vuelven solos unos 8 s después de que la base está Ready (C17, `docs/incidentes/ejemplo-postmortem.md`).

## Mitigación manual

1. Restaurar las réplicas del componente (lo ordena el IC):
   ```bash
   kubectl scale deploy/<deployment> -n pharmago --replicas=2     # microservicios
   kubectl scale deploy/pharmago-db -n pharmago --replicas=1      # base de datos
   ```
2. Esperar a que queden Ready:
   ```bash
   kubectl rollout status deploy/<deployment> -n pharmago --timeout=180s
   ```
3. Si era la base de datos, **no** reiniciar los microservicios: vuelven solos unos 8 s después de que la base está Ready (lección del postmortem de ejemplo).

## Validación

```bash
kubectl get deploy -n pharmago     # 4 microservicios 2/2 y la base 1/1
cd "Implementacion K8S/Codigo/chaos-engineering" && ./steady-state.sh
```

`pg-5xx` tarda cerca de 1 min en volver a Normal (ventana de 1 min del `rate`). Durante la falla, `steady-state.sh` termina con salida distinta de 0 (E6: `exit=3`, con el Deployment 0/2, 503 en `/api/drug` y `pg-breaker` en Firing); al final tiene que dar `RESULTADO: steady state OK`.

## Si no funciona

- Si el Deployment no levanta pods (`0/2` con eventos `FailedCreate` o pods `Pending`): `kubectl describe pod -n pharmago <pod>` (falta de recursos en el nodo, imagen inexistente). Si empezó con un despliegue, `docs/playbooks/rollout-fallido.md`.
- Si los pods están Ready pero el breaker sigue abriendo, el problema es la red: `docs/playbooks/red.md`.
- Si la base no queda Ready en 2 min: `kubectl logs -n pharmago deploy/pharmago-db --tail=30` y revisar el PVC (`kubectl get pvc -n pharmago`).

## Registro

Copiar `docs/plantillas/registro-incidente.md` a `docs/incidentes/<fecha>-desconexion.md`. Anotar: componente, hora en que quedó en 0 (evento `ScalingReplicaSet`), endpoints afectados, hora de restauración, tiempo hasta Ready y hora del primer 200.
