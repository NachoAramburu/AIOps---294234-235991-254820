#!/bin/bash
# Verifica que ningún nodo aloje pods de dos microservicios distintos (letra, ítem Plataforma).
# Las réplicas de un mismo microservicio sí pueden compartir nodo (decisión D02).
# Uso: bash check-separacion.sh   (desde Git Bash, cualquier directorio)
# Sale con 0 si la separación se cumple y con 1 si algún nodo mezcla microservicios.

set -euo pipefail

NS="pharmago"
APPS="pharmago-api-gateway,pharmago-users-service,pharmago-pharmacy-service,pharmago-ui"

# Una línea por pod: <app> <nodo> <pod> <fase>. Un pod sin nodo asignado (Pending) muestra "-".
PODS=$(kubectl get pods -n "$NS" -l "app in ($APPS)" \
    -o jsonpath='{range .items[*]}{.metadata.labels.app}{" "}{.spec.nodeName}{" "}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' \
    | awk 'NF == 3 { print $1, "-", $2, $3; next } NF == 4 { print }')

if [ -z "$PODS" ]; then
    echo "Error: no hay pods de los microservicios en el namespace $NS."
    exit 1
fi

echo "=== Pods por microservicio y nodo ==="
{ echo "MICROSERVICIO NODO POD FASE"; echo "$PODS" | sort; } | column -t

# Por nodo: lista de microservicios distintos que aloja.
POR_NODO=$(echo "$PODS" | awk '$2 != "-" { print $2, $1 }' | sort -u | awk '
    { apps[$1] = apps[$1] (apps[$1] ? "," : "") $2; n[$1]++ }
    END { for (node in apps) print node, apps[node], (n[node] > 1 ? "VIOLACION" : "ok") }' | sort)

echo ""
echo "=== Microservicios por nodo ==="
{ echo "NODO MICROSERVICIOS ESTADO"; echo "$POR_NODO"; } | column -t

PENDING=$(echo "$PODS" | awk '$2 == "-"' | wc -l | tr -d ' ')
if [ "$PENDING" -gt 0 ]; then
    echo ""
    echo "Aviso: $PENDING pod(s) sin nodo asignado (Pending). No cuentan como violación."
fi

BAD=$(echo "$POR_NODO" | awk '$3 == "VIOLACION"' | wc -l | tr -d ' ')
echo ""
if [ "$BAD" -gt 0 ]; then
    echo "FALLA: $BAD nodo(s) alojan pods de más de un microservicio."
    exit 1
fi
echo "OK: ningún nodo aloja dos microservicios distintos."
