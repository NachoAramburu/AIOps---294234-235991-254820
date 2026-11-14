#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Uso: $0 [--segundos N]   (N por defecto: 30)"
    echo "Corre los 6 tipos de caos en secuencia y espera entre cada uno a que todo vuelva a Ready."
    exit 1
}

SECS=30
while [ $# -gt 0 ]; do
    case "$1" in
        --segundos) [ $# -ge 2 ] || usage; SECS="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
done
require_int segundos "$SECS"
require_context

APPS=(pharmago-db pharmago-users-service pharmago-pharmacy-service pharmago-api-gateway pharmago-ui)
EXPERIMENTS=(
    "requests|load-requests.sh 200 10"
    "cpu|cpu-spike.sh pharmago-api-gateway $SECS 4"
    "memoria|ram-spike.sh pharmago-pharmacy-service 150 $SECS"
    "storage|volume-spike.sh pharmago-users-service 200 $SECS"
    "red|network-chaos.sh pharmago-users-service $SECS"
    "desconexion|disconnect.sh pharmago-pharmacy-service $SECS"
)
RESULTS=()

wait_ready() {
    local d ok=0
    for d in "${APPS[@]}"; do
        kubectl rollout status deploy/"$d" -n "$NS" --timeout=300s >/dev/null 2>&1 || ok=1
    done
    return "$ok"
}

print_table() {
    echo
    printf "%-12s %-20s %-20s %s\n" TIPO INICIO FIN "ESTADO FINAL"
    local r
    for r in "${RESULTS[@]}"; do
        IFS='|' read -r t s e st <<< "$r"
        printf "%-12s %-20s %-20s %s\n" "$t" "$s" "$e" "$st"
    done
}

on_exit() {
    set +e
    trap - EXIT
    print_table
}
trap on_exit EXIT
trap 'exit 130' INT TERM

echo "Esperando que todos los Deployments estén Ready antes de empezar..."
wait_ready || die "hay Deployments que no están Ready; no se empieza"

for exp in "${EXPERIMENTS[@]}"; do
    type="${exp%%|*}"
    cmd="${exp#*|}"
    echo
    echo "=== $type: ./$cmd"
    start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    rc=0
    bash "$DIR"/$cmd || rc=$?
    echo "Esperando que todos los Deployments vuelvan a Ready..."
    if wait_ready; then state="OK (exit $rc, todo Ready)"; else state="FALLA (exit $rc, quedó algo sin Ready)"; fi
    end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    RESULTS+=("$type|$start|$end|$state")
done
