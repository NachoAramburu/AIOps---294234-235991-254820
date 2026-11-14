#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
    echo "Uso: $0 <deployment> <segundos>"
    echo "Ejemplo: $0 pharmago-users-service 45"
    echo "Aplica una NetworkPolicy que niega todo el tráfico de entrada y salida de los pods del Deployment."
    exit 1
}

[ $# -ge 2 ] || usage
DEP="$1"
SECS="$2"
POLICY="chaos-deny-${DEP}"
require_int segundos "$SECS"
require_context
require_deployment "$DEP"

EXISTING=$(kubectl get networkpolicy -n "$NS" -o name 2>/dev/null | grep '/chaos-' || true)
[ -z "$EXISTING" ] || die "ya hay una NetworkPolicy de caos aplicada: $EXISTING. Borrala antes de empezar otra."

APPLIED=0
cleanup() {
    set +e
    trap - EXIT
    if [ "$APPLIED" -eq 1 ]; then
        kubectl delete networkpolicy "$POLICY" -n "$NS" --ignore-not-found >/dev/null
        echo "NetworkPolicy $POLICY borrada."
    fi
    echo "NetworkPolicies de caos que quedan: $(kubectl get networkpolicy -n "$NS" -o name 2>/dev/null | grep -c '/chaos-')"
    marca_tiempo fin
}
trap cleanup EXIT
trap 'exit 130' INT TERM

marca_tiempo inicio
echo "Red: se corta todo el tráfico de app=$DEP durante $SECS s"
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${POLICY}
  namespace: ${NS}
  labels:
    chaos: "true"
spec:
  podSelector:
    matchLabels:
      app: ${DEP}
  policyTypes:
  - Ingress
  - Egress
EOF
APPLIED=1
for _ in $(seq 1 "$SECS"); do sleep 1; done
