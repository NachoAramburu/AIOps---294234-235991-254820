#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
    echo "Uso: $0 <cantidad> <concurrencia> [url=http://127.0.0.1/api/login]"
    echo "Ejemplo: $0 300 20"
    echo "Requiere minikube tunnel. Con la URL de login manda POST con credenciales inválidas."
    exit 1
}

[ $# -ge 2 ] || usage
N="$1"
C="$2"
URL="${3:-http://127.0.0.1/api/login}"
require_int cantidad "$N"
require_int concurrencia "$C"
require_context
command -v curl >/dev/null || die "falta curl"

OUT=$(mktemp)
cleanup() {
    trap - EXIT
    rm -f "$OUT"
    marca_tiempo fin
}
trap cleanup EXIT
trap 'exit 130' INT TERM

marca_tiempo inicio
echo "Requests: $N a $URL con concurrencia $C"
START=$(date +%s)
if [[ "$URL" == */api/login ]]; then
    seq "$N" | xargs -P "$C" -I{} curl -s -o /dev/null -m 10 -w '%{http_code}\n' \
        -X POST -H 'Content-Type: application/json' -d '{"userName":"chaos","password":"chaos"}' "$URL" >> "$OUT" || true
else
    seq "$N" | xargs -P "$C" -I{} curl -s -o /dev/null -m 10 -w '%{http_code}\n' "$URL" >> "$OUT" || true
fi
END=$(date +%s)
echo "Duración: $((END - START)) s"
echo "Respuestas por código HTTP:"
sort "$OUT" | uniq -c | sort -rn | awk '{ printf "  %s x%s\n", $2, $1 }'
