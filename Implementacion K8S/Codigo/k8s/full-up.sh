#!/bin/bash

set -euo pipefail
export MINIKUBE_IN_STYLE=false

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CHAOS_DIR="$(dirname "$SCRIPT_DIR")/chaos-engineering"
NS=pharmago
APPS=(pharmago-users-service pharmago-pharmacy-service pharmago-api-gateway pharmago-ui)
TUNNEL_WAIT="${TUNNEL_WAIT:-300}"
STEADY_TRIES="${STEADY_TRIES:-6}"

image_tag() {
    local sha
    sha=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
    if git -C "$SCRIPT_DIR" diff --quiet HEAD --; then echo "$sha"; else echo "${sha}-dirty"; fi
}
TAG="${1:-$(image_tag)}"

START=$(date +%s)
SUMMARY=()

step() {
    local name="$1"
    shift
    local t0 t1
    t0=$(date +%s)
    echo ""
    echo "=== $(date -u +%H:%M:%S) ${name} ==="
    "$@"
    t1=$(date +%s)
    SUMMARY+=("$(printf '%-28s %4d s' "$name" $((t1 - t0)))")
}

wait_apps() {
    for app in "${APPS[@]}"; do
        kubectl rollout status "deployment/${app}" -n "$NS" --timeout=300s
    done
    kubectl rollout status deployment/pharmago-db -n "$NS" --timeout=300s
}

wait_tunnel() {
    local waited=0
    until curl -s -o /dev/null --max-time 3 http://127.0.0.1/; do
        if [ "$waited" -eq 0 ]; then
            echo "http://127.0.0.1 no responde. Abrí minikube tunnel en PowerShell como administrador."
        fi
        if [ "$waited" -ge "$TUNNEL_WAIT" ]; then
            echo "Error: el tunnel no respondió en ${TUNNEL_WAIT} s."
            return 1
        fi
        sleep 5
        waited=$((waited + 5))
    done
    echo "http://127.0.0.1 responde."
}

steady() {
    local try
    for try in $(seq "$STEADY_TRIES"); do
        if bash "$CHAOS_DIR/steady-state.sh" 20; then
            return 0
        fi
        echo "Intento ${try} de ${STEADY_TRIES} sin steady state. Se repite en 30 s (las alertas del arranque tardan en volver a Normal)."
        sleep 30
    done
    return 1
}

step "cluster-up.sh" bash "$SCRIPT_DIR/cluster-up.sh"
step "build-images.sh ${TAG}" bash "$SCRIPT_DIR/build-images.sh" "$TAG"
step "apply-k8s.sh ${TAG}" bash "$SCRIPT_DIR/apply-k8s.sh" "$TAG"
step "rollout de la app" wait_apps
step "seed-db.sh" bash "$SCRIPT_DIR/seed-db.sh"
step "setup-kibana.sh" bash "$SCRIPT_DIR/setup-kibana.sh"
step "minikube tunnel" wait_tunnel
step "steady-state.sh" steady
step "check-separacion.sh" bash "$SCRIPT_DIR/verify/check-separacion.sh"

echo ""
echo "=== Resumen (tag ${TAG}) ==="
printf '%s\n' "${SUMMARY[@]}"
echo "Total: $(( $(date +%s) - START )) s"
echo ""
echo "App: http://127.0.0.1/   Herramientas: ./port-forward.sh"
