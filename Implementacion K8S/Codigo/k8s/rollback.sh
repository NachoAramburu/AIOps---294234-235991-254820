#!/bin/bash
# Vuelve a la revisión anterior de los microservicios (C08).
# Uso: ./rollback.sh                 (los 4: ui, gateway, pharmacy y users)
#      ./rollback.sh pharmago-ui     (solo uno)

set -uo pipefail

NS=pharmago
APPS=(pharmago-ui pharmago-api-gateway pharmago-pharmacy-service pharmago-users-service)

if [ "$(kubectl config current-context 2>/dev/null)" != "minikube" ]; then
    echo "Error: el contexto de kubectl no es minikube."
    exit 1
fi

if [ $# -ge 1 ]; then
    valid=0
    for app in "${APPS[@]}"; do
        [ "$app" = "$1" ] && valid=1
    done
    if [ "$valid" -ne 1 ]; then
        echo "Error: '$1' no es uno de: ${APPS[*]}"
        exit 1
    fi
    APPS=("$1")
fi

fail=0
for app in "${APPS[@]}"; do
    echo "$(date -u +%H:%M:%S) rollback de ${app}"
    if ! kubectl rollout undo "deployment/${app}" -n "$NS"; then
        fail=1
        continue
    fi
    kubectl rollout status "deployment/${app}" -n "$NS" --timeout=180s || fail=1
done

kubectl get deploy -n "$NS" "${APPS[@]}" -o custom-columns=DEPLOYMENT:.metadata.name,LISTOS:.status.readyReplicas,IMAGEN:.spec.template.spec.containers[0].image
exit "$fail"
