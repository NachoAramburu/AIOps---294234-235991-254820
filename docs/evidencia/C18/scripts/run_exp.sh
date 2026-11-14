#!/bin/bash
# run_exp.sh <id> <segundos_observar> <rutas_observar> <comando de caos...>
# Corre: steady-state (antes) -> observar.sh en paralelo con el caos -> steady-state (después, reintenta hasta OK, máx 8)
ID="$1"; OBS="$2"; ROUTES="$3"; shift 3
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
CHAOS="$REPO/Implementacion K8S/Codigo/chaos-engineering"
EV="$REPO/docs/evidencia/C18"
OUT="$EV/$ID.txt"
export MSYS_NO_PATHCONV=1
cd "$CHAOS"
{
echo "##### Experimento $ID"
echo "##### 1. Steady state ANTES"
echo "\$ ./steady-state.sh"
./steady-state.sh; echo "exit=$?"
echo
echo "##### 2. Experimento: observar.sh en paralelo con el caos"
echo "\$ ./observar.sh $OBS $ROUTES   (en otra terminal)"
echo "\$ $*"
./observar.sh "$OBS" $ROUTES > "$OUT.obs" 2>&1 &
OP=$!
sleep 5
T0=$(date +%s)
echo "--- salida del caos"
"$@"; echo "exit=$?"
T1=$(date +%s)
echo "--- duración del caos: $((T1 - T0)) s"
wait $OP
echo "--- salida de observar.sh"
cat "$OUT.obs"; rm -f "$OUT.obs"
echo
echo "##### 3. Steady state DESPUÉS (se repite hasta OK, máximo 8 veces)"
for i in $(seq 1 8); do
  echo "\$ ./steady-state.sh   (intento $i, $(( $(date +%s) - T1 )) s después del fin del caos)"
  ./steady-state.sh; rc=$?; echo "exit=$rc"
  [ $rc -eq 0 ] && { echo "Steady state recuperado $(( $(date +%s) - T1 )) s después del fin del caos (al terminar el chequeo)"; break; }
  sleep 10
done
} > "$OUT" 2>&1
echo "listo: $OUT"
