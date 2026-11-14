#!/bin/bash
# C20: verifica que los playbooks nombren alertas y paneles que existen.
# Uso: bash check-playbooks.sh   (desde Git Bash, cualquier directorio; no necesita el cluster)
#   1. Cada playbook de docs/playbooks/ tiene las 10 secciones obligatorias.
#   2. Cada uid pg-* que nombra un playbook existe en grafana-alerting.yaml.
#   3. Cada título entre comillas dobles "..." de un playbook (fuera de bloques de código y de `código`)
#      es un dashboard o un panel de los configmaps de Grafana. Convención: en los playbooks las comillas
#      dobles se usan solo para títulos de Grafana.
#   4. Cada alerta de grafana-alerting.yaml tiene un playbook que la nombra y su annotation runbook
#      apunta a un archivo que existe.
# Termina con error si algo no existe.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
CM="$SCRIPT_DIR/../configmaps"
PB_DIR="$REPO/docs/playbooks"
ALERTING="$CM/grafana-alerting.yaml"
FAILS=0

ok()    { echo "  [OK]    $*"; }
falla() { echo "  [FALTA] $*"; FAILS=$((FAILS + 1)); }

[ -d "$PB_DIR" ] || { echo "Error: no existe $PB_DIR"; exit 1; }
shopt -s nullglob
PLAYBOOKS=("$PB_DIR"/*.md)
[ ${#PLAYBOOKS[@]} -gt 0 ] || { echo "Error: no hay playbooks en $PB_DIR"; exit 1; }

UIDS=$(grep -oE '^\s*- uid: pg-[a-z0-9-]+' "$ALERTING" | awk '{ print $3 }' | sort -u)
TITLES=$(cat "$CM"/grafana-dashboard*.yaml | grep -oE '"title": ?"[^"]*"' | sed -E 's/"title": ?"//; s/"$//' | sort -u)

# Texto del playbook sin bloques de código ni `código` en línea (ahí puede haber comillas de comandos).
prose() { awk '/^[[:space:]]*```/ { inside = !inside; next } !inside' "$1" | sed 's/`[^`]*`//g'; }

SECTIONS=("Síntoma" "Alerta" "Panel" "Severidad inicial" "Diagnóstico" "Mitigación automática esperada"
          "Mitigación manual" "Validación" "Si no funciona" "Registro")

echo "Playbooks: ${#PLAYBOOKS[@]} en docs/playbooks/"
echo "Alertas provisionadas: $(wc -w <<< "$UIDS") | Títulos de dashboards y paneles: $(grep -c . <<< "$TITLES")"

for pb in "${PLAYBOOKS[@]}"; do
    name="docs/playbooks/$(basename "$pb")"
    echo
    echo "# $name"
    for s in "${SECTIONS[@]}"; do
        grep -qE "^## $s" "$pb" || falla "sección \"## $s\""
    done
    n_sec=$(grep -cE '^## ' "$pb")
    echo "  secciones: $n_sec"

    pb_uids=$(grep -oE '`pg-[a-z0-9-]+`' "$pb" | tr -d '`' | sort -u)
    [ -n "$pb_uids" ] || falla "no nombra ninguna alerta pg-*"
    for u in $pb_uids; do
        if grep -qx "$u" <<< "$UIDS"; then ok "alerta $u"; else falla "alerta $u no está en grafana-alerting.yaml"; fi
    done

    titles=$(prose "$pb" | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
    [ -n "$titles" ] || falla "no nombra ningún panel entre comillas"
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        if grep -qxF "$t" <<< "$TITLES"; then ok "panel \"$t\""; else falla "panel \"$t\" no está en los dashboards"; fi
    done <<< "$titles"
done

echo
echo "# Cada alerta tiene playbook y su runbook existe"
for u in $UIDS; do
    if grep -lq "\`$u\`" "${PLAYBOOKS[@]}"; then
        files=$(grep -l "\`$u\`" "${PLAYBOOKS[@]}" | while IFS= read -r f; do printf '%s ' "$(basename "$f")"; done)
        ok "$u nombrada en: $files"
    else
        falla "$u no aparece en ningún playbook"
    fi
    rb=$(awk -v u="$u" '$0 ~ "- uid: "u"$" { f = 1 } f && /runbook:/ { print $2; exit }' "$ALERTING")
    if [ -n "$rb" ] && [ -f "$REPO/$rb" ]; then ok "$u runbook $rb existe"; else falla "$u runbook '${rb:-sin runbook}' no existe"; fi
done

echo
if [ "$FAILS" -eq 0 ]; then
    echo "RESULTADO: OK, todas las alertas y paneles que nombran los playbooks existen"
else
    echo "RESULTADO: $FAILS referencia(s) faltante(s)"
fi
exit $((FAILS > 0))
