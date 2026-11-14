#!/bin/bash
# Despliega una versión nueva de los 4 microservicios con RollingUpdate, uno por uno (C08).
# Uso: ./deploy.sh <tag>      (el tag que usó build-images.sh, por ejemplo 3f2a1bc)
# Orden: users, pharmacy, gateway y ui. Si un rollout no termina en 180 s, vuelve ese Deployment
# a la revisión anterior y termina con error, sin tocar los que siguen.

set -uo pipefail
export MINIKUBE_IN_STYLE=false

NS=pharmago
APPS=(pharmago-users-service pharmago-pharmacy-service pharmago-api-gateway pharmago-ui)
TAG="${1:-}"

if [ -z "$TAG" ]; then
    echo "Uso: $0 <tag>"
    exit 1
fi
if [ "$(kubectl config current-context 2>/dev/null)" != "minikube" ]; then
    echo "Error: el contexto de kubectl no es minikube."
    exit 1
fi

IMAGES=$(minikube image ls 2>/dev/null)
for app in "${APPS[@]}"; do
    if ! grep -q "/${app}:${TAG}$" <<< "$IMAGES"; then
        echo "Error: falta la imagen ${app}:${TAG} en Minikube. Corré ./build-images.sh ${TAG}"
        exit 1
    fi
done

for app in "${APPS[@]}"; do
    echo "$(date -u +%H:%M:%S) ${app} -> ${TAG}"
    # change-cause queda en "kubectl rollout history": así se ve qué tag tiene cada revisión.
    kubectl annotate "deployment/${app}" kubernetes.io/change-cause="deploy.sh ${TAG}" --overwrite -n "$NS" > /dev/null
    kubectl set image "deployment/${app}" "${app}=${app}:${TAG}" -n "$NS"
    if ! kubectl rollout status "deployment/${app}" -n "$NS" --timeout=180s; then
        echo "Error: el rollout de ${app} no terminó en 180 s. Volviendo a la revisión anterior..."
        kubectl rollout undo "deployment/${app}" -n "$NS"
        kubectl rollout status "deployment/${app}" -n "$NS" --timeout=180s
        exit 1
    fi
done

echo "$(date -u +%H:%M:%S) Listo: los 4 microservicios corren ${TAG}."
kubectl get deploy -n "$NS" "${APPS[@]}" -o custom-columns=DEPLOYMENT:.metadata.name,LISTOS:.status.readyReplicas,IMAGEN:.spec.template.spec.containers[0].image
