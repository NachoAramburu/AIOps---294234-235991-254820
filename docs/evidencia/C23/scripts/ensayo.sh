#!/bin/bash

set -uo pipefail
export MSYS_NO_PATHCONV=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
CHAOS="$REPO/Implementacion K8S/Codigo/chaos-engineering"
EV="$REPO/docs/evidencia/C23"
TRAFICO="$REPO/docs/evidencia/C18/scripts/con_trafico.sh"
cd "$CHAOS"

run() {
    local id="$1" obs="$2" routes="$3" ruta_trafico="$4"
    shift 4
    local out="$EV/03-ensayo-${id}.txt"
    {
        echo "##### Ensayo ${id} $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "\$ ./steady-state.sh   (antes)"
        ./steady-state.sh; echo "exit=$?"
        echo
        echo "\$ ./observar.sh ${obs} ${routes} &"
        echo "\$ $*"
        ./observar.sh "$obs" $routes > "$out.obs" 2>&1 &
        local op=$!
        sleep 5
        local t0 t1
        t0=$(date +%s)
        echo "Inicio de la falla: $(date -u +%H:%M:%S)"
        if [ -n "$ruta_trafico" ]; then
            bash "$TRAFICO" "$ruta_trafico" "$@"; echo "exit=$?"
        else
            "$@"; echo "exit=$?"
        fi
        t1=$(date +%s)
        echo "Fin de la falla: $(date -u +%H:%M:%S) ($((t1 - t0)) s)"
        wait "$op"
        echo "--- observar.sh"
        cat "$out.obs"
        rm -f "$out.obs"
        echo
        local i rc
        for i in $(seq 1 10); do
            echo "\$ ./steady-state.sh   (intento ${i}, $(( $(date +%s) - t1 )) s después del fin)"
            ./steady-state.sh; rc=$?; echo "exit=${rc}"
            if [ "$rc" -eq 0 ]; then
                echo "Recuperación: steady state OK $(( $(date +%s) - t1 )) s después del fin de la falla"
                break
            fi
            sleep 10
        done
    } > "$out" 2>&1
    echo "listo: $out"
}

case "${1:-todos}" in
    requests|todos) run requests 150 "/api/drug" "" ./load-requests.sh 300 20 ;;&
    cpu|todos) run cpu 200 "/api/drug /api/roles" "" ./cpu-spike.sh pharmago-api-gateway 120 4 ;;&
    memoria|todos) run memoria 200 "/api/drug /api/roles" "" ./ram-spike.sh pharmago-pharmacy-service 250 150 ;;&
    storage|todos) run storage 210 "/api/roles /api/drug" "" ./volume-spike.sh pharmago-users-service 400 150 ;;&
    red|todos) run red 170 "/api/drug /api/roles" "/api/roles" ./network-chaos.sh pharmago-users-service 60 ;;&
    desconexion|todos) run desconexion 170 "/api/drug /api/roles" "/api/drug" ./disconnect.sh pharmago-pharmacy-service 60 ;;
esac
