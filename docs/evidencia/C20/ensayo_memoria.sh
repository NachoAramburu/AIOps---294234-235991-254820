#!/bin/bash
# C20: seguir docs/playbooks/memoria.md paso a paso durante un experimento real.
export MSYS_NO_PATHCONV=1
CH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/Implementacion K8S/Codigo/chaos-engineering"
cd "$CH"
ts() { date -u +%T; }
step() { echo; echo "=== $(ts) $*"; }
rule_state() {
  kubectl exec -n pharmago deploy/grafana -c grafana -- sh -c 'curl -s -m 4 -u "admin:$GF_SECURITY_ADMIN_PASSWORD" http://localhost:3000/api/prometheus/grafana/api/v1/rules' 2>/dev/null \
    | grep -o "\"state\":\"[a-z]*\",\"name\":\"$1" | cut -d'"' -f4
}

step "Prepare: steady state antes de inyectar la falla"
./steady-state.sh; echo "exit=$?"

step "Falla (la inyecta el «docente»; Ops no sabe cuál es): ./ram-spike.sh pharmago-pharmacy-service 250 300"
./ram-spike.sh pharmago-pharmacy-service 250 300 > /tmp/ensayo-ram.log 2>&1 &
RP=$!
T0=$(date +%s)

step "Detect: se espera una alerta (consulta cada 5 s del estado de las reglas)"
while :; do
  s=$(rule_state pg-memory)
  if [ "$s" = "firing" ]; then echo "$(ts) pg-memory=firing a los $(( $(date +%s) - T0 )) s de inyectar la falla"; break; fi
  [ "$s" = "pending" ] && echo "$(ts) pg-memory=pending"
  [ $(( $(date +%s) - T0 )) -gt 180 ] && { echo "$(ts) la alerta no disparó en 180 s"; break; }
  sleep 5
done
echo "IC (según el playbook): SEV2 por pg-memory (memoria > 85 % del límite durante 30 s). Playbook: docs/playbooks/memoria.md"

step "Panel del playbook: \"Memoria del pod contra su límite\" (misma métrica en Prometheus)"
curl -s -m 5 --data-urlencode 'query=max by (k8s_pod_name) (k8s_pod_memory_limit_utilization_ratio{k8s_namespace_name="pharmago"}) > 0.5' http://127.0.0.1:9090/api/v1/query \
  | python -c "import json,sys; [print('  ', r['metric']['k8s_pod_name'], round(float(r['value'][1]),3)) for r in json.load(sys.stdin)['data']['result']]"

step "Diagnóstico 1: kubectl top pod -n pharmago --sort-by=memory | head -8"
kubectl top pod -n pharmago --sort-by=memory | head -8
POD=$(kubectl top pod -n pharmago -l app=pharmago-pharmacy-service --sort-by=memory --no-headers | head -1 | awk '{print $1}')
echo "-> pod sospechoso: $POD"

step "Diagnóstico 2: proceso que ocupa la memoria (VmRSS) en $POD"
PROCS=$(kubectl exec -n pharmago "$POD" -- sh -c 'for p in /proc/[0-9]*; do printf "%s %s %s\n" "${p#/proc/}" "$(grep VmRSS $p/status 2>/dev/null)" "$(tr "\0" " " < $p/cmdline)"; done' | sort -k3 -n -r)
echo "$PROCS" | head -5 | cut -c1-120
PID=$(echo "$PROCS" | awk '$1 != 1 && $3 > 100000 { print $1; exit }')
echo "-> proceso ajeno a la app (no es dotnet, PID 1) con más de 100 MB: PID $PID"

step "Diagnóstico 3: ¿hubo OOM? (memory.events)"
kubectl exec -n pharmago "$POD" -- grep oom /sys/fs/cgroup/memory.events

step "Diagnóstico 4: ¿se reinició la app?"
kubectl get pod -n pharmago "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount} {.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'

step "Diagnóstico 5: ¿el usuario lo nota? ./observar.sh 20 /api/drug /api/roles"
./observar.sh 20 /api/drug /api/roles | sed -n '/Resumen/,$p'

step "Mitigación automática esperada: ninguna mientras no pase el límite (el OOM solo actúa al superarlo). Se pasa a la manual."
step "Mitigación manual, paso 2: kubectl exec -n pharmago $POD -- kill $PID"
kubectl exec -n pharmago "$POD" -- kill "$PID"; echo "exit=$?"
T1=$(date +%s)

step "Validación: kubectl top pod (el pod vuelve a su valor normal)"
sleep 20
kubectl top pod -n pharmago -l app=pharmago-pharmacy-service
step "Validación: esperar a que pg-memory vuelva a Normal"
while :; do
  s=$(rule_state pg-memory)
  if [ "$s" = "inactive" ]; then echo "$(ts) pg-memory=inactive (Normal) $(( $(date +%s) - T1 )) s después del kill"; break; fi
  [ $(( $(date +%s) - T1 )) -gt 180 ] && { echo "$(ts) pg-memory sigue en $s"; break; }
  sleep 5
done
step "Validación: ./steady-state.sh"
./steady-state.sh; echo "exit=$?"

wait $RP
step "Salida de ram-spike.sh (el script de la falla)"
cat /tmp/ensayo-ram.log; rm -f /tmp/ensayo-ram.log
echo "Duración total: $(( $(date +%s) - T0 )) s desde la inyección"
