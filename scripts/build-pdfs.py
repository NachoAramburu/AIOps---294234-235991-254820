"""Genera los PDF de la documentación en docs/pdf/ (C24).

Convierte cada Markdown a HTML con mistune y lo imprime a PDF con Chrome o Edge
en modo headless. Los bloques ```mermaid se dibujan con Mermaid en el navegador.

Uso, desde la raíz del repo (necesita mistune 3, que ya trae el venv de anomaly-detection):

    anomaly-detection/.venv/Scripts/python scripts/build-pdfs.py

Variables opcionales: CHROME (ruta del navegador) y MAX_PAGINAS_INFORME (10 por defecto).
Sale con 1 si un PDF no se genera o si el informe pasa del máximo de páginas.
"""

import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import mistune

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "docs" / "pdf"
CODE = "Implementacion K8S/Codigo/"
MERMAID_JS = "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js"
MAX_PAGINAS_INFORME = int(os.environ.get("MAX_PAGINAS_INFORME", "10"))

EXTRA = [
    CODE + "chaos-engineering/EXPERIMENTOS.md",
    CODE + "chaos-engineering/README.md",
    CODE + "k8s/README-k8s.md",
    "anomaly-detection/README.md",
]
EXCLUIDOS = {"docs/letra-obligatorio.md"}

CSS = """
@page { size: A4; margin: 16mm 15mm; }
body { font-family: "Segoe UI", Arial, sans-serif; font-size: 10pt; line-height: 1.38; color: #1a1a1a; }
h1 { font-size: 17pt; margin: 0 0 6pt; }
h2 { font-size: 12.5pt; margin: 13pt 0 4pt; border-bottom: 1px solid #bbb; padding-bottom: 2pt; }
h3 { font-size: 11pt; margin: 10pt 0 3pt; }
p { margin: 4pt 0; }
ul, ol { margin: 3pt 0; padding-left: 18pt; }
li { margin: 1.5pt 0; }
table { border-collapse: collapse; width: 100%; margin: 5pt 0; font-size: 8.6pt; page-break-inside: auto; }
tr { page-break-inside: avoid; }
th, td { border: 1px solid #b5b5b5; padding: 2.5pt 4pt; vertical-align: top; text-align: left; }
th { background: #eceff3; }
code { font-family: Consolas, "Courier New", monospace; font-size: 8.6pt; background: #f2f2f2; padding: 0 2px;
       overflow-wrap: anywhere; }
pre { background: #f5f5f5; border: 1px solid #ddd; padding: 5pt; font-size: 8pt; white-space: pre-wrap;
      overflow-wrap: anywhere; page-break-inside: avoid; }
pre code { background: none; padding: 0; }
pre.mermaid { background: none; border: none; text-align: center; }
blockquote { margin: 5pt 0; padding: 2pt 8pt; border-left: 3px solid #999; color: #444; }
a { color: #1a4f9c; text-decoration: none; }
"""


class Renderer(mistune.HTMLRenderer):
    def block_code(self, code, info=None):
        if info and info.strip().split()[0] == "mermaid":
            return '<pre class="mermaid">' + html.escape(code) + "</pre>\n"
        return super().block_code(code, info)


MARKDOWN = mistune.create_markdown(renderer=Renderer(escape=False), plugins=["table", "strikethrough", "url"])


def documentos():
    """Markdown versionados o nuevos (sin los ignorados, como el material interno del equipo)."""
    salida = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "docs"],
        cwd=ROOT, capture_output=True, check=True,
    ).stdout.decode("utf-8")
    rutas = [r for r in salida.split("\0") if r.endswith(".md")]
    rutas = [r for r in rutas if not r.startswith("docs/evidencia/") and r not in EXCLUIDOS]
    rutas += [r for r in EXTRA if (ROOT / r).exists()]
    return sorted(set(rutas))


def nombre_pdf(ruta):
    if ruta == "docs/informe/informe.md":
        return "informe.pdf"
    corto = ruta.removeprefix("docs/").removeprefix(CODE)
    return corto.removesuffix(".md").replace("/", "-") + ".pdf"


def navegador():
    candidatos = [
        os.environ.get("CHROME", ""),
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        shutil.which("google-chrome") or "",
        shutil.which("chromium") or "",
        shutil.which("chromium-browser") or "",
    ]
    for c in candidatos:
        if c and Path(c).exists():
            return c
    sys.exit("No encontré Chrome ni Edge. Indicá la ruta con CHROME=<ruta>.")


def a_html(ruta):
    texto = (ROOT / ruta).read_text(encoding="utf-8")
    titulo = next((l[2:].strip() for l in texto.splitlines() if l.startswith("# ")), Path(ruta).stem)
    cuerpo = MARKDOWN(texto)
    mermaid = ""
    if 'class="mermaid"' in cuerpo:
        mermaid = (f'<script src="{MERMAID_JS}"></script>'
                   '<script>mermaid.initialize({startOnLoad: true, theme: "neutral", '
                   'flowchart: {useMaxWidth: true}});</script>')
    return (f'<!doctype html><html lang="es"><head><meta charset="utf-8"><title>{html.escape(titulo)}</title>'
            f"<style>{CSS}</style></head><body>{cuerpo}{mermaid}</body></html>")


def paginas(pdf):
    return len(re.findall(rb"/Type\s*/Page(?![a-zA-Z])", pdf.read_bytes()))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    chrome = navegador()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for viejo in OUT_DIR.glob("*.pdf"):
        viejo.unlink()
    errores = 0
    with tempfile.TemporaryDirectory() as tmp:
        for ruta in documentos():
            destino = OUT_DIR / nombre_pdf(ruta)
            html_tmp = Path(tmp) / (destino.stem + ".html")
            html_tmp.write_text(a_html(ruta), encoding="utf-8")
            subprocess.run(
                [chrome, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                 "--virtual-time-budget=15000", f"--print-to-pdf={destino}", html_tmp.as_uri()],
                capture_output=True, timeout=180,
            )
            if not destino.exists() or destino.stat().st_size == 0:
                print(f"ERROR  {ruta}: no se generó el PDF")
                errores += 1
                continue
            print(f"{paginas(destino):4d} págs  {destino.stat().st_size // 1024:5d} KB  {destino.relative_to(ROOT).as_posix()}  <-  {ruta}")
    informe = OUT_DIR / "informe.pdf"
    if informe.exists():
        n = paginas(informe)
        estado = "OK" if n <= MAX_PAGINAS_INFORME else "SUPERA EL MÁXIMO"
        print(f"\nInforme: {n} páginas (máximo {MAX_PAGINAS_INFORME}): {estado}")
        if n > MAX_PAGINAS_INFORME:
            errores += 1
    return 1 if errores else 0


if __name__ == "__main__":
    sys.exit(main())
