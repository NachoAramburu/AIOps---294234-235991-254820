# Progreso del obligatorio

Cada commit agrega acá su sección. Las salidas completas van en `docs/evidencia/<id>/`.

## C01 — Base de trabajo del equipo — 2026-11-09 — francokbd
- **Estado:** 🟡 Parcial. Todo hecho salvo la URL del tablero, que queda `PENDIENTE` en `docs/tablero.md` hasta que se cree el Project en GitHub.
- **Ítem de rúbrica:** Transversal
- **Commit:** `C01: base de trabajo del equipo y registro de decisiones` (SHA en `git log --grep "^C01:"`)
- **Archivos creados / modificados:** `.gitignore`, `.gitattributes`, `docs/letra-obligatorio.md`, `docs/DECISIONES.md`, `docs/USO_IA.md`, `docs/PROGRESO.md`, `docs/tablero.md`, `docs/evidencia/.gitkeep`, `docs/evidencia/C01/`, `anomaly-detection/laboratorio_comparacion_detectores.ipynb`
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  $ git switch -c team/obligatorio origin/feature/k8s
  ## team/obligatorio...origin/feature/k8s  (dccba67)

  $ dotnet build PharmaGo.sln -c Release
  648 Warning(s), 0 Error(s)

  $ dotnet test PharnaGo.Test/PharmaGo.Test.csproj -c Release --no-build
  Failed Test_GetOneByExpression
  Failed: 1, Passed: 290, Total: 291

  Letra contra el docx: 73 de 73 frases presentes
  ```
  Detalle en `docs/evidencia/C01/baseline.txt` y `docs/evidencia/C01/letra-vs-docx.txt`.
- **Criterio de "hecho":** no aplica (commit transversal). Lo pedido está cumplido salvo la URL del tablero.
- **Decisiones tomadas:** roles A = Franco, B = Martin, C = Nacho. La sección RECORDATORIO de la letra y otros tres párrafos estaban resumidos: se reemplazaron por el texto literal del docx. El material interno del equipo (guía de trabajo, plan de prompts e instrucciones para la IA) se guarda fuera del repo, en la PC de cada integrante.
- **NO VERIFICADO / riesgos:** ninguno, salvo la URL del tablero.
- **Hallazgos nuevos que cambian el plan:** el repo se renombró a `NachoAramburu/AIOps---294234-235991-254820`; GitHub redirige el nombre viejo. El test que falla queda para C21, como estaba previsto.
- **Uso de IA registrado en docs/USO_IA.md:** sí
