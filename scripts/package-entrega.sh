#!/usr/bin/env bash
# Arma obligatorio-aiops.zip para subir a Gestión (C24).
#
# Uso, desde cualquier carpeta del repo:
#   scripts/package-entrega.sh            # zip desde HEAD (lo normal, después de mergear a main)
#   scripts/package-entrega.sh <tree-ish> # zip desde otro commit o árbol (por ejemplo, el de `git write-tree`)
#
# El zip sale de `git archive`: solo entra lo versionado, sin los .bak de la base, bin, obj ni node_modules.
# Los PDF de docs/pdf/ están versionados (se generan con scripts/build-pdfs.py), y el informe se copia
# además a la raíz del zip como INFORME.pdf. Falla si el zip pasa de 40 MB o si falta el informe.
set -euo pipefail

REF="${1:-HEAD}"
MAX_BYTES=$((40 * 1024 * 1024))
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
OUT="$ROOT/obligatorio-aiops.zip"
PREFIX="obligatorio-aiops/"

if ! git cat-file -e "$REF:docs/pdf/informe.pdf" 2>/dev/null; then
  echo "ERROR: $REF no tiene docs/pdf/informe.pdf. Generá los PDF (scripts/build-pdfs.py) y commitealos." >&2
  exit 1
fi
if [ "$REF" = "HEAD" ] && [ -n "$(git status --porcelain -- docs/pdf docs/informe)" ]; then
  echo "ERROR: hay cambios sin commitear en docs/pdf o docs/informe; el zip saldría distinto del repo." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git show "$REF:docs/pdf/informe.pdf" > "$TMP/INFORME.pdf"

rm -f "$OUT"
git archive --format=zip -o "$OUT" --prefix="$PREFIX" --add-file="$TMP/INFORME.pdf" "$REF" -- . \
  ':(exclude,glob)**/*.bak' \
  ':(exclude,glob)**/bin/**' \
  ':(exclude,glob)**/obj/**' \
  ':(exclude,glob)**/node_modules/**'

BYTES=$(wc -c < "$OUT" | tr -d ' ')
ARCHIVOS=$(unzip -Z1 "$OUT" | grep -vc '/$' || true)
PDFS=$(unzip -Z1 "$OUT" | grep -ci '\.pdf$' || true)
PROHIBIDOS=$(unzip -Z1 "$OUT" | grep -Eci '\.bak$|/bin/|/obj/|/node_modules/' || true)

echo "Origen:    $REF ($(git rev-parse --short "$REF"))"
echo "Zip:       $OUT"
echo "Tamaño:    $BYTES bytes ($(awk -v b="$BYTES" 'BEGIN { printf "%.2f", b / 1048576 }') MB, máximo 40 MB)"
echo "Archivos:  $ARCHIVOS, de los cuales $PDFS son PDF"
echo "Excluidos que se colaron (.bak, bin, obj, node_modules): $PROHIBIDOS"
echo "PDF incluidos:"
unzip -Z1 "$OUT" | grep -i '\.pdf$' | sed 's/^/  /'

if [ "$BYTES" -gt "$MAX_BYTES" ]; then
  echo "ERROR: el zip pasa de 40 MB." >&2
  exit 1
fi
if [ "$PROHIBIDOS" -ne 0 ]; then
  echo "ERROR: el zip incluye archivos que debían quedar afuera." >&2
  exit 1
fi
echo "OK: listo para subir a Gestión."
