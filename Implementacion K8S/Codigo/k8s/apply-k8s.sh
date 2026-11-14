#!/bin/bash
# Script de despliegue para Kubernetes (Minikube)
# Uso: ./apply-k8s.sh [tag] (se puede correr desde cualquier directorio)
#   Sin tag usa el mismo que build-images.sh: el SHA corto de git, con -dirty si hay cambios sin commitear.
# Requiere el cluster multinodo creado y etiquetado por cluster-up.sh.

set -e
export MINIKUBE_IN_STYLE=false   # salida de minikube en texto plano, sin emojis

# Trabajar siempre desde el directorio del script, para que las rutas relativas funcionen
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Tag de las imágenes propias (D21). Los manifiestos de la app tienen IMAGE_TAG y apply_app lo reemplaza.
image_tag() {
    local sha
    sha=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
    if git -C "$SCRIPT_DIR" diff --quiet HEAD --; then echo "$sha"; else echo "${sha}-dirty"; fi
}
TAG="${1:-$(image_tag)}"
apply_app() { sed "s/IMAGE_TAG/${TAG}/g" "$1" | kubectl apply -f -; }

echo "=== Desplegando PharmaGo en Kubernetes ==="

# Verificar que kubectl está disponible
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl no está instalado o no está en el PATH"
    exit 1
fi

# Verificar que minikube está corriendo
if ! minikube status &> /dev/null; then
    echo "Error: Minikube no está corriendo."
    echo "Ejecuta: ./cluster-up.sh"
    exit 1
fi

echo "Tag de las imágenes propias: ${TAG}"
IMAGES=$(minikube image ls 2>/dev/null)
for img in pharmago-users-service pharmago-pharmacy-service pharmago-api-gateway pharmago-ui; do
    if ! grep -q "/${img}:${TAG}$" <<< "$IMAGES"; then
        echo "Error: falta la imagen ${img}:${TAG} en Minikube. Corré ./build-images.sh ${TAG}"
        exit 1
    fi
done

# Los nodos los etiqueta cluster-up.sh (node-type=frontend|gateway|users|pharmacy|ops).
if ! kubectl get nodes -l node-type=ops -o name 2>/dev/null | grep -q .; then
    echo "Error: ningún nodo tiene node-type=ops. Ejecuta primero: ./cluster-up.sh"
    exit 1
fi

echo ""
echo "1. Nodos y etiquetas:"
kubectl get nodes -L node-type

echo ""
echo "2. Creando namespace..."
kubectl apply -f namespace.yaml

echo ""
echo "3. Creando secrets..."
kubectl apply -f secrets/db-secret.yaml

echo ""
echo "4. Creando configmaps..."
kubectl apply -f configmaps/prometheus-config.yaml
kubectl apply -f configmaps/otel-collector-config.yaml
kubectl apply -f configmaps/grafana-provisioning.yaml
kubectl apply -f configmaps/grafana-dashboards.yaml
kubectl apply -f configmaps/grafana-dashboard-infra.yaml
kubectl apply -f configmaps/fluent-bit-config.yaml

echo ""
echo "5. Creando StorageClass y PersistentVolumes..."
kubectl apply -f persistent-volumes/storage-class.yaml

