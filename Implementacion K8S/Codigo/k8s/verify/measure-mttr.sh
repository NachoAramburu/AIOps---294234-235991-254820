#!/bin/bash
# C09: mide el MTTR de un microservicio y si el usuario ve errores mientras se recupera.
# Pide 1 request por segundo durante 40 s a un endpoint que atiende ese microservicio. A los 10 s:
#   modo por defecto: borra una réplica (kubectl delete pod: apagado ordenado, como un reemplazo o un desalojo).
#   --crash:          mata el proceso principal dentro del contenedor (kill 1: falla del proceso; el kubelet lo reinicia).
# MTTR = segundos desde la falla hasta que el Deployment vuelve a tener todas sus réplicas Ready.
# Uso: ./measure-mttr.sh <deployment> [--crash] [url_base]
#   deployment: pharmago-api-gateway | pharmago-users-service | pharmago-pharmacy-service | pharmago-ui
# Termina con error si hubo respuestas no-2xx o si tardó más de 15 s.

set -uo pipefail
export MSYS_NO_PATHCONV=1

NS=pharmago
DEP="${1:-}"
MODE="delete"
BASE="http://127.0.0.1"
shift || true
for arg in "$@"; do
    case "$arg" in
        --crash) MODE="crash" ;;
        http*) BASE="$arg" ;;
        *) echo "Argumento desconocido: $arg"; exit 1 ;;
    esac
done

case "$DEP" in
    pharmago-api-gateway)      PATH_REQ=/api/drug ;;
    pharmago-pharmacy-service) PATH_REQ=/api/drug ;;
    pharmago-users-service)    PATH_REQ=/api/roles ;;
    pharmago-ui)               PATH_REQ=/ ;;
    *) echo "Uso: $0 <pharmago-api-gateway|pharmago-users-service|pharmago-pharmacy-service|pharmago-ui> [--crash] [url_base]"; exit 1 ;;
esac
if [ "$(kubectl config current-context 2>/dev/null)" != "minikube" ]; then
    echo "Error: el contexto de kubectl no es minikube."
    exit 1
fi
URL="$BASE$PATH_REQ"
if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL")" != "200" ]; then
    echo "Error: $URL no responde 200 antes de empezar. ¿Está abierto minikube tunnel?"
    exit 1
fi

DESIRED=$(kubectl get deploy "$DEP" -n "$NS" -o jsonpath='{.spec.replicas}')
POD=$(kubectl get pods -n "$NS" -l app="$DEP" -o jsonpath='{.items[0].metadata.name}')
RESTARTS0=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.status.containerStatuses[0].restartCount}')
LOG=$(mktemp)
FAULT_AT=10
DURATION=40
echo "Deployment: $DEP | modo: $MODE | pod: $POD | réplicas: $DESIRED | URL: $URL | $DURATION requests, 1 por segundo"

ready_count() {
    # Pods Ready que no se están borrando.
    kubectl get pods -n "$NS" -l app="$DEP" \
        -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}{"|"}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null \
        | awk -F'|' '$1 == "" && $2 == "true"' | wc -l
}

T_FAULT=""
T_BACK=""
for i in $(seq 1 "$DURATION"); do
    if [ "$i" -eq "$FAULT_AT" ]; then
        T_FAULT=$(date +%s.%N)
        if [ "$MODE" = "crash" ]; then
            kubectl exec -n "$NS" "$POD" -- /bin/sh -c "kill 1" >/dev/null 2>&1
            echo "t=${i}s  kill 1 dentro de $POD"
        else
            kubectl delete pod "$POD" -n "$NS" --wait=false >/dev/null
            echo "t=${i}s  kubectl delete pod $POD"
        fi
    fi
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL")
    echo "$i $code" >> "$LOG"
    [ "${code:0:1}" != "2" ] && echo "t=${i}s  HTTP $code"
    if [ -n "$T_FAULT" ] && [ -z "$T_BACK" ] && [ "$i" -gt "$FAULT_AT" ]; then
        if [ "$MODE" = "crash" ]; then
            r=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
            if [ "${r:-0}" -gt "$RESTARTS0" ] && [ "$(ready_count)" -ge "$DESIRED" ]; then T_BACK=$(date +%s.%N); fi
        elif [ "$(ready_count)" -ge "$DESIRED" ]; then
            T_BACK=$(date +%s.%N)
        fi
    fi
    sleep 1
done

TOTAL=$(wc -l < "$LOG")
OK=$(awk '$2 ~ /^2/' "$LOG" | wc -l)
BAD=$((TOTAL - OK))
echo "Respuestas: $TOTAL | 2xx: $OK | no-2xx: $BAD"
rm -f "$LOG"
if [ -z "$T_BACK" ]; then
    echo "FALLA: el Deployment no volvió a $DESIRED réplicas Ready en $((DURATION - FAULT_AT)) s."
    exit 1
fi
MTTR=$(awk -v a="$T_FAULT" -v b="$T_BACK" 'BEGIN { printf "%.1f", b - a }')
echo "MTTR (falla -> $DESIRED/$DESIRED Ready): ${MTTR} s (resolución de 1 s, la del loop)"
if [ "$BAD" -gt 0 ]; then
    echo "FALLA: hubo respuestas no-2xx."
    exit 1
fi
if awk -v m="$MTTR" 'BEGIN { exit !(m > 15) }'; then
    echo "FALLA: el MTTR superó los 15 s."
    exit 1
fi
echo "OK"
