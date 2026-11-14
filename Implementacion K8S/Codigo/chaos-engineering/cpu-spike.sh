#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
    echo "Uso: $0 <deployment> <segundos> [hilos=4]"
    echo "Ejemplo: $0 pharmago-api-gateway 60 4"
    exit 1
}

[ $# -ge 2 ] || usage
DEP="$1"
SECS="$2"
THREADS="${3:-4}"
require_int segundos "$SECS"
require_int hilos "$THREADS"
require_context
require_deployment "$DEP"
POD=$(pick_pod "$DEP")

EXEC_PID=""
cleanup() {
    set +e
    trap - EXIT
    [ -n "$EXEC_PID" ] && kill "$EXEC_PID" 2>/dev/null
    kill_marked "$POD" chaos_cpu
    echo "Loops que quedan en $POD: $(count_marked "$POD" chaos_cpu)"
    marca_tiempo fin
}
trap cleanup EXIT
trap 'exit 130' INT TERM

marca_tiempo inicio
echo "CPU: $POD, $THREADS hilos durante $SECS s"
kubectl exec -n "$NS" "$POD" -- sh -c "
    i=0
    while [ \$i -lt $THREADS ]; do
        timeout $SECS sh -c ': chaos_cpu; while :; do :; done' &
        i=\$((i+1))
    done
    wait" &
EXEC_PID=$!
while kill -0 "$EXEC_PID" 2>/dev/null; do sleep 1; done
wait "$EXEC_PID" || true
EXEC_PID=""
