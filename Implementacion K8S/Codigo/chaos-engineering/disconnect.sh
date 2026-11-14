#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ALLOWED=(pharmago-db pharmago-users-service pharmago-pharmacy-service pharmago-api-gateway)

usage() {
    echo "Uso: $0 <deployment> <segundos>"
    echo "Deployments permitidos: ${ALLOWED[*]}"
    echo "Ejemplo: $0 pharmago-db 45"
    exit 1
}

[ $# -ge 2 ] || usage
DEP="$1"
SECS="$2"
require_int segundos "$SECS"
valid=0
for a in "${ALLOWED[@]}"; do [ "$a" = "$DEP" ] && valid=1; done
[ "$valid" -eq 1 ] || die "'$DEP' no se puede desconectar. Permitidos: ${ALLOWED[*]}"
require_context
require_deployment "$DEP"

ORIG=$(kubectl get deploy "$DEP" -n "$NS" -o jsonpath='{.spec.replicas}')
[ "${ORIG:-0}" -gt 0 ] || die "$DEP ya está en 0 réplicas"

SCALED=0
cleanup() {
    set +e
    trap - EXIT
    if [ "$SCALED" -eq 1 ]; then
        echo "$(date -u +%H:%M:%S) Restaurando $DEP a $ORIG réplicas..."
        kubectl scale deploy "$DEP" -n "$NS" --replicas="$ORIG" >/dev/null
        local t0
        t0=$(date +%s)
        kubectl rollout status deploy/"$DEP" -n "$NS" --timeout=300s
        echo "$DEP de vuelta en $ORIG/$ORIG Ready en $(( $(date +%s) - t0 )) s desde la restauración."
    fi
    marca_tiempo fin
}
trap cleanup EXIT
trap 'exit 130' INT TERM

marca_tiempo inicio
echo "Desconexión: $DEP pasa de $ORIG réplicas a 0 durante $SECS s"
kubectl scale deploy "$DEP" -n "$NS" --replicas=0 >/dev/null
SCALED=1
for _ in $(seq 1 "$SECS"); do sleep 1; done
