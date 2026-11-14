#!/bin/bash
# Construye las 4 imágenes propias y las carga en todos los nodos de Minikube.
# Uso: ./build-images.sh [tag]
#   Sin tag usa el SHA corto de git del commit actual (D21), con sufijo -dirty si hay cambios sin commitear.
#   apply-k8s.sh y deploy.sh usan el mismo tag.

set -e
export MINIKUBE_IN_STYLE=false   # salida de minikube en texto plano, sin emojis

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CODE_DIR="$(dirname "$SCRIPT_DIR")"

image_tag() {
    local sha
    sha=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
    if git -C "$SCRIPT_DIR" diff --quiet HEAD --; then echo "$sha"; else echo "${sha}-dirty"; fi
}
TAG="${1:-$(image_tag)}"

echo "=== Construyendo y cargando imágenes en Minikube (tag: ${TAG}) ==="

if ! command -v docker &> /dev/null; then
    echo "Error: Docker no está instalado o no está en el PATH"
    exit 1
fi
if ! minikube status &> /dev/null; then
    echo "Error: Minikube no está corriendo. Ejecuta: ./cluster-up.sh"
    exit 1
fi

build() {
    local image="$1" dockerfile="$2" context="$3"
    echo ""
    echo "  - ${image}:${TAG}"
    docker build -f "$dockerfile" -t "${image}:${TAG}" "$context"
    minikube image load "${image}:${TAG}"
}

cd "$CODE_DIR/Backend"
build pharmago-users-service PharmaGo.UsersService/Dockerfile .
build pharmago-pharmacy-service PharmaGo.PharmacyService/Dockerfile .
build pharmago-api-gateway PharmaGo.ApiGateway/Dockerfile .

cd "$CODE_DIR/Frontend"
build pharmago-ui Dockerfile .

echo ""
echo "=== Imágenes construidas y cargadas ==="
minikube image ls | grep "pharmago-.*:${TAG}$" || true
echo ""
echo "Siguiente paso: ./apply-k8s.sh ${TAG}   (primera vez)   o   ./deploy.sh ${TAG}   (actualizar sin caídas)"

cd "$SCRIPT_DIR"
