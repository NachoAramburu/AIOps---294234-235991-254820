#!/bin/bash
# C06: loop de 1 curl por segundo a una URL (por defecto /api/drug) durante 40 s; en t=10 s borra una réplica del Deployment.
# Mide respuestas no-2xx y segundos desde el delete hasta volver a 2/2 Ready.
# Uso: bash loop-delete-pod.sh <deployment> [url]   (requiere minikube tunnel abierto)
set -uo pipefail
DEP="$1"; NS=pharmago; URL="${2:-http://127.0.0.1/api/drug}"; DUR=40; DEL_AT=10
OUT=$(mktemp); READYLOG=$(mktemp)
POD=$(kubectl get pods -n $NS -l app=$DEP -o jsonpath='{.items[0].metadata.name}')
echo "Deployment: $DEP | pod a borrar en t=${DEL_AT}s: $POD | URL: $URL | ${DUR} requests, 1 por segundo"
for i in $(seq 0 $((DUR - 1))); do
    T0=$(date +%s.%N)
    if [ "$i" -eq "$DEL_AT" ]; then
        DEL_TS=$(date +%s.%N)
        kubectl delete pod "$POD" -n $NS --wait=false >/dev/null
        echo "t=${i}s  kubectl delete pod $POD"
        # Medidor en segundo plano: espera a que el Deployment vuelva a 2 réplicas Ready.
        ( sleep 1
          while :; do
              # Pods Ready del Deployment, sin contar al que se borró.
              R=$(kubectl get pods -n $NS -l app=$DEP -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].ready}{"\n"}{end}' \
                  | awk -v del="$POD" '$1 != del && $2 == "true"' | wc -l)
              # Corte de seguridad: si en 120 s no vuelve, se informa y se termina.
              if [ "$(awk -v a="$(date +%s.%N)" -v b="$DEL_TS" 'BEGIN { print (a - b > 120) }')" = "1" ]; then break; fi
              if [ "$R" -ge 2 ]; then
                  echo "$(date +%s.%N)" > "$READYLOG"; break
              fi
              sleep 0.5
          done ) &
        WATCHER=$!
    fi
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$URL")
    echo "$i $CODE" >> "$OUT"
    printf "t=%2ds  HTTP %s\n" "$i" "$CODE"
    SLEEP=$(awk -v t0="$T0" -v now="$(date +%s.%N)" 'BEGIN { s = 1 - (now - t0); if (s > 0) printf "%.3f", s; else print 0 }')
    sleep "$SLEEP"
done
wait "$WATCHER" 2>/dev/null
TOTAL=$(wc -l < "$OUT"); OK=$(awk '$2 ~ /^2/' "$OUT" | wc -l); BAD=$((TOTAL - OK))
echo ""
echo "Respuestas: $TOTAL | 2xx: $OK | no-2xx: $BAD"
[ "$BAD" -gt 0 ] && { echo "No-2xx:"; awk '$2 !~ /^2/ { print "  t=" $1 "s HTTP " $2 }' "$OUT"; }
if [ -s "$READYLOG" ]; then
    echo "Segundos desde el delete hasta volver a 2/2 Ready: $(awk -v a="$(cat "$READYLOG")" -v b="$DEL_TS" 'BEGIN { printf "%.1f", a - b }')"
else
    echo "No volvió a 2/2 Ready durante la prueba"
fi
kubectl get pods -n $NS -l app=$DEP -o wide --no-headers
rm -f "$OUT" "$READYLOG"
