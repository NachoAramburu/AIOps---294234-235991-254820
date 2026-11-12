#!/bin/bash
# Crea (o reutiliza) el cluster Minikube de 5 nodos de PharmaGo y etiqueta cada nodo.
# Idempotente: si el cluster ya existe lo arranca si hace falta, y vuelve a aplicar addons y etiquetas.
# Uso: ./cluster-up.sh            (desde Git Bash, cualquier directorio)
#      MINIKUBE_MEMORY=4608 ./cluster-up.sh   (memoria por nodo en MB, solo al crear)
#
# Arquitectura (AGENTS.md §4 / docs/DECISIONES.md D01):
#   minikube     -> node-type=frontend  (UI, ingress)
#   minikube-m02 -> node-type=gateway
#   minikube-m03 -> node-type=users
#   minikube-m04 -> node-type=pharmacy
#   minikube-m05 -> node-type=ops       (BD y observabilidad)

set -euo pipefail
export MINIKUBE_IN_STYLE=false   # salida de minikube en texto plano, sin emojis

PROFILE="minikube"
NODES=5
CPUS="${MINIKUBE_CPUS:-2}"
MEMORY="${MINIKUBE_MEMORY:-4096}"
K8S_VERSION="v1.33.13"

echo "=== Cluster Minikube de PharmaGo (${NODES} nodos) ==="
echo "Verificando herramientas y Docker..."

for cmd in docker minikube kubectl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd no está instalado o no está en el PATH"
        exit 1
    fi
done

if ! docker info &> /dev/null; then
    echo "Error: Docker no responde. Abrí Docker Desktop y esperá a que diga que está corriendo."
    exit 1
fi

echo "Buscando si el cluster ya existe (puede tardar unos segundos)..."
if minikube profile list -o json 2>/dev/null | grep -q "\"Name\":\"${PROFILE}\""; then
    echo "El cluster '${PROFILE}' ya existe."
    if ! minikube status -p "$PROFILE" &> /dev/null; then
        echo "No está corriendo: arrancando los ${NODES} nodos (unos 3 a 5 minutos)..."
        minikube start -p "$PROFILE"
    fi
else
    echo "Creando cluster: ${NODES} nodos, ${CPUS} CPU y ${MEMORY} MB por nodo, Kubernetes ${K8S_VERSION}..."
    minikube start -p "$PROFILE" \
        --driver=docker \
        --container-runtime=docker \
        --cni=calico \
        --kubernetes-version="$K8S_VERSION" \
        --nodes "$NODES" \
        --cpus "$CPUS" \
        --memory "$MEMORY"
fi

echo ""
echo "Habilitando addon metrics-server..."
minikube addons enable metrics-server -p "$PROFILE"

echo ""
echo "Habilitando addon ingress (acceso a la app sin port-forward)..."
minikube addons enable ingress -p "$PROFILE"

echo ""
echo "Etiquetando nodos (node-type)..."
label() {
    local node="$1" type="$2"
    if kubectl get node "$node" &> /dev/null; then
        kubectl label node "$node" "node-type=${type}" --overwrite
    else
        echo "Error: no existe el nodo $node. ¿El cluster tiene ${NODES} nodos?"
        exit 1
    fi
}
label minikube     frontend
label minikube-m02 gateway
label minikube-m03 users
label minikube-m04 pharmacy
label minikube-m05 ops

echo ""
echo "Esperando a que todos los nodos estén Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo ""
kubectl get nodes -L node-type
echo ""
echo "Siguiente paso: ./build-images.sh, ./apply-k8s.sh y ./seed-db.sh"
echo "Para entrar a la app: en PowerShell como administrador, minikube tunnel (dejalo abierto) y abrí http://127.0.0.1/"