# Eliminar solo PVs en estado Released (huérfanos tras borrar el namespace).
# No intentar borrar PVs Bound: kubectl delete se bloquearía indefinidamente.
echo "   Limpiando PVs huérfanos (Released)..."
for pv in sql-pv elasticsearch-pv prometheus-pv grafana-pv; do
  status=$(kubectl get pv $pv -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
  if [ "$status" = "Released" ] || [ "$status" = "Failed" ]; then
    kubectl delete pv $pv --ignore-not-found=true 2>/dev/null || true
  fi
done
sleep 2

kubectl apply -f persistent-volumes/sql-pv.yaml
kubectl apply -f persistent-volumes/elasticsearch-pv.yaml
kubectl apply -f persistent-volumes/prometheus-pv.yaml
kubectl apply -f persistent-volumes/grafana-pv.yaml

echo ""
echo "6. Desplegando base de datos..."
kubectl apply -f services/ops/db-service.yaml
kubectl apply -f deployments/ops/db-deployment.yaml

echo ""
echo "   Esperando a que la base de datos esté lista..."
timeout=0
max_timeout=300
while [ $timeout -lt $max_timeout ]; do
    pod_ready=$(kubectl get pod -l app=pharmago-db -n pharmago -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$pod_ready" = "True" ]; then
        echo "   Base de datos lista!"
        break
    fi
    sleep 5
    timeout=$((timeout + 5))
    echo "   Esperando... ($timeout/$max_timeout segundos)"
done
if [ $timeout -ge $max_timeout ]; then
    echo "   Timeout esperando la base de datos. Continuando..."
fi

echo ""
echo "7. Desplegando servicios de observabilidad..."
# Elasticsearch primero
kubectl apply -f services/ops/elasticsearch-service.yaml
kubectl apply -f deployments/ops/elasticsearch-deployment.yaml

# Esperar a que Elasticsearch esté listo
echo "   Esperando a que Elasticsearch esté listo..."
timeout=0
max_timeout=300
while [ $timeout -lt $max_timeout ]; do
    pod_ready=$(kubectl get pod -l app=elasticsearch -n pharmago -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$pod_ready" = "True" ]; then
        echo "   Elasticsearch listo!"
        break
    fi
    sleep 5
    timeout=$((timeout + 5))
    echo "   Esperando... ($timeout/$max_timeout segundos)"
done
if [ $timeout -ge $max_timeout ]; then
    echo "   Timeout esperando Elasticsearch. Continuando..."
fi

# Resto de servicios ops
kubectl apply -f services/ops/otel-collector-service.yaml
kubectl apply -f deployments/ops/otel-collector-deployment.yaml

kubectl apply -f deployments/ops/prometheus-serviceaccount.yaml
kubectl apply -f deployments/ops/prometheus-clusterrole.yaml
kubectl apply -f deployments/ops/prometheus-clusterrolebinding.yaml
kubectl apply -f services/ops/prometheus-service.yaml
kubectl apply -f deployments/ops/prometheus-deployment.yaml
kubectl apply -f services/ops/node-exporter-service.yaml
kubectl apply -f deployments/ops/node-exporter-daemonset.yaml

kubectl apply -f services/ops/grafana-service.yaml
kubectl apply -f deployments/ops/grafana-deployment.yaml

kubectl apply -f services/ops/kibana-service.yaml
kubectl apply -f deployments/ops/kibana-deployment.yaml

# Fluent Bit: recolecta logs de pods y los envía a Elasticsearch (pharmago-logs-*)
kubectl apply -f deployments/ops/fluent-bit-serviceaccount.yaml
kubectl apply -f deployments/ops/fluent-bit-clusterrole.yaml
kubectl apply -f deployments/ops/fluent-bit-clusterrolebinding.yaml
kubectl apply -f deployments/ops/fluent-bit-daemonset.yaml

echo ""
echo "8. Desplegando servicios backend..."
kubectl apply -f services/backend/users-service-service.yaml
apply_app deployments/backend/users-service-deployment.yaml

kubectl apply -f services/backend/pharmacy-service-service.yaml
apply_app deployments/backend/pharmacy-service-deployment.yaml

kubectl apply -f services/backend/api-gateway-service.yaml
apply_app deployments/backend/api-gateway-deployment.yaml

echo ""
echo "9. Desplegando frontend..."
kubectl apply -f services/frontend/ui-service.yaml
apply_app deployments/frontend/ui-deployment.yaml

echo ""
echo "10. Creando PodDisruptionBudgets (al menos 1 réplica disponible por microservicio)..."
kubectl apply -f pdb/

echo ""
echo "11. Configurando Ingress (acceso a la app sin port-forward)..."
if ! kubectl get namespace ingress-nginx &> /dev/null; then
    echo "Error: falta el addon ingress. Corré ./cluster-up.sh y volvé a intentar."
    exit 1
fi
echo "   Esperando al controlador de ingress-nginx (su webhook tiene que estar listo)..."
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller --timeout=180s
kubectl apply -f ingress/pharmago-ingress.yaml

echo ""
echo "=== Despliegue completado ==="
echo ""
echo "Verificando estado de los pods..."
kubectl get pods -n pharmago -o wide

echo ""
echo "Para entrar a la app (sin port-forward):"
echo "  1. En PowerShell como administrador: minikube tunnel   (dejalo abierto)"
echo "  2. Abrí http://127.0.0.1/   (la API queda en http://127.0.0.1/api/...)"
echo ""
echo "Herramientas de operación (Prometheus, Grafana, Kibana, Elasticsearch):"
echo "  ./port-forward.sh"

