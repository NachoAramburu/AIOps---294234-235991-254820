#!/bin/bash
# con_trafico.sh <ruta> <comando de caos...>
# Tráfico concurrente de varios usuarios: 1 request cada 0,7 s a <ruta> durante 75 s, sin esperar la respuesta
# (timeout 15 s), mientras corre el caos. Al final: códigos por ventana de 5 s.
RUTA="$1"; shift
OUT=$(mktemp)
echo "\$ for i in \$(seq 107); do curl -s -o /dev/null -m 15 -w '%{http_code} %{time_total}' http://127.0.0.1$RUTA & sleep 0.7; done   (en segundo plano)"
(
  for i in $(seq 107); do
    ( c=$(curl -s -o /dev/null -m 15 -w '%{http_code} %{time_total}' "http://127.0.0.1$RUTA"); echo "$(date -u +%T) $c" >> "$OUT" ) &
    sleep 0.7
  done
  wait
) &
G=$!
sleep 5
"$@"; rc=$?
wait $G
echo "--- tráfico concurrente a $RUTA: códigos por ventana de 5 s (hora de respuesta) y latencia máxima"
sort "$OUT" | awk '{ split($1, t, ":"); b = sprintf("%s:%s:%02d", t[1], t[2], int(t[3] / 5) * 5); k = b " " $2; n[k]++; if (!(b in seen)) { seen[b] = 1; o[++m] = b }; if ($3 > mx[b]) mx[b] = $3 }
  END { for (i = 1; i <= m; i++) { b = o[i]; line = ""; for (k in n) { split(k, kk, " "); if (kk[1] == b) line = line " " kk[2] "x" n[k] }; printf "  %s %s  (máx %.1f s)\n", b, line, mx[b] } }'
echo "--- total"
awk '{ print $2 }' "$OUT" | sort | uniq -c | awk '{ printf "  %s x%s\n", $2, $1 }'
rm -f "$OUT"
exit $rc
