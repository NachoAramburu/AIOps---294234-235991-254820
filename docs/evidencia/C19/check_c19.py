"""Chequeo de C19: toda herramienta, archivo, panel y decisión que nombra el plan existe en el repo,
salvo lo marcado como pendiente de B6/B7."""
import json, os, re, sys

ROOT = sys.argv[1]
CODE = os.path.join(ROOT, "Implementacion K8S", "Codigo")
docs = ["docs/plan-incidentes.md", "docs/plantillas/registro-incidente.md",
        "docs/plantillas/postmortem.md", "docs/incidentes/ejemplo-postmortem.md"]
text = {d: open(os.path.join(ROOT, d), encoding="utf-8").read() for d in docs}
plan = text["docs/plan-incidentes.md"]
ok = fail = pend = 0

def report(state, what, detail=""):
    global ok, fail, pend
    if state == "OK": ok += 1
    elif state == "PENDIENTE": pend += 1
    else: fail += 1
    print(f"  [{state}] {what}{('  -> ' + detail) if detail else ''}")

PENDING = {  # existen recién en B6/B7, según PLAN_COMMITS.md
    "chaos-engineering/steady-state.sh": "B7 (C18)", "steady-state.sh": "B7 (C18)",
    "chaos-engineering/EXPERIMENTOS.md": "B7 (C18)", "EXPERIMENTOS.md": "B7 (C18)",
    "docs/playbooks/": "B7 (C20)",
    "docs/alertas.md": "B6 (C13)",
    "docs/evidencia/C19/": "se crea en este commit",
}
SEARCH_DIRS = [ROOT, os.path.join(ROOT, "docs"), os.path.join(ROOT, "docs", "plantillas"), CODE,
               os.path.join(CODE, "k8s"), os.path.join(CODE, "k8s", "verify"), os.path.join(CODE, "chaos-engineering"),
               os.path.join(CODE, "Backend")]

print("# 1. Archivos y scripts nombrados en los 4 documentos (texto y bloques de código)")
paths = set()
for d, t in text.items():
    fences = re.findall(r"```.*?```", t, flags=re.S)
    inline = re.sub(r"```.*?```", "", t, flags=re.S)
    tokens = re.findall(r"`([^`]+)`", inline) + [w for f in fences for w in f.split()]
    for m in tokens:
        for w in m.split():
            w = w.strip("()[],;:")
            if re.search(r"\.(md|sh|yaml|txt)$|/$", w) and not w.startswith("http") and "<" not in w and "*" not in w:
                paths.add(w)
PLAYBOOKS = ["requests.md", "cpu.md", "memoria.md", "storage.md", "red.md", "desconexion.md",
             "pod-caido.md", "rollout-fallido.md"]  # nombres del plan de C20
for p in sorted(paths):
    if p == "/":
        continue
    if p in PLAYBOOKS:
        PENDING[p] = "B7 (C20), nombre corto de docs/playbooks/" + p
    pend_key = next((k for k in PENDING if p.startswith(k)), None)
    rel = p[2:] if p.startswith("./") else p
    cands = [os.path.join(dirp, rel) for dirp in SEARCH_DIRS]
    hit = next((c for c in cands if os.path.exists(c)), None)
    if hit:
        report("OK", p, os.path.relpath(hit, ROOT).replace("\\", "/"))
    elif pend_key:
        report("PENDIENTE", p, PENDING[pend_key])
    else:
        report("FALTA", p)

print("\n# 2. Paneles de Grafana nombrados entre comillas, contra los dashboards provisionados")
titles = {}
for f in ["grafana-dashboards.yaml", "grafana-dashboard-infra.yaml"]:
    raw = open(os.path.join(CODE, "k8s", "configmaps", f), encoding="utf-8").read()
    for t in re.findall(r'"title":"([^"]+)"', raw):
        titles[t] = f
panels = set(re.findall(r'"([A-ZÁÉÍÓÚ][^"\n]{6,80})"', plan))
for p in sorted(panels):
    if p in titles:
        report("OK", f'panel "{p}"', titles[p])
    elif any(w in p for w in ("PharmaGo - ",)):
        report("FALTA", f'dashboard "{p}"')
print("  (las frases entre comillas que no son paneles, como ejemplos de mensajes, no se listan)")
named_panels = ["Tasa de Error por Endpoint (%)", "Distribución de Status Codes (%)", "Latencia Promedio por Endpoint",
                "Throughput Total", "Peticiones por Segundo por Endpoint", "CPU del contenedor contra su límite",
                "Memoria del pod contra su límite", "Filesystem por pod", "Red por nodo",
                "Réplicas deseadas y disponibles por Deployment", "Reinicios por contenedor", "Nodos Ready",
                "PharmaGo - Overview", "PharmaGo - Infra"]
for p in named_panels:
    exact = p in titles
    prefix = next((t for t in titles if t.startswith(p)), None)
    if exact: report("OK", f'nombrado "{p}"', titles[p])
    elif prefix: report("OK", f'nombrado "{p}"', f'título completo "{prefix}"')
    else: report("FALTA", f'nombrado "{p}"')

print("\n# 3. Decisiones citadas (Dxx) existen en docs/DECISIONES.md")
dec = open(os.path.join(ROOT, "docs", "DECISIONES.md"), encoding="utf-8").read()
cited = sorted(set(re.findall(r"\bD(\d\d)\b", " ".join(text.values()))))
for n in cited:
    report("OK" if f"| D{n} |" in dec else "FALTA", f"D{n}")

print("\n# 4. Alertas pg-* citadas: deben coincidir con los uid del plan de C13 (se provisionan en B6)")
plan_c13 = open(os.path.join(ROOT, "docs", "PLAN_COMMITS.md"), encoding="utf-8").read()
c13 = plan_c13.split("### C13")[1].split("### C14")[0]
c13_uids = set(re.findall(r"\b(pg-[a-z0-9-]+)\b", c13))
grafana_alerting = os.path.exists(os.path.join(CODE, "k8s", "configmaps", "grafana-alerting.yaml"))
for u in sorted(set(re.findall(r"`(pg-[a-z0-9-]+)`", " ".join(text.values())))):
    if u not in c13_uids: report("FALTA", u, "no está en el plan de C13")
    elif grafana_alerting: report("OK", u)
    else: report("PENDIENTE", u, "uid del plan de C13; grafana-alerting.yaml llega en B6")

print("\n# 5. Playbooks citados: deben coincidir con los nombres del plan de C20 (se crean en B7)")
c20 = plan_c13.split("### C20")[1].split("### C21")[0]
for pb in sorted(set(re.findall(r"docs/playbooks/([a-z-]+\.md)", plan))):
    report("PENDIENTE" if pb in c20 else "FALTA", f"docs/playbooks/{pb}", "nombre del plan de C20" if pb in c20 else "")

print(f"\nResumen: {ok} OK, {pend} PENDIENTE (B6/B7), {fail} FALTA")
sys.exit(1 if fail else 0)
