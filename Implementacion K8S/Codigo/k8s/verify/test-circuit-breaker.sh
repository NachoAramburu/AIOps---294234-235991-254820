#!/bin/bash
# C07: prueba en el cluster el circuit breaker del gateway.
# Escala pharmago-users-service a 0, pide GET /api/roles por el Ingress a 2 por segundo durante 15 s,
# restaura las réplicas (también si se corta con Ctrl+C) y espera a que vuelva a responder 200.
# Termina con error si nunca aparece un 503 con circuit_open o si el servicio no vuelve.
# Uso: ./test-circuit-breaker.sh [url_base]      (por defecto http://127.0.0.1, requiere minikube tunnel)

set -uo pipefail
export MSYS_NO_PATHCONV=1

NS=pharmago
DEPLOY=pharmago-users-service
BASE="${1:-http://127.0.0.1}"
URL="$BASE/api/roles"

if [ "$(kubectl config current-context 2>/dev/null)" != "minikube" ]; then
    echo "Error: el contexto de kubectl no es minikube."
    exit 1
fi
if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL")" != "200" ]; then
    echo "Error: $URL no responde 200. ¿Está abierto minikube tunnel?"
    exit 1
fi

ORIG=$(kubectl get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.spec.replicas}')
restore() {
    echo "Restaurando $DEPLOY a $ORIG réplicas..."
    kubectl scale deploy "$DEPLOY" -n "$NS" --replicas="$ORIG" >/dev/null
    kubectl rollout status deploy/"$DEPLOY" -n "$NS" --timeout=180s >/dev/null
}
trap restore EXIT

echo "$(date -u +%H:%M:%S) Escalando $DEPLOY a 0 (estaba en $ORIG)"
kubectl scale deploy "$DEPLOY" -n "$NS" --replicas=0 >/dev/null
kubectl wait --for=delete pod -l app="$DEPLOY" -n "$NS" --timeout=90s >/dev/null 2>&1

seen_open=0
echo "$(date -u +%H:%M:%S) GET $URL, 2 por segundo durante 15 s:"
for i in $(seq 1 30); do
    resp=$(curl -s -w ' %{http_code}' --max-time 15 "$URL")
    code=${resp##* }
    printf "%s " "$code"
    if [ "$code" = "503" ] && echo "$resp" | grep -q "circuit_open"; then
        seen_open=1
    fi
    sleep 0.5
done
echo

restore
trap - EXIT

echo "$(date -u +%H:%M:%S) Esperando que $URL vuelva a 200 (1 pedido por segundo, hasta 90 s):"
back=0
for i in $(seq 1 90); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL")
    printf "%s " "$code"
    if [ "$code" = "200" ]; then
        back=1
        echo
        echo "$(date -u +%H:%M:%S) Volvió a 200 a los ${i} s de restaurar."
        break
    fi
    sleep 1
done

echo "Logs del gateway (transiciones del breaker):"
kubectl logs -n "$NS" -l app=pharmago-api-gateway --since=5m --tail=-1 2>/dev/null | grep -o "circuit_breaker cluster=[a-z-]* state=[a-z0-9 -]*" | sed 's/^/  /'

if [ "$seen_open" -ne 1 ]; then
    echo "FALLA: nunca apareció un 503 con circuit_open."
    exit 1
fi
if [ "$back" -ne 1 ]; then
    echo "FALLA: el servicio no volvió a responder 200."
    exit 1
fi
echo "OK: el circuito se abrió (503 circuit_open) y el servicio se recuperó solo."
