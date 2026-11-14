#!/bin/bash
# E8: versión rota de pharmacy (imagen que no existe en los nodos) y rollback con rollback.sh
export MSYS_NO_PATHCONV=1
NS=pharmago; D=pharmago-pharmacy-service
echo "\$ kubectl rollout history deploy/$D -n $NS | tail -3"; kubectl rollout history deploy/$D -n $NS | tail -3
echo "$(date -u +%T) \$ kubectl set image deploy/$D $D=$D:no-existe -n $NS"
kubectl set image deploy/$D $D=$D:no-existe -n $NS
sleep 45
echo "$(date -u +%T) \$ kubectl rollout status deploy/$D -n $NS --timeout=10s   (se espera que NO termine)"
kubectl rollout status deploy/$D -n $NS --timeout=10s; echo "exit=$?"
echo "$(date -u +%T) \$ kubectl get pods -l app=$D"; kubectl get pods -n $NS -l app=$D
echo "\$ kubectl get deploy $D"; kubectl get deploy $D -n $NS
echo "\$ eventos del pod nuevo"; kubectl get events -n $NS --sort-by=.lastTimestamp | grep -E 'no-existe|ErrImageNeverPull' | tail -3
echo "$(date -u +%T) \$ ../k8s/rollback.sh $D"
T0=$(date +%s)
../k8s/rollback.sh $D; echo "exit=$?"
echo "rollback: $(( $(date +%s) - T0 )) s"
kubectl get pods -n $NS -l app=$D
