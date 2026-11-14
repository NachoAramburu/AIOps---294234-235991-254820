#!/bin/bash
# Observa un experimento de caos (C18): lo que ve el usuario y el estado de las alertas, con hora UTC.
# Uso: ./observar.sh <segundos> [ruta ...]   (rutas por defecto: /api/drug /api/roles /)
#   - Cada segundo hace 1 request por el Ingress, rotando las rutas (no pasa de 1 request/s: rate limit).
#     Imprime "HH:MM:SS http <ruta> <código> <ms>". Si una request tarda, la siguiente sale al terminar.
#   - Cada 5 s imprime las alertas de Grafana que no están en Normal: "HH:MM:SS alertas <uid>=<estado> ...".
#   - Al final, el conteo por código HTTP y la primera vez que cada alerta pasó a Pending y a Firing.
# Se corre en otra terminal (o en segundo plano) mientras corre el script de caos.
# Requiere minikube tunnel. La consulta a Grafana corre dentro de su pod, con su variable de entorno.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set +e

usage() {
    echo "Uso: $0 <segundos> [ruta ...]"
    echo "Ejemplo: $0 120 /api/drug"
    exit 1
}

[ $# -ge 1 ] || usage
SECS="$1"; shift
require_int segundos "$SECS"
require_context
PATHS=("$@")
[ ${#PATHS[@]} -gt 0 ] || PATHS=(/api/drug /api/roles /)
BASE_URL="${BASE_URL:-http://127.0.0.1}"
# Timeout del cliente: mayor que los 2 intentos de 3 s del gateway (D13), para ver el código que devuelve el
# gateway (504, 503) y no un corte del propio cliente (000). Se cambia con TIMEOUT=<s>.
TIMEOUT="${TIMEOUT:-10}"

LOG=$(mktemp)
PIDS=()
cleanup() {
    trap - EXIT
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
    wait 2>/dev/null
    echo
    echo "Resumen ($SECS s):"
    echo "  Respuestas por código HTTP:"
    awk '$2 == "http" { print $4 }' "$LOG" | sort | uniq -c | sort -rn | awk '{ printf "    %s x%s\n", $2, $1 }'
    awk '$2 == "http" && $4 !~ /^2/ { n++; if (!f) f = $1; l = $1 } END { if (n) printf "  no-2xx: %d, primero %s, último %s\n", n, f, l; else print "  no-2xx: 0" }' "$LOG"
    echo "  Alertas (primera vez en cada estado):"
    awk '$2 == "alertas" { for (i = 3; i <= NF; i++) { split($i, a, "="); k = a[1] " " a[2]; if (!(k in s)) { s[k] = $1; o[++n] = k } } }
         END { if (!n) print "    ninguna salió de Normal"; for (i = 1; i <= n; i++) printf "    %-20s %s\n", o[i], s[o[i]] }' "$LOG"
    rm -f "$LOG"
    marca_tiempo fin
}
trap cleanup EXIT
trap 'exit 130' INT TERM

alert_states() {
    kubectl exec -n "$NS" deploy/grafana -c grafana -- sh -c \
        'curl -s -m 4 -u "admin:$GF_SECURITY_ADMIN_PASSWORD" http://localhost:3000/api/prometheus/grafana/api/v1/rules' 2>/dev/null \
        | grep -o '"state":"[a-z]*","name":"[^:"]*' | awk -F'"' '$4 != "inactive" { printf "%s=%s ", $8, $4 }'
}

marca_tiempo inicio
echo "Observando $SECS s: tráfico a 1 request/s por $BASE_URL (${PATHS[*]}) y alertas de Grafana cada 5 s"

(
    for i in $(seq 0 $((SECS - 1))); do
        t0=$(date +%s%N)
        p="${PATHS[$((i % ${#PATHS[@]}))]}"
        out=$(curl -s -o /dev/null -m "$TIMEOUT" -w '%{http_code} %{time_total}' "$BASE_URL$p")
        code=${out% *}; ms=$(awk -v t="${out#* }" 'BEGIN { printf "%d", t * 1000 }')
        echo "$(date -u +%T) http $p $code $ms" | tee -a "$LOG"
        elapsed=$(( ($(date +%s%N) - t0) / 1000000 ))
        [ "$elapsed" -lt 1000 ] && sleep "0.$(printf '%03d' $((1000 - elapsed)))"
    done
) &
PIDS+=($!)

(
    end=$(( $(date +%s) + SECS ))
    while [ "$(date +%s)" -lt "$end" ]; do
        echo "$(date -u +%T) alertas $(alert_states)" | tee -a "$LOG"
        sleep 5
    done
) &
PIDS+=($!)

wait "${PIDS[0]}"
