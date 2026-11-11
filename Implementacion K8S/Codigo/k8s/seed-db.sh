#!/bin/bash
# Carga los datos iniciales (Backend/seed-data.sql) en la BD de PharmaGo.
# Sin esto no hay roles ni usuarios y no se puede iniciar sesión.
# Idempotente: seed-data.sql usa IF NOT EXISTS, se puede correr varias veces.
# Uso: ./seed-db.sh   (desde Git Bash, cualquier directorio)
#
# La contraseña de sa NO pasa por este script: el contenedor de BD ya la tiene en
# la variable SA_PASSWORD (secretKeyRef al Secret db-secret) y sqlcmd la lee de
# SQLCMDPASSWORD dentro del pod. Nunca se imprime.

set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash: no convertir /tmp/... a rutas de Windows

NS="pharmago"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SEED_FILE="$SCRIPT_DIR/../Backend/seed-data.sql"
MAX_WAIT="${MAX_WAIT:-300}"

if [ ! -f "$SEED_FILE" ]; then
    echo "Error: no se encuentra $SEED_FILE"
    exit 1
fi

echo "=== Seed de datos de PharmaGo ==="

echo "Esperando el pod de BD listo..."
kubectl wait --for=condition=Ready pod -l app=pharmago-db -n "$NS" --timeout="${MAX_WAIT}s"
POD=$(kubectl get pod -l app=pharmago-db -n "$NS" -o jsonpath='{.items[0].metadata.name}')
echo "Pod de BD: $POD"

# sqlcmd cambia de ruta según la versión de la imagen: mssql-tools18 exige -C (confiar en el certificado)
SQLCMD_INFO=$(kubectl exec -n "$NS" "$POD" -c pharmago-db -- bash -c '
if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then echo "/opt/mssql-tools18/bin/sqlcmd -C";
elif [ -x /opt/mssql-tools/bin/sqlcmd ]; then echo "/opt/mssql-tools/bin/sqlcmd";
else echo ""; fi')
if [ -z "$SQLCMD_INFO" ]; then
    echo "Error: no se encontró sqlcmd en el pod de BD"
    exit 1
fi
echo "sqlcmd: $SQLCMD_INFO"

# Ejecuta una consulta dentro del pod usando la contraseña del Secret (variable SA_PASSWORD del contenedor)
run_sql() {
    kubectl exec -i -n "$NS" "$POD" -c pharmago-db -- env SQLCMD_BIN="$SQLCMD_INFO" bash -c \
        'SQLCMDPASSWORD="$SA_PASSWORD" $SQLCMD_BIN -S localhost -U sa -b -h -1 -W "$@"' _ "$@"
}

# Las tablas las crean las migraciones de EF al arrancar users-service y pharmacy-service.
echo "Esperando a que las migraciones creen las tablas (Roles, Users, Pharmacys, Drugs, Invitations)..."
elapsed=0
while true; do
    count=$(run_sql -Q "SET NOCOUNT ON; IF DB_ID('PharmaDb') IS NULL SELECT 0 ELSE SELECT COUNT(*) FROM PharmaDb.sys.tables WHERE name IN ('Roles','Users','Pharmacys','Drugs','Invitations','UnitMeasures','Presentations');" 2>/dev/null | tr -d '[:space:]' || true)
    if [ "$count" = "7" ]; then
        echo "Tablas listas."
        break
    fi
    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
        echo "Error: después de ${MAX_WAIT}s faltan tablas (encontradas: ${count:-0} de 7)."
        echo "Revisá: kubectl logs -n $NS -l app=pharmago-users-service"
        exit 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    echo "  Esperando... (${elapsed}/${MAX_WAIT}s, tablas: ${count:-0}/7)"
done

echo "Copiando seed-data.sql al pod..."
kubectl exec -i -n "$NS" "$POD" -c pharmago-db -- bash -c 'cat > /tmp/seed-data.sql' < "$SEED_FILE"

echo "Ejecutando seed-data.sql..."
# El script imprime la contraseña de los usuarios de prueba: se filtra esa línea.
# Con -b, sqlcmd sale con código distinto de 0 si falla alguna sentencia.
set +e
run_sql -i /tmp/seed-data.sql | grep -vi 'password'
status=${PIPESTATUS[0]}
set -e
kubectl exec -n "$NS" "$POD" -c pharmago-db -- rm -f /tmp/seed-data.sql
if [ "$status" -ne 0 ]; then
    echo "Error: sqlcmd terminó con código $status"
    exit "$status"
fi

echo ""
echo "Verificación:"
run_sql -Q "SET NOCOUNT ON; SELECT 'Roles=' + CAST(COUNT(*) AS varchar) FROM PharmaDb.dbo.Roles; SELECT 'Users=' + CAST(COUNT(*) AS varchar) FROM PharmaDb.dbo.Users; SELECT 'Drugs=' + CAST(COUNT(*) AS varchar) FROM PharmaDb.dbo.Drugs;"
echo "=== Seed completado ==="
