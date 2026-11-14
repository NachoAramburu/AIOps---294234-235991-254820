#!/bin/bash
# C09: demuestra que un rollout v1 -> v2 -> rollback no produce respuestas no-2xx.
# Mientras corre deploy.sh <tag_v2> y después rollback.sh, un loop pide 1 request por segundo por el Ingress,
# rotando entre la UI (/), pharmacy (/api/drug) y users (/api/roles), y guarda la hora y el código de cada una.
# 1 request por segundo y endpoints distintos para no chocar con el rate limit (100 por minuto y 1000 por hora
# por endpoint): un 429 se informa aparte porque es el límite del borde, no una caída.
# Uso: ./test-rollout.sh <tag_v2> [url_base]     (requiere minikube tunnel y las imágenes v2 cargadas)
# Termina con error si hubo alguna respuesta no-2xx.

set -uo pipefail
export MSYS_NO_PATHCONV=1

TAG_V2="${1:-}"
BASE="${2:-http://127.0.0.1}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
K8S_DIR="$(dirname "$SCRIPT_DIR")"
PATHS=(/ /api/drug /api/roles)

if [ -z "$TAG_V2" ]; then
    echo "Uso: $0 <tag_v2> [url_base]"
    exit 1
fi
if [ "$(kubectl config current-context 2>/dev/null)" != "minikube" ]; then
    echo "Error: el contexto de kubectl no es minikube."
    exit 1
fi
for p in "${PATHS[@]}"; do
    if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BASE$p")" != "200" ]; then
        echo "Error: $BASE$p no responde 200 antes de empezar. ¿Está abierto minikube tunnel?"
        exit 1
    fi
done

LOG=$(mktemp)
loop() {
    local i=0
    while :; do
        local p="${PATHS[$((i % 3))]}"
        local code
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BASE$p")
        echo "$(date -u +%H:%M:%S) $code $p" >> "$LOG"
        i=$((i + 1))
        sleep 1
    done
}
loop &
LOOP_PID=$!
trap 'kill $LOOP_PID 2>/dev/null' EXIT

echo "$(date -u +%H:%M:%S) Imágenes antes del rollout:"
kubectl get deploy -n pharmago -o custom-columns=DEPLOYMENT:.metadata.name,IMAGEN:.spec.template.spec.containers[0].image | grep pharmago-
sleep 5

echo "$(date -u +%H:%M:%S) deploy.sh $TAG_V2"
bash "$K8S_DIR/deploy.sh" "$TAG_V2"
DEPLOY_EXIT=$?
sleep 5

echo "$(date -u +%H:%M:%S) rollback.sh"
bash "$K8S_DIR/rollback.sh"
ROLLBACK_EXIT=$?
sleep 5

kill $LOOP_PID 2>/dev/null
trap - EXIT
sleep 1

TOTAL=$(wc -l < "$LOG")
OK=$(awk '$2 ~ /^2/' "$LOG" | wc -l)
RL=$(awk '$2 == "429"' "$LOG" | wc -l)
BAD=$((TOTAL - OK - RL))
echo
echo "Resultado: $TOTAL requests | 2xx: $OK | 429 (rate limit): $RL | otras no-2xx: $BAD"
echo "deploy.sh terminó con $DEPLOY_EXIT y rollback.sh con $ROLLBACK_EXIT"
if [ "$((BAD + RL))" -gt 0 ]; then
    echo "Detalle de las no-2xx:"
    awk '$2 !~ /^2/ { print "  " $0 }' "$LOG"
fi
rm -f "$LOG"

if [ "$DEPLOY_EXIT" -ne 0 ] || [ "$ROLLBACK_EXIT" -ne 0 ]; then
    echo "FALLA: deploy.sh o rollback.sh no terminaron bien."
    exit 1
fi
if [ "$BAD" -gt 0 ]; then
    echo "FALLA: hubo respuestas no-2xx durante el rollout."
    exit 1
fi
if [ "$RL" -gt 0 ]; then
    echo "ATENCIÓN: hubo 429 del rate limit. No es una caída, pero repetí la prueba más tarde para tener 0 no-2xx."
    exit 1
fi
echo "OK: 0 respuestas no-2xx durante v1 -> v2 -> rollback."
