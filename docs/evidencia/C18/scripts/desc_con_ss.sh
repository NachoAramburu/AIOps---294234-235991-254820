#!/bin/bash
# disconnect.sh en segundo plano y, a los 25 s, steady-state.sh en medio de la falla (debe terminar con salida != 0)
./disconnect.sh pharmago-pharmacy-service 60 &
D=$!
sleep 25
echo "--- steady-state.sh DURANTE la desconexión (se espera salida distinta de 0)"
./steady-state.sh 10; echo "exit=$?"
echo "--- fin del chequeo durante la falla"
wait $D
