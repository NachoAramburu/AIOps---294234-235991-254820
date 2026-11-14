# Playbook: interrupción de tráfico de red

> Convención de los playbooks: lo que va entre comillas dobles es el título exacto de un dashboard o panel de Grafana, y los `pg-*` son los uid de las alertas (`k8s/configmaps/grafana-alerting.yaml`). Lo verifica `k8s/verify/check-playbooks.sh`.

## Síntoma

Un microservicio deja de ser alcanzable por la red (por ejemplo, una NetworkPolicy que niega todo su tráfico) aunque sus pods sigan `Running` y, durante un rato, `Ready`. El gateway espera hasta 3 s por intento y después devuelve **504**; con suficiente tráfico, el circuit breaker abre y devuelve **503** inmediato. Los endpoints de los otros servicios siguen bien.

## Alerta

- `pg-breaker`: el circuit breaker del gateway está abierto para un cluster (`users-cluster` o `pharmacy-cluster`).
- `pg-5xx`: más del 5 % de las respuestas del gateway son 5xx durante 30 s.
- `pg-latency`: P95 del gateway > 1000 ms durante 1 min (los intentos que esperan el timeout).

## Panel

- "PharmaGo - Overview" → "Distribución de Status Codes (%)": aparecen 503 y 504.
- "PharmaGo - Overview" → "Tasa de Error por Endpoint (%)": qué endpoint falla (`/api/roles` y `/api/login` son users; `/api/drug` es pharmacy).
- "PharmaGo - Overview" → "Latencia Promedio por Endpoint": sube por los intentos que esperan los 3 s.
- "PharmaGo - Infra" → "Red por nodo (rx y tx)": cae el tráfico del nodo del servicio afectado (`minikube-m03` users, `minikube-m04` pharmacy). No hay red por pod en este cluster (ver el panel "Red por pod: no disponible en este cluster").

## Severidad inicial

**SEV1** si `pg-breaker` está en Firing o el 5xx del gateway supera el 50 % (criterio del plan: el servicio está caído para el usuario). **SEV2** si solo hay `pg-5xx` o `pg-latency`.

## Diagnóstico

```bash
# 1. ¿Hay una NetworkPolicy que niega tráfico? (es la causa más rápida de confirmar)
kubectl get networkpolicy -n pharmago
kubectl describe networkpolicy -n pharmago <nombre>

# 2. Qué cluster tiene el breaker abierto y desde cuándo
kubectl logs -n pharmago -l app=pharmago-api-gateway --since=5m | grep circuit_breaker | tail -5

# 3. ¿Los pods del servicio están vivos? (con un corte de red suelen seguir Running)
kubectl get pods -n pharmago -o wide | grep -E 'users|pharmacy'

# 4. ¿Llegan al servicio desde el gateway? (sin curl en la imagen: /dev/tcp de bash)
kubectl exec -n pharmago deploy/pharmago-api-gateway -- bash -c 'timeout 3 bash -c "exec 3<>/dev/tcp/pharmago-users-service/80" && echo conecta || echo NO conecta'

# 5. Lo que ve el usuario (timeout del cliente mayor que los reintentos del gateway)
cd "Implementacion K8S/Codigo/chaos-engineering" && ./observar.sh 30 /api/roles /api/drug
```

## Mitigación automática esperada

- **Mecanismo:** timeout de 3 s por intento y hasta 2 reintentos de GET en el gateway; circuit breaker por cluster que abre cuando falla al menos la mitad de 8 o más requests en 10 s, queda abierto 5 s y prueba de nuevo (half-open) (D13). El breaker **no arregla la red**: evita que el usuario espere 9 s y le devuelve 503 al instante. La red vuelve cuando se quita la causa.
- **Tiempo medido (E5 de `chaos-engineering/EXPERIMENTOS.md`):**
  - Con tráfico de varios usuarios (E5b, ~1,4 requests/s a `/api/roles`): el breaker de `users-cluster` abrió a los 14 s del corte y alternó open y half-open cada 5-7 s. Los usuarios recibieron 503 en menos de 100 ms (salvo las pruebas de half-open, de hasta 3,2 s). `pg-breaker` se vio en Firing a los 33 s (alterna con Normal en cada half-open), `pg-5xx` a los 61 s y `pg-latency` después del corte. `/api/drug` siguió con 0 no-2xx: el blast radius quedó en users.
  - Con poco tráfico (E5a, 0,5 requests/s): el breaker **no abrió** (no llega a 8 requests en 10 s). Cada request esperó los timeouts y solo disparó `pg-latency`, cuando el corte ya había terminado.
  - Al borrar la policy, `/api/roles` volvió a 200 en unos 3 s.

## Mitigación manual

1. Si hay una NetworkPolicy desconocida o `chaos-*` (diagnóstico 1), borrarla (lo ordena el IC):
   ```bash
   kubectl delete networkpolicy -n pharmago <nombre>
   ```
2. Si no hay policy y los pods no conectan (diagnóstico 4), reiniciar los pods del servicio afectado para renovar su red:
   ```bash
   kubectl rollout restart deploy/<deployment> -n pharmago
   ```
3. Si el problema es del nodo entero ("Nodos Ready" o "Red por nodo (rx y tx)" en 0 para ese nodo), ver `docs/plan-incidentes.md`, riesgo «Réplicas en el mismo nodo»: `minikube node start <nodo>`.

## Validación

```bash
kubectl get networkpolicy -n pharmago          # sin policies chaos-*
kubectl logs -n pharmago -l app=pharmago-api-gateway --since=2m | grep circuit_breaker | tail -2   # último estado: closed
cd "Implementacion K8S/Codigo/chaos-engineering" && ./steady-state.sh
```

`pg-5xx` y `pg-latency` tardan cerca de 1 min en volver a Normal después de que el servicio responde (ventana de 1 min del `rate`; E5b: todas en Normal 69 s después del fin del corte). Repetir `steady-state.sh` hasta `RESULTADO: steady state OK`.

## Si no funciona

- Si al borrar la policy el breaker sigue abriendo, el servicio tiene otro problema: ver si sus pods están Ready y seguir `docs/playbooks/desconexion.md` o `docs/playbooks/pod-caido.md`.
- Si fallan users y pharmacy a la vez con 500, sospechar de la base de datos (la tabla de triage de `docs/plan-incidentes.md`, sección 7).
- Si el gateway mismo no responde (todos los endpoints con error), el corte es del gateway o del Ingress: `kubectl get pods -n pharmago -l app=pharmago-api-gateway` y `kubectl get pods -n ingress-nginx`.

## Registro

Copiar `docs/plantillas/registro-incidente.md` a `docs/incidentes/<fecha>-red.md`. Anotar: servicio y causa (policy, nodo), hora de apertura del breaker (del log del gateway), códigos que vio el usuario, acción tomada y hora en que volvió el primer 200.
