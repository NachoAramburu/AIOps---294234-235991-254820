#!/bin/bash
# Verifica el steady state de PharmaGo antes y después de cada experimento (C18).
# Uso: ./steady-state.sh [segundos=20]
#   1. Deployments: los 4 microservicios 2/2 y la BD 1/1.
#   2. Nodos: todos Ready.
#   3. Tráfico: loop a 1 request/s por el Ingress (/api/drug, /api/roles y /), 0 respuestas no-2xx.
#   4. Alertas: ninguna alerta de Grafana en Firing.
# Sale con 0 si todo está bien y con la cantidad de chequeos fallidos si no.
# Requiere minikube tunnel (http://127.0.0.1). La contraseña de Grafana no pasa por este script:
# la consulta corre dentro del pod de Grafana con su propia variable de entorno.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set +e   # cada chequeo informa su resultado; no cortar en el primero que falle

usage() {
    echo "Uso: $0 [segundos=20]"
    exit 1
}

SECS="${1:-20}"
[ "$SECS" = "-h" ] || [ "$SECS" = "--help" ] && usage
require_int segundos "$SECS"
require_context
command -v curl >/dev/null || die "falta curl"

BASE_URL="${BASE_URL:-http://127.0.0.1}"
PATHS=(/api/drug /api/roles /)
FAILS=0

ok()    { echo "  [OK]    $*"; }
falla() { echo "  [FALLA] $*"; FAILS=$((FAILS + 1)); }

marca_tiempo inicio
echo "Steady state de PharmaGo (namespace $NS)"

echo
echo "1. Deployments"
check_deploy() {
    local d="$1" want="$2" ready
    ready=$(kubectl get deploy "$d" -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    ready="${ready:-0}"
    if [ "$ready" = "$want" ]; then ok "$d $ready/$want"; else falla "$d $ready/$want Ready"; fi
}
for d in pharmago-api-gateway pharmago-users-service pharmago-pharmacy-service pharmago-ui; do
    check_deploy "$d" 2
done
check_deploy pharmago-db 1

echo
echo "2. Nodos"
NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}')
TOTAL=$(grep -c . <<< "$NODES")
NOT_READY=$(awk -F'|' '$2 != "True" { print $1 }' <<< "$NODES" | tr '\n' ' ')
if [ -z "$NOT_READY" ] && [ "$TOTAL" -gt 0 ]; then ok "$TOTAL/$TOTAL nodos Ready"; else falla "nodos no Ready: ${NOT_READY:-ninguno listado}"; fi

echo
echo "3. Tráfico: $SECS s a 1 request/s por $BASE_URL (${PATHS[*]})"
CODES=()
BAD=0
for i in $(seq 0 $((SECS - 1))); do
    t0=$(date +%s%N)
    p="${PATHS[$((i % ${#PATHS[@]}))]}"
    code=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$BASE_URL$p")
    CODES+=("$code")
    case "$code" in 2??) ;; *) BAD=$((BAD + 1)); echo "    $(date -u +%T) $p -> $code" ;; esac
    # completar el segundo, para no pasar de 1 request/s (rate limit)
    elapsed=$(( ($(date +%s%N) - t0) / 1000000 ))
    [ "$elapsed" -lt 1000 ] && sleep "0.$(printf '%03d' $((1000 - elapsed)))"
done
SUMMARY=$(printf '%s\n' "${CODES[@]}" | sort | uniq -c | awk '{ printf "%s x%s  ", $2, $1 }')
if [ "$BAD" -eq 0 ]; then ok "0 no-2xx de $SECS ($SUMMARY)"; else falla "$BAD no-2xx de $SECS ($SUMMARY)"; fi

echo
echo "4. Alertas de Grafana"
# /metrics de Grafana es público (no usa credenciales) y cuenta las instancias de alerta por estado.
# "alerting" es Firing. Si alguna está en Firing, se buscan los uid con la API (necesita la contraseña
# de admin del manifiesto: la consulta corre dentro del pod, con su propia variable de entorno).
GMETRICS=$(kubectl exec -n "$NS" deploy/grafana -c grafana -- curl -s -m 5 http://localhost:3000/metrics 2>/dev/null)
gcount() { awk -v s="$1" -F'[{}" ]+' '$1 == "grafana_alerting_alerts" && $3 == s { print $NF }' <<< "$GMETRICS"; }
FIRING=$(gcount alerting); NORMAL=$(gcount normal); PENDING=$(gcount pending)
if [ -z "$FIRING" ]; then
    falla "no se pudo leer el estado de las alertas en Grafana"
elif [ "${NORMAL:-0}" -eq 0 ]; then
    falla "Grafana no tiene reglas cargadas (0 instancias en Normal)"
elif [ "$FIRING" -eq 0 ]; then
    ok "ninguna alerta en Firing (Normal: $NORMAL, Pending: ${PENDING:-0})"
else
    UIDS=$(kubectl exec -n "$NS" deploy/grafana -c grafana -- sh -c \
        'curl -s -m 5 -u "admin:$GF_SECURITY_ADMIN_PASSWORD" http://localhost:3000/api/prometheus/grafana/api/v1/rules' 2>/dev/null \
        | grep -o '"state":"firing","name":"[^:"]*' | cut -d'"' -f8 | tr '\n' ' ')
    falla "$FIRING instancia(s) de alerta en Firing ${UIDS:+($UIDS)}"
fi

echo
marca_tiempo fin
if [ "$FAILS" -eq 0 ]; then
    echo "RESULTADO: steady state OK"
else
    echo "RESULTADO: steady state con $FAILS chequeo(s) fallido(s)"
fi
exit "$FAILS"
