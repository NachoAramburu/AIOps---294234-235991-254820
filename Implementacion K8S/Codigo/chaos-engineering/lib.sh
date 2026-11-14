#!/bin/bash

set -euo pipefail
export MSYS_NO_PATHCONV=1
export MINIKUBE_IN_STYLE=false

NS=pharmago

die() {
    echo "Error: $*" >&2
    exit 1
}

require_int() {
    local name="$1" value="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -le 0 ]; then
        die "$name tiene que ser un entero positivo (recibido: '$value')"
    fi
}

require_context() {
    local ctx
    ctx=$(kubectl config current-context 2>/dev/null || true)
    [ "$ctx" = "minikube" ] || die "el contexto de kubectl es '$ctx'; los experimentos solo corren contra minikube"
}

require_deployment() {
    kubectl get deploy "$1" -n "$NS" >/dev/null 2>&1 || die "no existe el Deployment $1 en el namespace $NS"
}

pick_pod() {
    local pod
    pod=$(kubectl get pods -n "$NS" -l app="$1" \
        -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.containerStatuses[0].ready}{"|"}{.metadata.deletionTimestamp}{"\n"}{end}' \
        | awk -F'|' '$2 == "true" && $3 == "" { print $1; exit }')
    [ -n "$pod" ] || die "no hay pods Ready de $1"
    echo "$pod"
}

marca_tiempo() {
    echo "[$1] $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

kill_marked() {
    local pod="$1" marker="$2"
    kubectl exec -n "$NS" "$pod" -- sh -c "
        m='${marker%?}'; m=\"\${m}${marker: -1}\"
        for p in /proc/[0-9]*; do
            pid=\${p#/proc/}
            [ \"\$pid\" = \"\$\$\" ] && continue
            grep -q \"\$m\" \"\$p/cmdline\" 2>/dev/null && kill \"\$pid\" 2>/dev/null
        done
        true" >/dev/null 2>&1 || true
}

count_marked() {
    local pod="$1" marker="$2"
    kubectl exec -n "$NS" "$pod" -- sh -c "
        m='${marker%?}'; m=\"\${m}${marker: -1}\"; n=0
        for p in /proc/[0-9]*; do
            [ \"\${p#/proc/}\" = \"\$\$\" ] && continue
            grep -q \"\$m\" \"\$p/cmdline\" 2>/dev/null && n=\$((n+1))
        done
        echo \$n" 2>/dev/null || echo "?"
}
