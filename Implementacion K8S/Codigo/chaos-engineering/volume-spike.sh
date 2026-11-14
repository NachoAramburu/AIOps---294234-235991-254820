#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
    echo "Uso: $0 <deployment> <MB> <segundos>"
    echo "Ejemplo: $0 pharmago-users-service 200 60"
    echo "Con MB mayor al límite de ephemeral-storage (512Mi), el kubelet desaloja el pod y el Deployment crea otro."
    exit 1
}

[ $# -ge 3 ] || usage
DEP="$1"
MB="$2"
SECS="$3"
FILE=/tmp/chaos_fill
require_int MB "$MB"
require_int segundos "$SECS"
require_context
require_deployment "$DEP"
POD=$(pick_pod "$DEP")

EXEC_PID=""
rc=0
cleanup() {
    set +e
    trap - EXIT
    [ -n "$EXEC_PID" ] && kill "$EXEC_PID" 2>/dev/null
    kill_marked "$POD" chaos_vol
    if kubectl get pod "$POD" -n "$NS" >/dev/null 2>&1 && \
       kubectl exec -n "$NS" "$POD" -- rm -f "$FILE" >/dev/null 2>&1; then
        echo "Archivo $FILE borrado en $POD."
    else
        echo "$POD ya no está disponible: el archivo se fue con el pod."
    fi
    local phase="" i
    if [ "$rc" -ne 0 ]; then
        for i in $(seq 1 20); do
            phase=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)
            [ "$phase" = "Succeeded" ] || [ "$phase" = "Failed" ] || [ -z "$phase" ] && break
            sleep 1
        done
    fi
    if [ "$phase" = "Succeeded" ] || [ "$phase" = "Failed" ]; then
        local why
        why=$(kubectl get events -n "$NS" --field-selector involvedObject.name="$POD",reason=Evicted -o jsonpath='{.items[0].message}' 2>/dev/null || true)
        echo "$POD terminó (${phase}${why:+, desalojado: $why}). Se borra el pod terminado; el Deployment ya creó otro."
        kubectl delete pod "$POD" -n "$NS" --wait=false >/dev/null 2>&1 || true
    fi
    marca_tiempo fin
}
trap cleanup EXIT
trap 'exit 130' INT TERM

marca_tiempo inicio
echo "Storage: $POD escribe $MB MB en $FILE y los mantiene $SECS s"
kubectl exec -n "$NS" "$POD" -- sh -c ": chaos_vol; dd if=/dev/zero of=$FILE bs=1048576 count=$MB 2>/dev/null; ls -l $FILE; sleep $SECS" &
EXEC_PID=$!
while kill -0 "$EXEC_PID" 2>/dev/null; do sleep 1; done
wait "$EXEC_PID" || rc=$?
EXEC_PID=""
if [ "$rc" -ne 0 ]; then
    echo "El proceso del experimento terminó con código $rc (el pod pudo haber sido desalojado)."
fi
