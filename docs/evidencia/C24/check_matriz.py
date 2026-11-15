"""Comprueba docs/MATRIZ_CUMPLIMIENTO.md (C24).

1. Cada ruta entre comillas invertidas que parezca un archivo o carpeta del repo tiene que existir.
   `CODE/` se expande a `Implementacion K8S/Codigo/`.
2. Cuenta las filas por estado y lista las que no son CUMPLE.

Uso, desde la raíz del repo:  python docs/evidencia/C24/check_matriz.py
Sale con 1 si falta alguna ruta o si hay filas NO CUMPLE.
"""

import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MATRIZ = ROOT / "docs" / "MATRIZ_CUMPLIMIENTO.md"
ESTADOS = ["NO CUMPLE", "CUMPLE (defensa)", "CUMPLE", "PARCIAL", "NO VERIFICADO"]
PARECE_RUTA = re.compile(r"^(CODE/|docs/|anomaly-detection/|scripts/|\.github/)")


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    faltan, revisadas = [], 0
    conteo, no_cumple, otras = Counter(), [], []
    for linea in MATRIZ.read_text(encoding="utf-8").splitlines():
        if not re.match(r"^\| \d+\.\d+ ", linea):
            continue
        celdas = [c.strip() for c in linea.strip("|").split("|")]
        fila, estado = celdas[0], celdas[2]
        estado_norm = next((e for e in ESTADOS if estado.startswith(e)), estado)
        conteo[estado_norm] += 1
        if estado_norm == "NO CUMPLE":
            no_cumple.append(fila)
        elif estado_norm != "CUMPLE":
            otras.append(f"{fila} {estado_norm}")
        for ruta in re.findall(r"`([^`]+)`", celdas[4]):
            ruta = ruta.split(" ")[0]
            if not PARECE_RUTA.match(ruta):
                continue
            revisadas += 1
            real = ROOT / ruta.replace("CODE/", "Implementacion K8S/Codigo/", 1)
            if not real.exists():
                faltan.append(ruta)
    print(f"Rutas comprobadas: {revisadas}. Faltan: {len(faltan)}")
    for r in faltan:
        print(f"  FALTA {r}")
    print("Filas por estado: " + ", ".join(f"{e} {conteo[e]}" for e in ESTADOS if conteo[e]))
    print("Filas NO CUMPLE: " + (", ".join(no_cumple) if no_cumple else "ninguna"))
    print("Filas que no son CUMPLE: " + ("; ".join(otras) if otras else "ninguna"))
    return 1 if faltan or no_cumple else 0


if __name__ == "__main__":
    sys.exit(main())
