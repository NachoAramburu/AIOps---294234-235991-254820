# Playbook: inyección de requests (ráfaga de tráfico)

> Convención de los playbooks: lo que va entre comillas dobles es el título exacto de un dashboard o panel de Grafana, y los `pg-*` son los uid de las alertas (`k8s/configmaps/grafana-alerting.yaml`). Lo verifica `k8s/verify/check-playbooks.sh`.

## Síntoma

Muchas respuestas **429 Too Many Requests** en el gateway, en general concentradas en un endpoint (por ejemplo `/api/login`). El throughput sube de golpe. El resto de los endpoints sigue respondiendo 200.

## Alerta

- `pg-429`: más de 1 respuesta 429 por segundo en el gateway durante 30 s.

## Panel

- "PharmaGo - Overview" → "Rate Limit Errors (429) por Endpoint": qué endpoint recibe la ráfaga.
- "PharmaGo - Overview" → "Peticiones por Segundo por Endpoint" y "Throughput Total": tamaño de la ráfaga.
- "PharmaGo - Overview" → "Distribución de Status Codes (%)": proporción de 429 sobre el total.
- "PharmaGo - Infra" → "CPU del contenedor contra su límite": si la ráfaga además satura el gateway.

## Severidad inicial

**SEV3**: el rate limit es la protección funcionando. Sube a **SEV2** si aparecen 429 en endpoints que los usuarios legítimos usan a ritmo normal o si `pg-cpu` también dispara para el gateway.

## Diagnóstico

```bash
# 1. Qué endpoint y cuánto (Prometheus por port-forward, o el panel de arriba)
curl -s --data-urlencode 'query=sum by (endpoint) (rate(pharmago_http_requests_total{job="PharmaGo.ApiGateway",status_code="429"}[1m]))' http://127.0.0.1:9090/api/v1/query

# 2. ¿El tráfico legítimo sigue bien? 1 request/s a otro endpoint
cd "Implementacion K8S/Codigo/chaos-engineering" && ./observar.sh 30 /api/drug

# 3. ¿El gateway está saturado?
kubectl top pod -n pharmago -l app=pharmago-api-gateway

# 4. Logs del rate limit en el gateway (Kibana, índice pharmago-logs-*, o directo)
kubectl logs -n pharmago -l app=pharmago-api-gateway --since=5m | grep -m5 'has been blocked'
# Ejemplo real: Request post:/api/login from IP 192.168.49.2 has been blocked, quota 10/1m exceeded by 1. Blocked by rule POST:/api/login
```

## Mitigación automática esperada

- **Mecanismo:** rate limit de `AspNetCoreRateLimit` en el gateway, por IP y por endpoint (10 por minuto en login, 100 por minuto en el resto). Corta con 429 sin llegar a los servicios.
- **Tiempo medido (E1 de `chaos-engineering/EXPERIMENTOS.md`):** el corte es inmediato (280 de 300 requests con 429). `pg-429` pasó a Pending a los 17 s y a Firing a los 50 s, y volvió a Normal 70 s después del fin de la ráfaga (ventana de 1 min). El tráfico legítimo a `/api/drug` tuvo 0 no-2xx en 150 requests.
- El límite es **por réplica** del gateway (contador en memoria): con 2 réplicas el límite efectivo es el doble.
- Con `minikube tunnel` todas las requests llegan al gateway con la IP del nodo (`192.168.49.2`, se ve en el log). El límite «por IP» queda compartido por todos los clientes: una ráfaga a un endpoint también le gasta la cuota a los usuarios legítimos de **ese** endpoint. Los demás endpoints tienen su propia cuota y no se afectan (E1).

## Mitigación manual

1. Confirmar que el resto de los endpoints responde 200 (paso 2 del diagnóstico). Si es así, **no hacer nada**: esperar a que termine la ráfaga.
2. Si la ráfaga sigue y el gateway está saturado (CPU del gateway arriba del 80 %), escalar el gateway para repartir la carga:
   ```bash
   kubectl scale deploy/pharmago-api-gateway -n pharmago --replicas=3
   ```
   La tercera réplica cae en `minikube-m02` (nodeAffinity del gateway). Recordar volver a 2 al cerrar.
3. Si la ráfaga viene de una sola IP conocida y afecta a usuarios legítimos, documentarlo en el registro: bloquear IPs queda fuera del alcance del cluster (no hay WAF).

## Validación

```bash
cd "Implementacion K8S/Codigo/chaos-engineering" && ./steady-state.sh
```

Termina en `RESULTADO: steady state OK` cuando `pg-429` volvió a Normal y no hay no-2xx en el loop de 20 s. Si se escaló el gateway, volver a 2 réplicas antes de validar:

```bash
kubectl scale deploy/pharmago-api-gateway -n pharmago --replicas=2
```

## Si no funciona

- Si hay 429 en endpoints con tráfico normal: revisar los límites en la sección `IpRateLimiting` de `Implementacion K8S/Codigo/Backend/PharmaGo.ApiGateway/appsettings.json` (van dentro de la imagen) y hacer `kubectl rollout restart deploy/pharmago-api-gateway -n pharmago` para vaciar los contadores en memoria.
- Si aparecen 5xx además de 429, el gateway está sobrepasado: seguir `docs/playbooks/cpu.md`.

## Registro

Copiar `docs/plantillas/registro-incidente.md` a `docs/incidentes/<fecha>-requests.md`. Anotar: hora de la alerta, endpoint afectado, pico de requests por segundo, si hubo impacto en otros endpoints y si se escaló.
