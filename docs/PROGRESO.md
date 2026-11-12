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

## C02 — Cluster multinodo y prueba de memoria — 2026-11-10 — Martin Roux
- **Estado:** Hecho
- **Ítem de rúbrica:** 1 (Plataforma)
- **Commit:** `C02: cluster Minikube de 5 nodos, seed de datos y medicion de memoria` (SHA en `git log --grep "^C02:"`)
- **Archivos creados / modificados:**
  - Nuevos: `k8s/cluster-up.sh`, `k8s/seed-db.sh`, `docs/evidencia/C02/`
  - Modificados: `k8s/apply-k8s.sh` (sin etiquetado de nodos, corre desde cualquier directorio, falla si no se corrió `cluster-up.sh`), `k8s/build-images.sh` (mensaje), `k8s/README-k8s.md` (multinodo), `nodeAffinity` de gateway `[gateway]`, users `[users]`, pharmacy `[pharmacy]` y ui `[frontend]`, `busybox:1.36` en db, elasticsearch y prometheus, `mssql/server:2019-CU32-ubuntu-20.04`, `docs/DECISIONES.md` (D01, D08, D50)
  - Eliminados (D06): `k8s/apply-k8s.ps1`, `k8s/build-images.ps1`, `k8s/cleanup.ps1`
  - (rutas relativas a `Implementacion K8S/Codigo/`)
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  Confirmado antes de editar: apply-k8s.sh etiquetaba un solo nodo con node-type=all;
  ningún script aplicaba seed-data.sql; backend con nodeAffinity node-type In [backend, all].

  $ ./cluster-up.sh            (01-cluster-up.txt)
  minikube       Ready  control-plane  v1.33.13  frontend
  minikube-m02   Ready  <none>         v1.33.13  gateway
  minikube-m03   Ready  <none>         v1.33.13  users
  minikube-m04   Ready  <none>         v1.33.13  pharmacy
  minikube-m05   Ready  <none>         v1.33.13  ops       (runtime docker://29.7.2)

  $ ./build-images.sh          (02-build-images.txt)  4 imágenes, 0 Error(s)
  $ ./apply-k8s.sh             (03-apply-k8s.txt, ejecutado desde la raíz del repo)
  $ ./seed-db.sh  x3           (04-seed-db.txt)  sqlcmd en /opt/mssql-tools18 (-C); Roles=3 Users=3 Drugs=4 en las 3 corridas, exit 0

  $ kubectl get pods -A -o wide   (06-pods.txt)  20/20 Running y Ready en pharmago, 0 reinicios
  pharmago-ui -> minikube | api-gateway -> m02 | users -> m03 | pharmacy -> m04 | BD y observabilidad -> m05

  $ minikube ssh -n minikube-m03 -- docker images | grep pharmago   (07-images-m03.txt)
  las 4 imágenes pharmago-* presentes en m03 (y en m05)

  $ docker stats --no-stream      (08-memoria.txt)
  minikube-m05 3.535GiB / 4GiB (88%) | minikube 1.131GiB | m02 646MiB | m03 617MiB | m04 592MiB  => ~6,4 GiB total
  $ kubectl top pods: elasticsearch 915Mi, pharmago-db 900Mi, kibana 813Mi, users 116Mi, gateway 79Mi, pharmacy 77Mi

  $ kubectl logs fluent-bit (5 pods)   (09-fluent-bit.txt)  0 líneas con error/fail/refused/connection
  índice pharmago-logs-2026.11.10 con 2981 documentos

  $ kubectl port-forward svc/pharmago-api-gateway 15000:80 -n pharmago
  $ POST /api/login (admin, contraseña de seed-data.sql)   (10-login.txt)
  HTTP 200, role = Administrator     | control negativo con contraseña errónea: HTTP 400
  ```
- **Criterio de "hecho" de §3 (ítem 1):** parcial por diseño del plan. Hay 5 nodos (≥ 3) y hoy ningún nodo aloja dos microservicios distintos, pero eso sale solo de la `nodeAffinity`: la `podAntiAffinity` y el diagrama son de C03.
- **Decisiones tomadas:** D01 confirmada con 4096 MB por nodo (no hizo falta 4608). D50: Elasticsearch entra, no se cambia por Loki. D08 nueva: `seed-db.sh` toma la contraseña de `SA_PASSWORD` dentro del contenedor de BD, que ya viene del Secret, y nunca la imprime; además filtra la línea del seed que muestra la contraseña de los usuarios de prueba. `cluster-up.sh` acepta `MINIKUBE_MEMORY` para reintentar con más memoria sin editar el script.
- **NO VERIFICADO / riesgos:**
  - El nodo `ops` usa el 88 % de sus 4 GiB y los limits de sus pods suman 6,6 GiB. Con más carga (o al sumar Jaeger y el Collector en C10/C11) puede llegar a OOM. Si pasa: `MINIKUBE_MEMORY=4608`.
  - El host Windows quedó con ~0,6 GB libres mientras corre el cluster (WSL2 toma casi toda la RAM).
  - Login probado por API, no desde la UI.
- **Hallazgos nuevos que cambian el plan:**
  - En esta PC el puerto **5000 está en el `excludedportrange` de Windows**, así que `port-forward 5000:80` falla con "access forbidden". Se usó 15000. `port-forward.sh` sigue usando 5000; lo resuelve el Ingress de C04, o se cambia el puerto local si hace falta.
  - Había un perfil `minikube` viejo y roto (1 nodo, v1.35.1) que impedía crear el cluster: hubo que correr `minikube delete`. Conviene avisar al resto del equipo.
  - Las imágenes siguen con tag `:latest`; el tag con SHA corresponde a C08 (D21).
- **Uso de IA registrado en docs/USO_IA.md:** sí

## C15 — Detección de anomalías — 2026-11-11 — Ignacio Aramburu
- **Estado:** Hecho. El dataset de los docentes todavía no llegó: el cuaderno que lo procesa está listo y probado con un CSV de prueba.
- **Ítem de rúbrica:** 5 (Anomalías)
- **Commit:** `C15: Isolation Forest y One-Class SVM RBF no supervisados y reproducibles` (SHA en `git log --grep "^C15:"`)
- **Archivos creados / modificados:**
  - Modificado: `anomaly-detection/laboratorio_comparacion_detectores.ipynb` (TODO de las secciones 4 a 7, sección 10 nueva con las 7 respuestas y el exit ticket, ejecutado con salidas)
  - Nuevos: `anomaly-detection/requirements.txt`, `anomaly-detection/deteccion_dataset_docentes.ipynb`, `anomaly-detection/README.md`, `docs/evidencia/C15/`
  - `docs/DECISIONES.md` (D40 confirmada, D52 nueva), `docs/USO_IA.md`, `docs/PROGRESO.md`
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  $ python -m venv .venv && .venv/Scripts/python -m pip install -r requirements.txt   (01-entorno.txt)
  Python 3.12.10 | numpy 2.1.3, pandas 2.2.3, scikit-learn 1.5.2, matplotlib 3.9.2, nbconvert 7.16.4

  $ jupyter nbconvert --to notebook --execute --inplace laboratorio_comparacion_detectores.ipynb   (02-laboratorio.txt)
  exit 0, sin errores de celda
                    precision  recall     f1  alertas
  k-sigma error         1.000   0.189  0.317     10
  k-sigma lat           1.000   0.151  0.262      8
  MAD error             0.944   0.321  0.479     18
  MAD lat               1.000   0.679  0.809     36
  Isolation Forest      0.800   0.453  0.578     30     (esperado 0.800 / 0.453 / 0.578 / 30)
  One-Class SVM         0.621   0.340  0.439     29     (esperado 0.621 / 0.340 / 0.439 / 29)

  $ jupyter nbconvert --to notebook --execute --inplace deteccion_dataset_docentes.ipynb   (03-docentes-sin-dataset.txt)
  DATASET NO ENCONTRADO: datos/dataset_docentes.csv ... No se entrenó ningún modelo.   exit 0

  $ DATA_PATH=<csv del laboratorio> FEATURES=requests,error_rate,latency_ms,cpu_pct LABEL_COL=is_anomaly \
      jupyter nbconvert --execute deteccion_dataset_docentes.ipynb   (04-docentes-con-dataset-lab.txt)
  Isolation Forest 0.800 / 0.453 / 0.578 / 30 | One-Class SVM 0.621 / 0.340 / 0.439 / 29   (idéntico al laboratorio)

  $ 2 corridas extra de cada cuaderno + hash de scores en 2 procesos   (05-reproducibilidad.txt)
  sha256 de salidas idéntico en las 3 corridas; sha256 de scores c05bb6bb... en ambos procesos
  ```
- **Criterio de "hecho" de §3 (ítem 5):** cumplido. `anomaly-detection/` tiene Isolation Forest y One-Class SVM RBF, no supervisados (scaler y modelos sobre todas las ventanas, etiquetas solo para evaluar), de punta a punta con semilla fija, con `requirements.txt`, README y tabla comparativa.
- **Decisiones tomadas:** D40 confirmada con las versiones de `requirements.txt`. D52 nueva: el cuaderno de los docentes es genérico (`DATA_PATH`, `FEATURES`, `LABEL_COL`, también por variable de entorno) y con el CSV ausente avisa y termina sin error. `requirements.txt` va dentro de `anomaly-detection/`, junto a los cuadernos.
- **NO VERIFICADO / riesgos:**
  - El dataset de los docentes no llegó: no se sabe su formato. Si las columnas no son numéricas o la etiqueta tiene otro formato, el cuaderno lo informa con un error claro, y puede necesitar un ajuste menor.
  - Con 30 alertas sobre 53 anomalías reales, el recall máximo posible es 0.566: el presupuesto de alertas (0.10) limita el resultado, como se discute en el README.
- **Hallazgos nuevos que cambian el plan:** en esta PC, `python -m venv` falla porque la instalación de Python 3.12.10 no trae el wheel de pip para `ensurepip`. Se resolvió con `--without-pip` y el pip global; el README explica cómo. Puede pasarle a otro integrante.
- **Uso de IA registrado en docs/USO_IA.md:** sí

## C04 — Acceso estable por Ingress y rutas del gateway — 2026-11-12 — francokbd
- **Estado:** 🟡 Parcial. Cambios hechos y verificados en local; la verificación en el cluster queda pendiente porque esta PC no tiene Docker ni Minikube.
- **Ítem de rúbrica:** 8 (Defensa: acceso sin port-forward)
- **Commit:** `C04: acceso por Ingress sin port-forward y rutas del gateway corregidas` (SHA en `git log --grep "^C04:"`)
- **Archivos creados / modificados:** `Backend/PharmaGo.ApiGateway/appsettings.json`, `Frontend/src/environments/environment.prod.ts`, `k8s/cluster-up.sh`, `k8s/apply-k8s.sh`, `k8s/port-forward.sh`, `k8s/README-k8s.md`, `k8s/ingress/pharmago-ingress.yaml` (nuevo), `docs/evidencia/C04/` (rutas relativas a `Implementacion K8S/Codigo/` salvo `docs/`)
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  Confirmado antes de editar: apiUrl 'http://127.0.0.1:5000' en environment.prod.ts; rutas /api/unitmeasure
  y /api/presentation en el gateway; el frontend llama a /api/unitmeasures y /api/presentations.

  $ bash -n cluster-up.sh apply-k8s.sh port-forward.sh        -> sintaxis OK
  $ ingress/pharmago-ingress.yaml (PyYAML)                     -> /api -> pharmago-api-gateway:80, / -> pharmago-ui:80
  $ gateway real contra backend falso
    /api/presentations 200, /api/unitmeasures 200, /api/presentations/3 200 (path intacto)
    /api/presentation 404, /api/unitmeasure 404 (rutas viejas eliminadas)
  $ npx ng build (producción)                                  -> exit 0; "127.0.0.1:5000" aparece 0 veces en main.js
  ```
  Detalle en `docs/evidencia/C04/01-sintaxis.txt`, `02-gateway-rutas.txt` y `03-frontend-build.txt`.
- **Criterio de "hecho":** cumplido en código. La parte de cluster (Ingress respondiendo 200 por `minikube tunnel`, login y recuperación tras borrar un pod) está NO VERIFICADA.
- **Decisiones tomadas:** `apply-k8s.sh` espera a que el controlador de ingress-nginx esté listo antes de aplicar el Ingress; si no, el apply falla porque su webhook de admisión todavía no responde. `port-forward.sh` dejó de exponer la BD, que además imprimía la contraseña.
- **NO VERIFICADO / riesgos:** todo lo de cluster. Comandos exactos en `docs/evidencia/C04/04-cluster-pendiente.txt`, para que los corra quien tenga el cluster (Martin) y lo suba como `C04-verificacion`.
- **Hallazgos nuevos que cambian el plan:** la prueba de "borrar un pod de la UI sin que se corte el loop" supone 2 réplicas, que llegan en C06. En C04 se verifica que el acceso vuelve solo; el "0 errores" se mide en C06. La URL del tablero sigue pendiente: no se creó el Project todavía.
- **Uso de IA registrado en docs/USO_IA.md:** sí

## C04-verificacion — Evidencia de C04 en el cluster — 2026-11-12 — Martin Roux
- **Estado:** Hecho
- **Ítem de rúbrica:** 8 (Defensa: app accesible sin port-forward)
- **Commit:** `C04-verificacion: evidencia de C04 en el cluster` (SHA en `git log --grep "^C04-verificacion:"`)
- **Archivos creados / modificados:** `docs/evidencia/C04/05-cluster-up.txt` a `11-delete-pod-ui.txt`, `docs/PROGRESO.md`, `docs/USO_IA.md`. No se tocó código: se verificó tal cual quedó en C04 (`708f4f9`).
- **Dónde se corrió:** PC de Martin, cluster Minikube de 5 nodos de C02, `minikube tunnel` abierto en PowerShell como administrador.
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  $ ./cluster-up.sh       (05)  The 'ingress' addon is enabled; 5 nodos Ready con su node-type
  $ ./build-images.sh     (06)  4 imágenes reconstruidas, 0 Error(s)
  $ ./apply-k8s.sh        (07)  ingress-nginx-controller condition met; ingress.networking.k8s.io/pharmago-ingress created
  $ kubectl rollout restart deployment pharmago-api-gateway pharmago-users-service pharmago-pharmacy-service pharmago-ui -n pharmago
  $ kubectl rollout status ...   (08)  los 4 "successfully rolled out"
  $ kubectl get ingress -n pharmago
  pharmago-ingress   nginx   *   192.168.49.2   80

  1. Rutas por http://127.0.0.1 (sin port-forward)   (09)
  / 200 | /api/drug 200 | /api/presentations 200 | /api/unitmeasures 200
  control: /api/presentation 404 | /api/unitmeasure 404 (rutas viejas en singular)
  control: el bundle main.*.js servido ya no contiene "127.0.0.1:5000"

  2. POST http://127.0.0.1/api/login (admin, contraseña de seed-data.sql)   (10)
  HTTP 200, role = Administrator | contraseña incorrecta: HTTP 400

  3. Loop curl http://127.0.0.1/ cada 1 s x 40 s, borrando el pod de la UI en t=10 s   (11)
  t=1..10 200 | t=11 000 | t=12..24 503 | t=25..40 200
  40 requests: 26 con 200, 14 con error (000 x1, 503 x13); pod nuevo pharmago-ui-...-xqz9p
  ```
- **Criterio de "hecho":** cumplido para C04. La app (UI y API) responde por `http://127.0.0.1` con el Ingress y `minikube tunnel`, sin port-forward. Las rutas corregidas dan 200 y el login funciona. Tras borrar el pod de la UI, el acceso vuelve solo con la misma URL, sin reabrir nada. El "0 errores" no aplica todavía: con 1 réplica hubo ~14 s de corte (503 del ingress mientras no había pod Ready). Eso se mide en C06 con 2 réplicas.
- **Decisiones tomadas:** ninguna nueva.
- **NO VERIFICADO / riesgos:**
  - Login probado por API a través del Ingress, no haciendo clic en la UI desde el navegador.
  - `pharmago-users-service` acumulaba 7 reinicios después de prender el cluster (antes del rollout). Probablemente arrancó antes que la BD y fallaron sus probes; se normalizó solo. Lo cubren C05 (tolerancia a fallas de la BD) y C06 (probes).
- **Hallazgos nuevos que cambian el plan:** ninguno. El corte de ~14 s con 1 réplica de UI es la línea base contra la que C06 tiene que mostrar 0 errores.
- **Uso de IA registrado en docs/USO_IA.md:** sí

## C05 — Endpoints de salud y resiliencia de la base — 2026-11-12 — Martin Roux
- **Estado:** Hecho
- **Ítem de rúbrica:** 2 (Alta disponibilidad)
- **Commit:** `C05: endpoints live y ready, y resiliencia ante fallas transitorias de la base` (SHA en `git log --grep "^C05:"`)
- **Archivos creados / modificados** (en `Implementacion K8S/Codigo/Backend/`):
  - `PharmaGo.UsersService.Factory` y `PharmaGo.PharmacyService.Factory`: paquete `Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore` 6.0.8 y `EnableRetryOnFailure(3, 2 s)` en `ServiceFactory.cs`.
  - `PharmaGo.UsersService.Factory/ServiceFactory.cs`: `MigrateDatabase` con hasta 30 intentos, espera de min(intento, 5) s y un scope nuevo por intento.
  - `PharmaGo.UsersService/Program.cs` y `PharmaGo.PharmacyService/Program.cs`: check `self` (tag live) y `AddDbContextCheck<DbContext>` (tag ready). `/health/live`, `/health/ready`, y `/health` sin mirar la BD.
  - `PharmaGo.ApiGateway/Program.cs`: check `self` (live y ready, sin BD por D11) y los 3 endpoints antes de `MapReverseProxy`. `appsettings.json`: `get:/health/live` y `get:/health/ready` en `EndpointWhitelist`.
  - `docs/DECISIONES.md` (D10), `docs/evidencia/C05/`.
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  Confirmado antes de editar: users y pharmacy con AddHealthChecks() vacío y MapHealthChecks("/health");
  gateway sin health checks; MigrateDatabase solo en users (y en el monolito, que no se toca), sin reintentos;
  grep BeginTransaction|TransactionScope: sin resultados.

  $ dotnet build PharmaGo.sln -c Release          (01)  0 Errores, 648 advertencias (igual que el baseline)
  $ dotnet test ... --no-build                    (01)  Superado 290, Con error 1 (Test_GetOneByExpression, el mismo del baseline)

  Pharmacy local SIN BD (Server=127.0.0.1,1; Connect Timeout=2)   (02)
  /health/live  200 en 0,003 s | /health/ready 503 en 3,9 s | /health 200

  Gateway local                                   (03)
  150 GET a /health/live -> 200 x150 | 150 GET a /health/ready -> 200 x150
  control: 150 GET a una ruta fuera del whitelist -> 404 x100, 429 x50

  Cluster: build-images, apply-k8s, rollout restart de los 4 Deployments   (04, 05)
  gateway, users y pharmacy: /health/live, /health/ready y /health -> 200 en los 9
  ready en caliente: users 12-245 ms, pharmacy 12-94 ms (el primero de pharmacy, en frío: 3,5 s)

  MigrateDatabase                                 (06)
  cluster con BD: "migración aplicada (intento 1)"
  local sin BD: intento 1/30 falló... reintentando en 1 s; 2/30 -> 2 s; 3/30 -> 3 s
  ```
- **Criterio de "hecho" de §3 (ítem 2):** parcial por diseño del plan. Cumplida la parte de C05: `/health/live` y `/health/ready` en los 3 servicios .NET, con `ready` chequeando la BD en users y pharmacy. Las réplicas, los probes rápidos y la medición de `kubectl delete pod` son de C06, y Polly de C07.
- **Decisiones tomadas:** `/health` queda como estaba (no depende de la BD), con el mismo predicado que live, para no cambiar el comportamiento de los probes actuales antes de C06. D10 actualizada con lo medido.
- **NO VERIFICADO / riesgos:**
  - No se probó en el cluster la caída de la BD (ready 503 con pods vivos). Se probó en local. Corresponde a los experimentos de caos (C16-C18).
  - No se probó en el cluster el arranque con la BD caída ni dos réplicas migrando a la vez. El reintento se vio en local, y las 2 réplicas llegan en C06.
  - Con la BD inaccesible, ready tarda ~3,9 s en responder 503. Con el timeout de 2 s de C06 el probe falla igual (el resultado es el correcto), pero conviene tenerlo en cuenta al leer los eventos.
- **Hallazgos nuevos que cambian el plan:** ninguno. Para C06: el primer ready de pharmacy tras arrancar tardó 3,5 s; con `failureThreshold` 2-3 no debería sacarlo de servicio, pero hay que mirarlo al medir el MTTR.
- **Uso de IA registrado en docs/USO_IA.md:** sí
