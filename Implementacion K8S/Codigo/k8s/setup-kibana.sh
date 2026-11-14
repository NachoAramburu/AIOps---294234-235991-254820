#!/bin/bash

set -euo pipefail
export MSYS_NO_PATHCONV=1

NS=pharmago
TITLE='pharmago-logs-*'
NAME='PharmaGo logs'

if [ "$(kubectl config current-context 2>/dev/null)" != "minikube" ]; then
    echo "Error: el contexto de kubectl no es minikube."
    exit 1
fi

kib() {
    kubectl exec -n "$NS" deploy/kibana -- curl -s -m 20 -H 'kbn-xsrf: true' -H 'Content-Type: application/json' "$@"
}

echo "Esperando a Kibana..."
kubectl rollout status deploy/kibana -n "$NS" --timeout=300s >/dev/null
for _ in $(seq 1 60); do
    if kib http://localhost:5601/api/status 2>/dev/null | grep -q '"level":"available"'; then
        break
    fi
    sleep 5
done

if kib http://localhost:5601/api/data_views | grep -q "\"title\":\"${TITLE//\*/\\*}\""; then
    echo "El data view ${TITLE} ya existe."
else
    kib -X POST http://localhost:5601/api/data_views/data_view \
        -d "{\"data_view\":{\"title\":\"${TITLE}\",\"name\":\"${NAME}\",\"timeFieldName\":\"@timestamp\"}}" >/dev/null
    echo "Data view ${TITLE} creado."
fi

kib http://localhost:5601/api/data_views | grep -o "\"title\":\"pharmago-logs-[^\"]*\"" | sort -u
echo "Kibana: ./port-forward.sh y abrí http://127.0.0.1:5601 (Discover, data view \"${NAME}\")."
