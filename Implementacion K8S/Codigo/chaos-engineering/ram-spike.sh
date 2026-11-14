#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
    echo "Uso: $0 <deployment> <MB> <segundos>"
    echo "Ejemplo: $0 pharmago-pharmacy-service 150 60"
    echo "Con MB mayor al límite de memoria del contenedor, Kubernetes lo mata (OOMKilled) y lo reinicia."
    exit 1
}

[ $# -ge 3 ] || usage
DEP="$1"
MB="$2"
SECS="$3"
require_int MB "$MB"
require_int segundos "$SECS"
require_context
require_deployment "$DEP"
POD=$(pick_pod "$DEP")
RESTARTS0=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.status.containerStatuses[0].restartCount}')

EXEC_PID=""
cleanup() {
    set +e
    trap - EXIT
    [ -n "$EXEC_PID" ] && kill "$EXEC_PID" 2>/dev/null
    kill_marked "$POD" chaos_ram
    local restarts reason
    restarts=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "?")
    reason=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null || true)
    echo "Reinicios de $POD: $RESTARTS0 -> $restarts ${reason:+(último motivo: $reason)}"
    marca_tiempo fin
}
trap cleanup EXIT
trap 'exit 130' INT TERM

marca_tiempo inicio
echo "Memoria: $POD retiene $MB MB durante $SECS s"
rc=0
kubectl exec -n "$NS" "$POD" -- sh -c ": chaos_ram; a=\$(dd if=/dev/zero bs=1048576 count=$MB 2>/dev/null | tr '\\0' x); sleep $SECS" &
EXEC_PID=$!
while kill -0 "$EXEC_PID" 2>/dev/null; do sleep 1; done
wait "$EXEC_PID" || rc=$?
EXEC_PID=""
if [ "$rc" -ne 0 ]; then
    echo "El proceso del experimento terminó con código $rc (137 = el contenedor fue matado, por ejemplo OOMKilled)."
fi
