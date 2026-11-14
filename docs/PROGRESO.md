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

## C03 — Separación de microservicios por nodo y diagrama — 2026-11-12 — Ignacio Aramburu
- **Estado:** Hecho
- **Ítem de rúbrica:** 1 (Plataforma)
- **Commit:** `C03: anti-afinidad entre microservicios y diagrama de despliegue` (SHA en `git log --grep "^C03:"`)
- **Dónde se corrió:** PC de Ignacio Aramburu (16 GB, 12 CPU, Docker con 9,7 GiB por `.wslconfig memory=10GB`), cluster de 5 nodos creado desde cero con `cluster-up.sh`, `build-images.sh`, `apply-k8s.sh` y `seed-db.sh`.
- **Archivos creados / modificados:**
  - Modificados: `podAntiAffinity` en `k8s/deployments/backend/api-gateway-deployment.yaml`, `users-service-deployment.yaml`, `pharmacy-service-deployment.yaml` y `k8s/deployments/frontend/ui-deployment.yaml` (rutas relativas a `Implementacion K8S/Codigo/`)
  - Nuevos: `Implementacion K8S/Codigo/k8s/verify/check-separacion.sh`, `docs/diagrama-despliegue.md`, `docs/evidencia/C03/`
  - `docs/DECISIONES.md` (D07), `docs/USO_IA.md`, `docs/PROGRESO.md`
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  Confirmado antes de editar: los 4 Deployments tenían nodeAffinity por node-type (C02) y ninguna podAntiAffinity.

  $ check-separacion.sh con kubectl falso (antes del cluster): caso OK -> exit 0; caso con gateway y ui en el mismo nodo -> VIOLACION, exit 1

  $ ./cluster-up.sh && ./build-images.sh && ./apply-k8s.sh && ./seed-db.sh   (01-cluster.txt)
  5 nodos Ready con node-type; calico-node 5/5 Running; 4 imágenes cargadas; Roles=3 Users=3 Drugs=4

  $ kubectl get deploy <microservicio> -o jsonpath='{...podAntiAffinity}'   (02-antiafinidad-aplicada.txt)
  cada uno: required, topologyKey kubernetes.io/hostname, app In [los otros tres]

  $ kubectl get pods -n pharmago -o wide   (03-pods.txt)   20/20 Running
  pharmago-ui -> minikube | api-gateway -> m02 | users -> m03 | pharmacy -> m04 | BD y observabilidad -> m05

  $ bash k8s/verify/check-separacion.sh   (04-check-separacion.txt)
  OK: ningún nodo aloja dos microservicios distintos.   exit=0

  $ Pod busybox:1.36 con app=pharmago-users-service y nodeSelector minikube-m02   (05-prueba-negativa.txt)
  STATUS Pending | FailedScheduling: 0/5 nodes are available: 1 node(s) didn't satisfy existing pods
  anti-affinity rules, 4 node(s) didn't match Pod's node affinity/selector.
  endpoints de pharmago-users-service sin cambios (no recibe tráfico); pod borrado al terminar.
  ```
- **Criterio de "hecho" de §3 (ítem 1):** cumplido. 5 nodos (≥ 3), ningún nodo aloja dos microservicios distintos (lo garantiza la `podAntiAffinity` required y lo comprueba `check-separacion.sh`) y `docs/diagrama-despliegue.md` (Mermaid) es coherente con los manifiestos y con `kubectl get pods -o wide`.
- **Decisiones tomadas:** se aplicó D02 tal cual (anti-afinidad solo contra los otros tres microservicios, sin label común). D07 actualizada: además del `.wslconfig`, hace falta WSL actualizado para que arranque Calico.
- **NO VERIFICADO / riesgos:**
  - Con 1 réplica por microservicio la prueba no muestra réplicas compartiendo nodo; eso se ve en C06 (2 réplicas). Con `maxSurge: 1` (C08) el pod extra del rollout también va al mismo nodo, así que la anti-afinidad no lo bloquea.
  - El diagrama no se renderizó con una herramienta automática (no se permitió instalar `mermaid-cli`); la sintaxis se revisó a mano. Verlo en la vista previa de GitHub o VS Code.
- **Hallazgos nuevos que cambian el plan:**
  - **Calico v3.32.2 (el de minikube v1.39.0) no arranca con WSL 2.2.4 / kernel 5.15.153:** `calico-node` queda en CrashLoopBackOff porque no puede montar `/sys/kernel/security`, que ese kernel no tiene. Sin red no arranca nada más (CoreDNS, ingress, metrics-server). Se resolvió con `wsl --update` (WSL 3.0.5, kernel 6.18), `wsl --shutdown`, `minikube delete` y `cluster-up.sh`. Conviene que todo el equipo corra `wsl --version` antes de crear el cluster.
  - Confirmado: el addon ingress corre en el nodo `minikube` (control-plane), junto a la UI, como dice el diagrama.
- **Uso de IA registrado en docs/USO_IA.md:** sí

## C06 — Réplicas, probes rápidas y secretos — 2026-11-12 — Ignacio Aramburu
- **Estado:** Hecho, con 1 error en 5 pruebas de borrado de pod (ver abajo); el arreglo de fondo es de C08.
- **Ítem de rúbrica:** 2 (Alta disponibilidad)
- **Commit:** `C06: dos replicas, probes rapidas, PDB y cadena de conexion por Secret` (SHA en `git log --grep "^C06:"`)
- **Dónde se corrió:** PC de Ignacio Aramburu, cluster de C03, `minikube tunnel` abierto en PowerShell como administrador. Antes de verificar: `build-images.sh`, `apply-k8s.sh` y `rollout restart` de los 4 Deployments.
- **Archivos creados / modificados** (rutas relativas a `Implementacion K8S/Codigo/k8s/`):
  - Modificados: `deployments/backend/api-gateway-deployment.yaml`, `users-service-deployment.yaml`, `pharmacy-service-deployment.yaml`, `deployments/frontend/ui-deployment.yaml` (2 réplicas y probes; en users y pharmacy, `SA_PASSWORD` por `secretKeyRef` y cadena con `$(SA_PASSWORD)`), `deployments/ops/otel-collector-deployment.yaml` (resources), `apply-k8s.sh` (paso 10: PDB)
  - Nuevos: `pdb/` (4 PodDisruptionBudget), `docs/evidencia/C06/` (incluye `loop-delete-pod.sh`, el script de la prueba)
  - `docs/DECISIONES.md` (D18), `docs/USO_IA.md`, `docs/PROGRESO.md`
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  Confirmado antes de editar: replicas: 1 en los 4; probes con period 10 a 30 s (tcpSocket en el gateway, /health en users y
  pharmacy); contraseña en texto plano en la cadena de conexión de users y pharmacy.

  $ kubectl get deploy,pdb -n pharmago   (01-deploy-pdb.txt)
  pharmago-api-gateway 2/2 | pharmago-users-service 2/2 | pharmago-pharmacy-service 2/2 | pharmago-ui 2/2
  4 PDB minAvailable 1, ALLOWED DISRUPTIONS 1

  $ bash k8s/verify/check-separacion.sh   (02-check-separacion.txt)   OK, exit=0 (las 2 réplicas de cada uno en su nodo)

  $ grep -rn "Str0ngP" k8s/deployments/   (03-secretos.txt)   sin resultados, exit=1
  users y pharmacy Ready con readiness /health/ready, que consulta la BD: la cadena expandida desde el Secret funciona

  $ probes aplicadas en el cluster   (04-probes-aplicadas.txt)
  startup p=2 ft=60 t=2 | readiness p=2 ft=2 t=2 | liveness p=3 ft=2 t=2

  $ loop-delete-pod.sh: 1 curl/s x 40 s, kubectl delete pod de una réplica en t=10 s   (05 a 08)
  gateway   /api/drug   40/40 2xx, 0 no-2xx | vuelve a 2/2 Ready en 5,7 s
  users     /api/drug   40/40 2xx, 0 no-2xx | vuelve a 2/2 Ready en 7,3 s   (este tráfico va a pharmacy, ver 08)
  pharmacy  /api/drug   40/40 2xx, 0 no-2xx | vuelve a 2/2 Ready en 8,0 s
  users     /api/roles  40/40 2xx, 0 no-2xx | vuelve a 2/2 Ready en 7,2 s   (tráfico que sí atiende users)
  pharmacy  /api/drug   39/40 2xx, 1 x HTTP 502 en t=10 s, el segundo del delete | 2/2 en 9,0 s   (09, corrida del integrante)
  ```
- **Criterio de "hecho" de §3 (ítem 2):** parcial, como prevé el plan. Cumplido: `replicas: 2` en los 4, probes con period 2 a 3 s y failureThreshold 2, y vuelta a READY en menos de 15 s (5,7 a 9,0 s), medido. **No cumplido todavía:** "`kubectl delete pod` no produce errores": en 4 corridas hubo 0 errores, pero en la quinta (la del integrante) hubo un 502 justo al borrar el pod. Falta el apagado ordenado (`preStop`, C08) y el retry del gateway (C07).
- **Decisiones tomadas:** D12 y D17 aplicadas tal cual. D18 nueva: un PDB `minAvailable: 1` por microservicio. Se agregó `Connect Timeout=2` a la cadena de conexión, como pide el plan, para que una BD caída no trabe la readiness más que su timeout.
- **NO VERIFICADO / riesgos:**
  - El loop va a 1 request por segundo (límite del rate limit, AGENTS §5): un error de menos de 1 s entre dos requests podría no verse. C09 hace la medición formal.
  - No se probó el borrado de un pod de la UI con 2 réplicas. C04-verificación lo midió con 1 réplica (~14 s de corte); con 2 debería no cortar, y queda para C09.
  - `kubectl delete pod` es un apagado ordenado (SIGTERM): no se probó un crash abrupto ni un pod que deje de responder sin morir (eso lo cubre la liveness y se prueba con el caos de C16).
  - **Confirmado en la corrida 09:** sin `preStop`, el pod se apaga mientras el cambio de endpoints se propaga y el gateway puede mandarle una request (502). Con 1 request/s la ventana es de una fracción de segundo, por eso salió en 1 de 5 corridas. Lo corrige C08 (`preStop sleep 5`, D20) y lo atenúa C07 (retry de GET).
- **Hallazgos nuevos que cambian el plan:**
  - `GET /api/drug` va a pharmacy-service; para probar users hace falta otro endpoint. `GET /api/roles` responde 200 sin login y lo atiende users.
  - Algunos archivos de la copia local tenían CRLF de un checkout viejo con `core.autocrlf=true` (en el repo están en LF). `otel-collector-deployment.yaml` se normalizó a LF al editarlo.
- **Uso de IA registrado en docs/USO_IA.md:** sí

## C07 — Circuit breaker, reintentos y timeout en el gateway — 2026-11-13 — francokbd (bloque B1)
- **Estado:** 🟡 Parcial. Implementado y probado en local con el gateway real; la prueba en el cluster queda pendiente (esta PC no tiene Docker ni Minikube).
- **Ítem de rúbrica:** 2 (Alta disponibilidad: patrón ante fallas reiteradas)
- **Commit:** `C07-C09: resiliencia del gateway y despliegue seguro` (SHA en `git log --grep "^C07-C09:"`)
- **Archivos creados / modificados:** `Backend/PharmaGo.ApiGateway/Resilience/ResilientForwarderHttpClientFactory.cs` (nuevo), `Backend/PharmaGo.ApiGateway/Program.cs`, `Backend/PharmaGo.ApiGateway/PharmaGo.ApiGateway.csproj` (Polly 7.2.4), `Backend/PharmaGo.ApiGateway/appsettings.json` (sección `Resilience`), `Backend/InstrumentationInterface/ICustomMetrics.cs`, `Backend/Instrumentation/CustomMetrics.cs`, `k8s/verify/test-circuit-breaker.sh` (nuevo), `docs/resiliencia.md` (nuevo)
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  Confirmado antes de editar: PharmacyServiceClient y UsersServiceClient no se inyectan en ningún lado;
  los clusters de YARP tienen HealthCheck.Active.Enabled=false.

  $ dotnet build PharmaGo.sln -c Release           -> 0 Error(s)
  $ dotnet test (PharmaGo.Test)                     -> 290 de 291, igual que el punto de partida
  $ gateway real contra backend falso (01-gateway-local.txt)
    GET con 500: 1 intento (no se reintenta)
    12 GET con el backend fallando: 500 x7, después 503 con Retry-After: 5 y {"error":"circuit_open"}
    POST con el circuito abierto: 503 sin llegar al backend
    backend sano + 6 s: 200 x4; log: open for 5s -> half-open -> closed
    backend lento (8 s): GET 504 en 9,5 s con 3 intentos; POST 504 en 3,1 s con 1 intento
    pharmago_circuit_breaker_state{cluster="pharmacy-cluster"} 0 -> 1 -> 0
    rate limit: 120 GET -> 100 con 200 y 20 con 429; 150 GET /health/live sin 429
  ```
- **Criterio de "hecho":** cumplido en código y probado en local. La prueba en el cluster (`test-circuit-breaker.sh`) está NO VERIFICADA.
- **Decisiones tomadas:** D13 implementada con timeout de 3 s por intento. La métrica del breaker va sin unidad (ver hallazgos). Los health checks de YARP siguen apagados (D14).
- **NO VERIFICADO / riesgos:** `test-circuit-breaker.sh` en el cluster. Comandos en `docs/evidencia/C07/cluster-pendiente.txt`.
- **Hallazgos nuevos que cambian el plan:** con unidad `{state}` (lo que decía AGENTS.md §5), el exporter Prometheus de .NET publica `pharmago_circuit_breaker_state__state_`. Sin unidad sale `pharmago_circuit_breaker_state`, que es el nombre que usa la alerta del bloque B6. El gateway todavía expone `/metrics` directo; pasa a OTLP en C10.
- **Uso de IA registrado en docs/USO_IA.md:** sí (una fila para el bloque B1)

## C08 — Despliegue sin caídas y rollback — 2026-11-13 — francokbd (bloque B1)
- **Estado:** 🟡 Parcial. Manifiestos y scripts hechos y verificados en local (YAML, sintaxis y lógica con kubectl simulado); el rollout real queda pendiente.
- **Ítem de rúbrica:** 3 (Despliegues seguros)
- **Commit:** `C07-C09: resiliencia del gateway y despliegue seguro`
- **Archivos creados / modificados:** los Deployments de gateway, users, pharmacy y ui (RollingUpdate, `maxUnavailable: 0`, `maxSurge: 1`, `minReadySeconds: 5`, `revisionHistoryLimit: 5`, `terminationGracePeriodSeconds: 30`, `preStop sleep 5`, imagen `:IMAGE_TAG`, `ephemeral-storage` 64Mi y 512Mi), `prometheus-deployment.yaml` (`v2.53.4`), `otel-collector-deployment.yaml` (`0.111.0`), `k8s/build-images.sh`, `k8s/apply-k8s.sh`, `k8s/deploy.sh` (nuevo), `k8s/rollback.sh` (nuevo), `k8s/README-k8s.md`; eliminado `k8s/build-ui.sh`
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  Confirmado antes de editar: los 4 Deployments sin strategy, con imágenes :latest e imagePullPolicy Never.

  $ grep -rn ":latest" k8s/                          -> 0 resultados
  $ bash -n (5 scripts)                              -> OK
  $ IMAGE_TAG -> abc1234 + PyYAML (01-manifiestos.txt)
    los 4: RollingUpdate maxUnavailable=0 maxSurge=1 minReadySeconds=5 preStop=sleep 5 ephemeral-storage 64Mi/512Mi
  $ deploy.sh y rollback.sh con kubectl simulado (02-deploy-rollback-simulado.txt)
    sin tag -> uso; imagen inexistente -> error; exitoso -> users, pharmacy, gateway, ui en orden;
    rollout del gateway trabado -> rollout undo del gateway, exit 1, ui sin tocar;
    rollback.sh: nombre inválido -> error; uno -> solo ese; sin argumento -> los 4
  $ tag calculado con cambios sin commitear          -> 575991f-dirty
  ```
- **Criterio de "hecho":** cumplido en manifiestos y scripts. El rollout v1 → v2 → rollback en el cluster está NO VERIFICADO.
- **Decisiones tomadas:** D20 y D21 aplicadas. El paso 6 de C16 (límites de `ephemeral-storage`) se hizo acá, por el plan del 13/11. `deploy.sh` anota `kubernetes.io/change-cause` antes de cada cambio, así `rollout history` muestra el tag. `apply-k8s.sh` corta con un mensaje claro si falta la imagen del tag, en vez de dejar pods en `ErrImageNeverPull`.
- **NO VERIFICADO / riesgos:** todo lo de cluster. Comandos en `docs/evidencia/C08/cluster-pendiente.txt`.
- **Hallazgos nuevos que cambian el plan:** ninguno.
- **Uso de IA registrado en docs/USO_IA.md:** sí (fila del bloque B1)

## C09 — Prueba de cero errores, medición de MTTR y documentación — 2026-11-13 — francokbd (bloque B1)
- **Estado:** 🟡 Parcial. Scripts y documentación hechos; la medición en el cluster queda pendiente.
- **Ítem de rúbrica:** 3 (Despliegues seguros) y la actividad "reducir el MTTR"
- **Commit:** `C07-C09: resiliencia del gateway y despliegue seguro`
- **Archivos creados / modificados:** `k8s/verify/test-rollout.sh` (nuevo), `k8s/verify/measure-mttr.sh` (nuevo, modos borrado y `--crash`), `docs/despliegue-seguro.md` (nuevo), `docs/mttr.md` (nuevo)
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  $ bash -n verify/test-rollout.sh verify/measure-mttr.sh   -> OK
  $ validación de argumentos (01-scripts.txt)                -> uso o error claro en cada caso inválido
  $ sin la app accesible                                     -> los dos scripts se niegan a medir (exit 1)
  ```
  Mediciones previas usadas en `docs/mttr.md`, todas de evidencia ya commiteada: C06 (borrado de pod, 5,7 a 9,0 s, 1 error en 5 pruebas) y C04-verificación (UI con 1 réplica, unos 14 s de corte).
- **Criterio de "hecho":** no cumplido todavía: falta medir 0 no-2xx en el rollout y menos de 15 s al borrar un pod.
- **Decisiones tomadas:** el loop de `test-rollout.sh` rota entre `/`, `/api/drug` y `/api/roles` a 1 request por segundo, para pasar tráfico por los 4 microservicios sin chocar con el rate limit; los 429 se informan aparte. `measure-mttr.sh` usa `/api/roles` para users, que responde sin login (hallazgo de C06).
- **NO VERIFICADO / riesgos:** las mediciones. Comandos en `docs/evidencia/C09/cluster-pendiente.txt`; con esos números se completan las filas "Pendiente" de `docs/mttr.md`.
- **Hallazgos nuevos que cambian el plan:** el error que vio C06 (502 en el segundo del borrado) es la carrera entre el apagado del pod y su salida del Service. Lo corrigen el `preStop` de C08 y el reintento de GET de C07; está explicado en `docs/mttr.md`.
- **Uso de IA registrado en docs/USO_IA.md:** sí (fila del bloque B1)

## B1-verificacion — Evidencia de C07 a C09 en el cluster — 2026-11-14 — Martin Roux
- **Estado:** Hecho
- **Ítem de rúbrica:** 2 (Alta disponibilidad: circuit breaker y MTTR) y 3 (Despliegues seguros)
- **Commit:** `B1-verificacion: evidencia de C07 a C09 en el cluster` (SHA en `git log --grep "^B1-verificacion:"`)
- **Dónde se corrió:** PC de Martin, cluster de 5 nodos de C02, `minikube tunnel` abierto en PowerShell como administrador. No se tocó código: se verificó el bloque B1 tal cual quedó en `be11702`, con los comandos de `docs/evidencia/C07/`, `C08/` y `C09/cluster-pendiente.txt`.
- **Archivos creados / modificados:** `docs/evidencia/C07/02-cluster-circuit-breaker.txt`, `03-cluster-metrica-breaker.txt`; `docs/evidencia/C08/03-cluster-build.txt`, `04-cluster-apply.txt`, `05-cluster-deploy-rollback.txt`; `docs/evidencia/C09/02-cluster-test-rollout.txt`, `03-cluster-mttr.txt`; filas "Pendiente" de `docs/mttr.md` y sección "Resultado" de `docs/despliegue-seguro.md`; `docs/PROGRESO.md`, `docs/USO_IA.md`.
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  $ ./build-images.sh  /  ./build-images.sh be11702-v2   (C08/03)  tags be11702 y be11702-v2 cargados
  $ ./apply-k8s.sh                                       (C08/04)  los 4 Deployments 2/2 con :be11702; grep ":latest" sin resultados

  C07
  $ bash verify/test-circuit-breaker.sh                  (C07/02)
  users a 0 réplicas: 502 502 502 503 502 503 503 ... (desde la 4.ª request, 503 circuit_open)
  logs del gateway: users-cluster state=open for 5s -> half-open -> open ... -> closed
  al restaurar: 200 a 1 s; "OK: el circuito se abrió (503 circuit_open) y el servicio se recuperó solo."
  $ curl /metrics | grep pharmago_circuit_breaker_state  (C07/03, port-forward 15000:80)
  {cluster="pharmacy-cluster"} 0 | {cluster="users-cluster"} 0

  C08
  $ ./deploy.sh be11702-v2   -> "Listo: los 4 microservicios corren be11702-v2", exit=0   (C08/05)
  $ kubectl rollout history deployment/pharmago-api-gateway   -> revisión con CHANGE-CAUSE "deploy.sh be11702-v2"
  $ ./rollback.sh            -> los 4 de vuelta en :be11702, exit=0

  C09
  $ bash verify/test-rollout.sh be11702-v2               (C09/02)
  Resultado: 145 requests | 2xx: 145 | 429: 0 | otras no-2xx: 0
  OK: 0 respuestas no-2xx durante v1 -> v2 -> rollback.
  $ bash verify/measure-mttr.sh <deployment> [--crash]   (C09/03)
                     borrado de pod      crash (kill 1)
  api-gateway        4,1 s  0/40 err     4,4 s  0/40 err
  users-service      5,4 s  0/40 err     8,8 s  0/40 err
  pharmacy-service   6,7 s  0/40 err     7,4 s  0/40 err
  ui                 5,4 s  0/40 err     3,0 s  0/40 err
  ```
- **Criterio de "hecho" de §3:** cumplido para B1.
  - Ítem 2: el circuit breaker pasa por Closed, Open, Half-Open y Closed en el cluster, con la métrica publicada. `kubectl delete pod` no produce errores y el pod vuelve a Ready en menos de 15 s (4,1 a 6,7 s), y lo mismo ante un crash (3,0 a 8,8 s).
  - Ítem 3: rollout v1 → v2 → rollback con 0 respuestas no-2xx.
  - El 502 de C06 no se repitió en ninguna de las 9 pruebas.
- **Decisiones tomadas:** ninguna nueva. Para no saturar la memoria de esta PC, las imágenes se compilaron con el cluster apagado (`docker build` con el mismo tag) y después `build-images.sh` solo las cargó desde el caché.
- **NO VERIFICADO / riesgos:**
  - La resolución de las mediciones es de 1 s, la del loop: un corte menor a 1 s entre dos requests no se vería.
  - La v2 es el mismo código con otro tag: prueba el mecanismo, no un cambio funcional.
- **Hallazgos nuevos que cambian el plan:**
  - **`rollout history` etiqueta mal la revisión.** Después del rollback, la revisión que corre la v1 (`be11702`) muestra CHANGE-CAUSE "deploy.sh be11702-v2". `deploy.sh` anota `kubernetes.io/change-cause` en el Deployment antes del `set image` (la anotación también queda en la revisión vigente) y `rollback.sh` no la actualiza, así que la anotación vieja pasa a la revisión nueva. Las imágenes y el rollback son correctos; solo la etiqueta confunde. Arreglo sugerido: anotar después del `set image` y anotar "rollback.sh" en `rollback.sh`. No se tocó en esta verificación.
  - En esta PC el puerto 5000 está reservado por Windows, así que el port-forward de la métrica se hizo por el 15000.
- **Uso de IA registrado en docs/USO_IA.md:** sí

## C16 — Scripts de caos 1/2: requests, CPU, memoria y storage — 2026-11-14 — Martin Roux (bloque B2)
- **Estado:** Hecho
- **Ítem de rúbrica:** 7 (Scripts de caos)
- **Commit:** `C16-C17: scripts de caos de los seis tipos de falla` (SHA en `git log --grep "^C16-C17:"`)
- **Dónde se corrió:** PC de Martin, cluster de 5 nodos con B1 aplicado (imágenes `be11702`), `minikube tunnel` abierto.
- **Archivos creados / modificados** (en `Implementacion K8S/Codigo/chaos-engineering/`): `lib.sh` (nuevo); `cpu-spike.sh`, `ram-spike.sh`, `volume-spike.sh` y `load-requests.sh` reescritos; `README.md`. El paso 6 (límites de `ephemeral-storage`) no se hizo acá: ya venía del bloque B1.
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  Confirmado antes de editar: cpu-spike dejaba loops vivos, ram-spike escribía en /dev/shm, volume-spike no limpiaba,
  ninguno validaba argumentos ni el contexto de kubectl.

  $ bash -n (5 scripts) y argumentos inválidos            (01)  OK; uso o error claro en cada caso
  $ ./cpu-spike.sh pharmago-api-gateway 20 4              (02)
    cgroup cpu.stat: 10,1 s de CPU en 21,7 s (~0,47 núcleos, el limits.cpu de 500m), nr_throttled +201
    "Loops que quedan: 0"; /proc/*/cmdline después: solo dotnet
  $ ./ram-spike.sh pharmago-pharmacy-service 150 40       (03)
    Prometheus (container_memory_working_set_bytes, nivel pod): 68,3 -> 219,1 -> 68,4 MiB
  $ ./ram-spike.sh pharmago-pharmacy-service 500 30       (04)
    exit 137 del experimento; memory.events: oom_kill 1, oom_group_kill 0; la app no se reinicia (ver hallazgos)
  $ ./volume-spike.sh pharmago-users-service 200 30       (05)
    du /tmp: 1 -> 201 -> 1 MB; "Archivo /tmp/chaos_fill borrado"
  $ ./volume-spike.sh pharmago-users-service 600 75       (06)
    Evicted: "Pod ephemeral local storage usage exceeds the total limit of containers 512Mi"
    reemplazo Ready; el trap borra el pod terminado; quedan 2/2 sanos
  $ ./load-requests.sh 300 20                             (07)
    429 x280 | 404 x20 (login con usuario inexistente) en 14 s
  $ timeout -s INT 10..12 sobre cpu, ram y volume (120 s) (08)
    cortan en 11 a 14 s; 0 procesos con la marca, memoria de vuelta a ~68 MiB, archivo borrado
  ```
- **Criterio de "hecho" de §3 (ítem 7):** cumplido en lo que corresponde a C16: requests, CPU, memoria y storage parametrizables, con validación, guardia de contexto y limpieza probada, también ante Ctrl+C. `EXPERIMENTOS.md` es de C18 (bloque B7).
- **Decisiones tomadas:** D43 y D44 actualizadas con lo medido. D53 nueva: cómo se espera a `kubectl exec` para que el trap funcione en Git Bash. Los procesos del experimento llevan una marca (`chaos_cpu`, `chaos_ram`, `chaos_vol`) en su línea de comando, y el trap los busca por `/proc/*/cmdline` (las imágenes no traen `ps`).
- **NO VERIFICADO / riesgos:** `cpu-spike` no se vio en Grafana. Se midió con el cgroup, porque `kubectl top` actualiza con retraso y las métricas de pod por OTLP llegan en B3.
- **Hallazgos nuevos que cambian el plan:**
  - **Memoria por encima del límite:** el plan esperaba "OOMKilled y reinicio". En este cluster (cri-dockerd, `memory.oom.group=0`), el OOM killer mata solo el proceso más grande, que es el del experimento: la app sigue viva y el pod no pierde Ready. Para mostrar el reinicio del contenedor está `measure-mttr.sh --crash` (B1).
  - **Rate limit por réplica:** con 2 réplicas del gateway pasaron 20 logins por minuto, no 10. El contador está en memoria de cada réplica.
  - **Desalojo:** el estado final del pod desalojado varía (`Failed/Evicted` o `Succeeded`), y Kubernetes no lo borra. El script ahora lo borra.
  - **Trap en Git Bash:** con `wait` sobre `kubectl.exe` la señal no se atendía y el trap no corría (se vio en la primera corrida de 08). Corregido con D53.
- **Uso de IA registrado en docs/USO_IA.md:** sí (una fila para el bloque B2)

## C17 — Scripts de caos 2/2: red y desconexión — 2026-11-14 — Martin Roux (bloque B2)
- **Estado:** Hecho
- **Ítem de rúbrica:** 7 (Scripts de caos)
- **Commit:** `C16-C17: scripts de caos de los seis tipos de falla`
- **Archivos creados / modificados** (en `Implementacion K8S/Codigo/chaos-engineering/`): `network-chaos.sh`, `disconnect.sh` y `run-all.sh` (nuevos); `README.md`. `docs/DECISIONES.md` (D43, D44, D53).
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  $ bash -n, argumentos inválidos y calico-node            (01)  OK; calico-node 5/5 Running, uno por nodo
  $ ./network-chaos.sh pharmago-users-service 45  + loop 1 rps a /api/roles   (02)
    policy aplicada en t≈12 s, primer error en t=16 s (000 y 504); al borrarla, 200 (un 504 suelto)
    antes 200 x7 | durante 000 x6, 504 x1, 200 x5 | después 200 x28, 504 x1; kubectl get netpol vacío
  $ ./disconnect.sh pharmago-db 45  + loop 1 rps a /api/drug   (03)
    +4 s primer 500; +6 s pharmacy fuera de Ready; después 503 (circuito pharmacy-cluster open/half-open)
    BD restaurada -> Ready en 45 s (arranque de SQL Server) -> primer 200 8 s después; pharmacy 2/2
  $ ./disconnect.sh pharmago-users-service 30  + loop 1 rps a /api/roles   (04)
    502, 504 y 503 (circuito users-cluster open -> half-open -> closed); users 2/2 Ready 14 s después de restaurar
  $ timeout -s INT 10 sobre network-chaos y disconnect (120 s)   (05)
    netpol borrada (vacío); users restaurado a 2/2 en 12 s
  $ ./run-all.sh --segundos 20                               (06)
    requests, cpu, memoria, storage, red, desconexion: los 6 "OK (exit 0, todo Ready)"
  ```
- **Criterio de "hecho" de §3 (ítem 7):** cumplido junto con C16: los 6 tipos (requests, CPU, memoria, storage, red y desconexión) son parametrizables y tienen limpieza. Falta `chaos-engineering/EXPERIMENTOS.md`, que es de C18 (bloque B7).
- **Decisiones tomadas:** D41 y D42 aplicadas tal cual. `run-all.sh` usa por defecto requests contra login, CPU en el gateway, memoria en pharmacy, storage en users, red en users y desconexión de pharmacy. Entre cada uno espera a que todos los Deployments (incluida la BD) vuelvan a Ready.
- **NO VERIFICADO / riesgos:**
  - En la prueba de red, el circuit breaker no llegó a abrir: a 1 request por segundo, con esperas de 5 a 10 s, nunca se juntan las 8 requests en 10 s que necesita (D13). Con más tráfico sí abriría, como se ve con la desconexión.
  - El prompt pedía el loop a `/api/users`; se usó `/api/roles`, que atiende users y responde sin login (pedido del bloque B2).
- **Hallazgos nuevos que cambian el plan:**
  - Con la NetworkPolicy, los pods de users siguieron Ready: Calico deja pasar el tráfico desde el nodo (probes) y las conexiones ya establecidas (la readiness consulta la BD por una conexión abierta del pool). El corte lo ve el usuario, no Kubernetes. Conviene tenerlo en cuenta en el playbook de red (B7).
  - La caída de la BD deja la app sin servicio unos 96 s: lo que dura la caída más 45 s de arranque de SQL Server. Es el punto único de falla aceptado (D04).
- **Uso de IA registrado en docs/USO_IA.md:** sí (fila del bloque B2)

## C10 — Métricas de aplicación solo por OTLP — 2026-11-14 — Ignacio Aramburu (bloque B3)
- **Estado:** Hecho
- **Ítem de rúbrica:** 4 (Telemetría)
- **Commit:** `C10-C12: métricas por OTLP, trazas con Jaeger y métricas de pod y nodo` (SHA en `git log --grep "^C10-C12:"`)
- **Dónde se corrió:** PC de Ignacio Aramburu, cluster de 5 nodos de C03 (encendido con `minikube start`). Imágenes `6deb22a-dirty`, construidas con `docker build` con el cluster apagado y cargadas con `build-images.sh`. Después `apply-k8s.sh` y `rollout restart` de los 4 Deployments de la app, del Collector y de Prometheus. Sin `minikube tunnel`: el tráfico entró por `port-forward` al gateway.
- **Archivos creados / modificados:** `Backend/PharmaGo.Telemetry/` (nuevo: `.csproj` con OpenTelemetry 1.8.1 y `TelemetryExtensions.AddPharmaGoTelemetry`), `PharmaGo.sln`; gateway, users y pharmacy: `Program.cs`, `.csproj` y `Dockerfile` (línea `COPY` de Telemetry). Se borró `TelemetryExtensions.cs` de las dos Factory y se sacaron todos los `PackageReference OpenTelemetry*` de los servicios y sus Factory. `Instrumentation/MetricsMiddleware.cs` (no mide `/health*` ni `/metrics`). En k8s: los 3 Deployments del backend (`POD_NAME`, `NODE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_RESOURCE_ATTRIBUTES`), `configmaps/otel-collector-config.yaml` (`memory_limiter`, `batch`, `metric_expiration: 2m`, `resource_to_telemetry_conversion`, sin `debug`) y `configmaps/prometheus-config.yaml` (un único job al Collector con `honor_labels`).
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  Confirmado antes de editar: gateway con AddPrometheusExporter y sin OTLP; users y pharmacy con los dos;
  Prometheus scrapeaba otlp-collector, users, pharmacy, gateway, node-exporter y cAdvisor.

  $ dotnet build PharmaGo.sln                        (01)  0 errores, sin NU1605
  $ dotnet test PharmaGo.sln                         (02)  290/291, falla solo Test_GetOneByExpression (igual al baseline)
  $ docker build de gateway, users y pharmacy        (03)  las 3 imágenes 6deb22a-dirty construidas
  $ kubectl exec <pod> -- GET /metrics (3 servicios) (04)  HTTP/1.1 404 Not Found en los 3; /health/live sigue en 200
  $ GET /api/v1/targets                              (05)  un solo target: otlp-collector:8889 up
  $ count by (job, instance) (pharmago_http_requests_total), con tráfico a <=1 rps a las 6 réplicas   (06b)
    PharmaGo.ApiGateway: h9fx4 y tqnr9 | PharmaGo.PharmacyService: fskkt y q4z7f | PharmaGo.UsersService: 6l5wg y bj85m
    una serie por réplica, un job por servicio, con k8s_pod_name y k8s_node_name
  $ count by (endpoint) (pharmago_http_requests_total{endpoint=~"/health.*|/metrics"})   (06b)  vacío
  $ series de los jobs viejos (api-gateway, users-service, node-exporter, kubernetes-cadvisor)   (06b)  vacío
  $ Grafana /api/dashboards/uid/pharmago-overview y /api/ds/query por panel   (07)  provisionado, los 8 paneles con datos
  ```
- **Criterio de "hecho" de §3 (ítem 4, métricas de app):** cumplido. Las métricas de los 3 servicios viajan por OTLP al Collector y Prometheus solo scrapea al Collector.
- **Decisiones tomadas:** ninguna nueva. Se aplicaron D30 y D33. El endpoint OTLP no está en el código: el SDK lo lee de `OTEL_EXPORTER_OTLP_ENDPOINT`.
- **NO VERIFICADO / riesgos:**
  - Captura del dashboard "PharmaGo - Overview": no la pude sacar porque Grafana pide login y el navegador headless no lo puede completar. Se verificó por API que los 8 paneles devuelven datos (07). La captura queda para la revisión del integrante.
  - No se probó por el Ingress, porque no había `minikube tunnel` abierto. El tráfico entró por `port-forward` al Service del gateway.
- **Hallazgos nuevos que cambian el plan:**
  - En la primera consulta (06a) aparecieron series con `job="otlp-collector"`, incluso de `/health`. Eran datos anteriores al cambio, guardados en el volumen de Prometheus, y se fueron a los 5 minutos (06b).
  - `kubectl port-forward svc/...` se ata a un solo pod. Para ver las dos réplicas hubo que mandar tráfico directo a cada pod.
  - **Para B6 (alertas):** en el Overview, `sum by (endpoint)` suma la misma request dos veces, una en el gateway y otra en el servicio, porque los dos registran `/api/drug`. Para las señales de cara al usuario conviene filtrar `job="PharmaGo.ApiGateway"`.
- **Uso de IA registrado en docs/USO_IA.md:** sí (una fila para el bloque B3)

## C11 — Trazas distribuidas con OTLP y Jaeger — 2026-11-14 — Ignacio Aramburu (bloque B3)
- **Estado:** Hecho
- **Ítem de rúbrica:** 4 (Telemetría)
- **Commit:** `C10-C12: métricas por OTLP, trazas con Jaeger y métricas de pod y nodo`
- **Archivos creados / modificados:** `PharmaGo.Telemetry` (paquete `OpenTelemetry.Instrumentation.SqlClient` 1.8.0-beta.1 y `WithTracing`: ASP.NET Core con filtro de `/health` y `/metrics`, HttpClient, SqlClient con `SetDbStatementForText` y `RecordException`, y exportador OTLP); `k8s/deployments/ops/jaeger-deployment.yaml` y `k8s/services/ops/jaeger-service.yaml` (nuevos); `configmaps/otel-collector-config.yaml` (exporter `otlp/jaeger` y pipeline `traces`); `apply-k8s.sh`, `port-forward.sh` (puerto 16686), `README-k8s.md`; `docs/trazas.md` (nuevo).
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  $ dotnet build PharmaGo.sln                         (01)  0 errores
  $ docker build de los 3 servicios                   (02)  OK
  $ login (POST /api/login) y GET /api/drug por el gateway, a <=1 rps durante 3 min: 162 x drug 200, 18 x login 200
  $ GET /api/traces/<id> (Jaeger)                     (03)
    login c69bd6bc...: [ApiGateway] POST /api/login/{**catch-all}
                       -> [ApiGateway] POST (HttpClient, url.full=http://pharmago-users-service/api/login)
                       -> [UsersService] POST api/Login
                       -> 2 x [UsersService] PharmaDb (db.statement=SELECT TOP(1) ... / ... FROM [Sessions] ...)
    drug  7d817e59...: [ApiGateway] GET /api/drug -> [ApiGateway] GET -> [PharmacyService] GET api/Drug -> [PharmacyService] PharmaDb
    todos los spans con el mismo traceID
  $ operaciones y últimas 500 trazas de cada servicio  (04)  0 spans de /health o /metrics (probes activos, pods 1/1)
  capturas de la UI de Jaeger                         (05, 06)  traza de login con 5 spans en 2 servicios; búsqueda con 20 trazas
  ```
- **Criterio de "hecho" de §3 (ítem 4, trazas):** cumplido. Las trazas van del gateway al servicio y a SQL, por OTLP, y se ven en Jaeger. La propagación de contexto es W3C `traceparent` a través de YARP.
- **Decisiones tomadas:** ninguna nueva. Se aplicó D34. `ResilientForwarderHttpClientFactory` (C07) llama a `base.WrapHandler`, así que conserva el `ActivityPropagationHandler` de YARP que inyecta `traceparent`. No hizo falta tocar el gateway.
- **NO VERIFICADO / riesgos:** Jaeger guarda en memoria hasta 5000 trazas; si el pod se reinicia, se pierden. Alcanza para la defensa (D34).
- **Hallazgos nuevos que cambian el plan:** la instrumentación HttpClient sí genera el span de cliente en el gateway, aunque YARP usa `SocketsHttpHandler` directo. Por eso cada request tiene 4 spans, no 3.
- **Uso de IA registrado en docs/USO_IA.md:** sí (una fila para el bloque B3)

## C12 — Métricas de pod, contenedor y nodo por OTLP — 2026-11-14 — Ignacio Aramburu (bloque B3)
- **Estado:** Hecho
- **Ítem de rúbrica:** 4 (Telemetría)
- **Commit:** `C10-C12: métricas por OTLP, trazas con Jaeger y métricas de pod y nodo`
- **Archivos creados / modificados:** `k8s/deployments/ops/otel-agent-daemonset.yaml`, `otel-agent-rbac.yaml`, `otel-collector-rbac.yaml` y `k8s/configmaps/otel-agent-config.yaml` (nuevos); `otel-collector-deployment.yaml` (`serviceAccountName`); `configmaps/otel-collector-config.yaml` (receiver `k8s_cluster`). Se borraron el DaemonSet y el Service de node-exporter, y el ClusterRole y el Binding de Prometheus. `apply-k8s.sh` (aplica lo nuevo y borra los restos de node-exporter y `prometheus-cadvisor` en un cluster ya creado), `cleanup.sh` (borra el RBAC de alcance cluster), `configmaps/grafana-dashboard-infra.yaml` (reescrito), `README-k8s.md`, `docs/metricas.md` (nuevo), `docs/diagrama-despliegue.md` y `docs/DECISIONES.md` (D37, D38, D39).
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  $ kubectl get ds -n pharmago                         (01)  otel-agent 5/5 Ready, un pod por nodo; node-exporter y prometheus-cadvisor: NotFound
  $ count by (k8s_node_name) de CPU, memoria, filesystem y red de nodo   (02)  5 nodos en las 4
  $ valores por nodo                                   (02)
    CPU (núcleos): minikube 0,59 | m02 0,41 | m03 0,32 | m04 0,35 | m05 0,83          -> distinguen
    memoria working set (GB): 1,86 | 0,86 | 0,86 | 0,88 | 3,90                        -> distinguen
    red rx (B/s): 6978 | 5065 | 1563 | 3102 | 29079                                   -> distinguen
    filesystem: capacidad 1,08 TB en los 5, uso 37,94 GB en los 5                     -> NO distinguen (disco del host)
  $ GET /api/v1/targets                                (03)  sigue habiendo un solo target: otlp-collector:8889
  $ las 18 queries del dashboard Infra contra Prometheus   (04)  todas devuelven series
  $ kubectl get --raw /api/v1/nodes/minikube-m04/proxy/stats/summary   (05)  los pods no traen network; contenedores solo workingSetBytes
  $ kubectl top pods (otel-agent)                      (06)  con 128Mi/200m: 127Mi y 200m (al límite); con 256Mi/250m: 107-175Mi y 3-4m, 0 reinicios
  $ Grafana /api/dashboards/uid/pharmago-infra y /api/ds/query   (07)  provisionado, los 14 paneles de datos con series
  captura de Grafana, sacada por el integrante          (08)  CPU y memoria por nodo: 5 series; m05 ~3,6 GiB, minikube ~1,7 GiB, m02 a m04 ~0,8 GiB;
                                                              a las 13:04 la CPU de m02 a m04 baja de ~0,3 a ~0,13 núcleos al aplicar D38
  docs/evidencia/C12/nombres-metricas.txt: nombres reales y labels de cada métrica, para B6
  ```
- **Criterio de "hecho" de §3 (ítem 4, métricas de pod, contenedor y nodo):** cumplido. CPU, memoria, storage y red de nodo y de pod/contenedor llegan por OTLP al Collector y de ahí a Prometheus, con una serie por nodo en Grafana. Las excepciones por limitación del cluster están en D39 y `docs/metricas.md`.
- **Decisiones tomadas:** D37 (endpoint del kubelet por IP del nodo y RBAC), D38 (límites de `otel-agent` mayores que los del plan, con evidencia) y D39 (cómo se cubren las métricas que el kubelet no da).
- **NO VERIFICADO / riesgos:**
  - El Collector central usa 165 a 182 Mi de sus 256 Mi. `memory_limiter` no rechazó datos (no hay "Refusing data" en los logs), pero conviene mirarlo durante los experimentos de caos (B7).
- **Hallazgos nuevos que cambian el plan:**
  - Con cri-dockerd no hay red por pod ni memoria detallada por contenedor. La red se mira por nodo, y como cada microservicio tiene su nodo, equivale a la red del microservicio (D39).
  - `k8s_*_cpu_utilization_ratio` mide núcleos, no porcentaje. Las alertas de B6 tienen que usar `k8s_*_cpu_limit_utilization_ratio` si quieren un porcentaje.
  - `k8s_container_restarts` es un gauge acumulado: para alertar, usar `increase()` o `delta()`.
- **Uso de IA registrado en docs/USO_IA.md:** sí (una fila para el bloque B3)

## C19 — Plan de contención de incidentes — 2026-11-14 — Ignacio Aramburu (bloque B4)
- **Estado:** Hecho
- **Ítem de rúbrica:** 6 (Plan de incidentes)
- **Commit:** `C19: plan de contención de incidentes, roles y plantillas` (SHA en `git log --grep "^C19:"`)
- **Archivos creados / modificados:** `docs/plan-incidentes.md`, `docs/plantillas/registro-incidente.md`, `docs/plantillas/postmortem.md` y `docs/incidentes/ejemplo-postmortem.md` (nuevos).
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  $ python docs/evidencia/C19/check_c19.py .        (01)
    archivos y scripts nombrados en los 4 documentos, paneles de Grafana contra los dashboards provisionados,
    decisiones Dxx, alertas pg-* contra el plan de C13 y playbooks contra el plan de C20
    Resumen: 56 OK, 32 PENDIENTE (B6/B7), 0 FALTA  -> exit=0
  $ comandos de solo lectura del plan contra el cluster   (02)
    kubectl get deploy/nodes/networkpolicy/events, grep circuit_breaker en el gateway,
    índices pharmago-logs-* en Elasticsearch, minikube node start, kubectl rollout restart: todos responden
  ```
- **Criterio de "hecho" de §3 (ítem 6):** cumplido en lo que corresponde a C19: plan con severidades medibles, roles, war room, comunicación y riesgos, más las plantillas de registro y postmortem blameless. Los playbooks por tipo de falla son de C20 (bloque B7).
- **Decisiones tomadas:** ninguna técnica nueva. Se citan D45 y D46 en el plan y en las plantillas. Roles para la defensa, asignados por sorteo (`random.SystemRandom`) a pedido del integrante: IC Martin Roux, Ops Ignacio Aramburu, Comms Franco (francokbd).
- **NO VERIFICADO / riesgos:**
  - Las 10 alertas `pg-*` (B6), los 8 playbooks, `steady-state.sh` y `EXPERIMENTOS.md` (B7) todavía no existen. El plan los nombra por el uid y el nombre del plan, y el chequeo (01) confirma que coinciden con los prompts de C13 y C20. B7 tiene que verificar que el plan nombre las alertas y paneles reales.
  - El plan no se ensayó con un experimento en vivo: eso es de C20 (seguir un playbook durante un experimento) y de C23 (ensayo de la defensa).
- **Hallazgos nuevos que cambian el plan:**
  - Todavía no existe `chaos-engineering/EXPERIMENTOS.md`. El postmortem de ejemplo usa un experimento real ya medido: `disconnect.sh pharmago-db 45`, de `docs/evidencia/C17/03-disconnect-db.txt`. Las 64 requests entre 04:48:44 y 04:50:18 fallaron (6 × 500, 4 × 502, 54 × 503) y la recuperación fue automática, 8 s después de que la BD volvió a Ready. Las acciones del postmortem quedan asignadas a B6, B7 y B8.
  - El postmortem deja una lección operativa para la defensa: si se cae la BD, restaurarla y esperar unos 50 s, sin reiniciar los microservicios.
- **Uso de IA registrado en docs/USO_IA.md:** sí

## C13 — Alertas de Grafana como código — 2026-11-14 — Martin Roux (bloque B6)
- **Estado:** Hecho
- **Ítem de rúbrica:** 4 (Telemetría: al menos 5 alertas en Grafana)
- **Commit:** `C13-C14: alertas de Grafana como código y logs JSON con trace_id en Kibana` (SHA en `git log --grep "^C13-C14:"`)
- **Dónde se corrió:** PC de Martin, cluster de 5 nodos con B1 y B3 aplicados (imágenes `1c649b8-dirty`), `minikube tunnel` abierto. El trabajo se cortó a la mitad por un corte de luz y se retomó después; no se perdió nada.
- **Archivos creados / modificados:** `k8s/configmaps/grafana-alerting.yaml` (nuevo, 10 reglas), `k8s/deployments/ops/grafana-deployment.yaml` (montaje en `/etc/grafana/provisioning/alerting/alerts.yaml`), `k8s/apply-k8s.sh`, `k8s/README-k8s.md`, `docs/alertas.md` (nuevo), `docs/DECISIONES.md` (D54).
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  Confirmado antes de editar: Grafana sin alertas provisionadas; datasource uid "prometheus"; nombres de métricas
  de docs/evidencia/C12/nombres-metricas.txt; los uid pg-* que nombra docs/plan-incidentes.md (B4).

  $ GET /api/v1/provisioning/alert-rules                      (01)
    10 reglas, carpeta PharmaGo, grupo pharmago, provenance=file:
    pg-5xx, pg-latency, pg-latency-anomaly, pg-429, pg-cpu, pg-memory, pg-storage, pg-restarts, pg-replicas, pg-breaker
  $ cada expr contra GET /api/v1/query de Prometheus          (02)
    las 10 con status=success (ninguna con error ni nombre inexistente); pg-latency-anomaly y pg-breaker vacías
    (condición no cumplida); P95 del gateway 612 ms; 5xx 0; 429 0
  $ GET /api/prometheus/grafana/api/v1/rules (sistema sano)   (03)  las 10 en Normal
  $ ./load-requests.sh 300 20  (429 x280)                     (04)
    pg-429: Pending a los 21 s, Firing a los 57 s (30 s de ventana)
  $ bash verify/test-circuit-breaker.sh                       (05)
    pg-breaker: Firing a los 32 s para cluster=users-cluster, mientras el gateway respondía 503 circuit_open
  ```
- **Criterio de "hecho" de §3 (ítem 4, alertas):** cumplido: 10 alertas de Grafana (la letra pide al menos 5) provisionadas como código, con query, umbral y ventana documentados en `docs/alertas.md`, y dos forzadas hasta Firing en el cluster.
- **Decisiones tomadas:** D54 (piso de 50 ms en el k-sigma y filtro `job="PharmaGo.ApiGateway"`). Cada regla tiene `severity` alineada con el plan de incidentes y `runbook` con el playbook que nombra el plan.
- **NO VERIFICADO / riesgos:**
  - Captura de la pantalla de alertas: no se sacó (no hay forma de guardar la imagen desde la sesión de la IA). Queda para la revisión del integrante, que igual tiene que mirar Grafana, Alerting.
  - Solo se forzaron `pg-429` y `pg-breaker`, como pide el plan. El resto se valida con los experimentos de B7.
- **Hallazgos nuevos que cambian el plan:**
  - Para forzar `pg-429` el plan proponía 120 requests en un minuto, pero el rate limit es por réplica del gateway (2 réplicas: 200 por minuto). Se usó una ráfaga a login (10 por minuto por réplica), con `load-requests.sh 300 20`.
  - `pg-replicas` no dispara con `disconnect.sh`, porque ese script escala a 0 (las deseadas también bajan). Esa falla la cubren `pg-5xx` y `pg-breaker`. Está en `docs/alertas.md`, y B7 lo tiene que tener en cuenta en los playbooks.
- **Uso de IA registrado en docs/USO_IA.md:** sí (una fila para el bloque B6)

## C14 — Logs JSON con trace_id y consulta en Kibana — 2026-11-14 — Martin Roux (bloque B6)
- **Estado:** Hecho
- **Ítem de rúbrica:** 4 (Telemetría: logs JSON consultables en Kibana)
- **Commit:** `C13-C14: alertas de Grafana como código y logs JSON con trace_id en Kibana`
- **Archivos creados / modificados:** `Backend/PharmaGo.ApiGateway/appsettings.json` (formatter JSON, igual que users), `Backend/Instrumentation/CustomMetrics.cs` (sin el `Console.WriteLine`), `Backend/Instrumentation/CorrelationIdMiddlewareExtensions.cs` (`trace_id` y `span_id` de `Activity.Current` en el scope de gateway y servicios), `Backend/PharmaGo.UsersService.Factory/ServiceFactory.cs` (el log de `MigrateDatabase` pasa de `Console.WriteLine` a `ILogger`), `Frontend/nginx.conf` (`log_format json_combined`), `k8s/setup-kibana.sh` (nuevo), `k8s/README-k8s.md`, `docs/logs.md` (nuevo).
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  Confirmado antes de editar: gateway sin formatter JSON (users y pharmacy sí), Console.WriteLine en
  CustomMetrics.LoginInvocations, scope sin trace_id, nginx con el formato por defecto.

  $ dotnet build PharmaGo.sln -c Release                      (01)  0 errores
  $ dotnet test ... --no-build                                 (01)  290/291 (falla Test_GetOneByExpression, como el baseline)
  $ docker build de gateway, users, pharmacy y ui              (01)  las 4 OK
  $ ./setup-kibana.sh  (dos veces)                             (02)  "Data view pharmago-logs-* creado." / "ya existe."
  $ kubectl logs de cada pod, línea por línea con json.loads  (03)
    gateway 298/298 JSON (291 con trace_id) x2 pods | users 5/5 x2 | pharmacy 8/8 y 5/5 |
    ui 669/696 y 683/710: las 27 no-JSON son el arranque del contenedor nginx (docker-entrypoint y avisos de inicio)
  $ _cat/indices/pharmago-logs-*  (2 lecturas)                 (04)  285248 -> 285583 documentos
  $ kubectl logs fluent-bit (5 pods)                           (04)  0 mapper_parsing_exception; 0 [error] en los últimos 10 min
  $ login -> trace de Jaeger -> búsqueda en Elasticsearch      (05)
    traceID 73017f723564cc0f899fc13c59640619: 5 spans (gateway y users, 2 de SQL)
    Scopes.trace_id en ES -> 3 documentos de 2 servicios: gateway "Proxying to .../api/login",
    users "Login succeeded ... correlation_id=b0abffeb-...", gateway "Received HTTP/1.1 response 200."
  ```
- **Criterio de "hecho" de §3 (ítem 4, logs):** cumplido: logs JSON con `trace_id` y `span_id` en los 3 servicios .NET, la UI también en JSON, y los logs consultables en Kibana (data view creado por script). Se probó que se puede ir de una traza de Jaeger a sus logs.
- **Decisiones tomadas:** ninguna nueva. El scope del gateway usa el mismo diccionario que el de los servicios (`correlation_id`, `trace_id`, `span_id`).
- **NO VERIFICADO / riesgos:**
  - Captura de Kibana con la búsqueda: no se sacó desde la sesión de la IA. Queda para la revisión del integrante (la consulta lista está en `docs/logs.md` y en la evidencia 05).
  - Las 27 líneas de arranque del contenedor nginx siguen en texto: las escribe el entrypoint de la imagen antes de que nginx lea la configuración.
- **Hallazgos nuevos que cambian el plan:**
  - El `Console.WriteLine` de `MigrateDatabase` (agregado en C05) rompía el "todo JSON" de users. Se pasó a `ILogger`.
  - Los logs de error de YARP tienen las claves `Message` y `message` en `State`. Son JSON válido (Python y Elasticsearch los aceptan), pero `ConvertFrom-Json` de PowerShell los rechaza. Para validar se usó Python.
  - Después del corte de luz, Fluent Bit tuvo errores de conexión mientras Elasticsearch arrancaba; los reintentos (`Retry_Limit False`) evitaron perder datos.
- **Uso de IA registrado en docs/USO_IA.md:** sí (fila del bloque B6)

## C21 — Pipeline CI/CD en GitHub Actions — 2026-11-14 — francokbd (bloque B5)
- **Estado:** 🟡 Parcial. Workflow y corrección del test hechos y verificados en local; la corrida real en GitHub queda pendiente hasta el push.
- **Ítem de rúbrica:** Transversal ("Tableros, repositorios y pipelines CI/CD: GitHub")
- **Commit:** `C21-C22: pipeline CI/CD en GitHub Actions y pruebas BDD con Cypress y Cucumber` (SHA en `git log --grep "^C21-C22:"`)
- **Archivos creados / modificados:** `.github/workflows/ci.yml` (nuevo), `docs/ci-cd.md` (nuevo), `Backend/PharnaGo.Test/DataAccess.Test/PurchasesDetailRepositoryTest.cs`
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  $ dotnet build PharmaGo.sln -c Release                 -> 0 Error(s)
  $ dotnet test PharnaGo.Test/PharmaGo.Test.csproj        -> Passed! 291 de 291 (antes 290)
  $ ci.yml con PyYAML (02-workflow.txt)
    disparadores: push a team/obligatorio y main, pull_request a main
    jobs: backend, frontend, manifests, bdd-smoke (needs frontend), images (needs los otros cuatro)
    todas las actions fijadas en versión mayor; rutas de Dockerfiles, solución, tests y k8s comprobadas
  ```
- **Criterio de "hecho":** cumplido en local. Falta ver el pipeline en verde en GitHub Actions.
- **Decisiones tomadas:** D47 aplicada: el pipeline construye y valida, y el despliegue es local con `deploy.sh`. Actions en su última versión mayor, publicada hace meses: checkout v7, setup-dotnet v6, setup-node v7, upload-artifact v7, download-artifact v8, docker/login-action v4, cypress-io/github-action v7. kubeconform v0.8.0. El build del frontend se pasa como artefacto al job de BDD, para no compilar dos veces. `images` también espera a `bdd-smoke`: no se publica una imagen si el login está roto. Las imágenes se publican en `ghcr.io` solo en push a `main`.
- **NO VERIFICADO / riesgos:** la corrida real en GitHub Actions. En Linux las rutas distinguen mayúsculas: si algún `ProjectReference` del monolito o de los tests tiene una diferencia de mayúsculas, el job `backend` lo va a mostrar (las imágenes de los 3 servicios ya se construyen en Linux sin problema). kubeconform no se corrió en local: se valida en el pipeline.
- **Hallazgos nuevos que cambian el plan:** ninguno.
- **Uso de IA registrado en docs/USO_IA.md:** sí (una fila para el bloque B5)

## C22 — Pruebas BDD con Cypress y Cucumber — 2026-11-14 — francokbd (bloque B5)
- **Estado:** 🟡 Parcial. Escenarios `@smoke` en verde en local; los `@e2e` quedan pendientes porque esta PC no tiene cluster.
- **Ítem de rúbrica:** Transversal ("BDD: Cypress + Cucumber")
- **Commit:** `C21-C22: pipeline CI/CD en GitHub Actions y pruebas BDD con Cypress y Cucumber`
- **Archivos creados / modificados:** `Implementacion K8S/Codigo/e2e/` (nuevo: `package.json`, `package-lock.json`, `cypress.config.js`, `cypress/e2e/login.feature`, `cypress/e2e/salud.feature`, `cypress/support/step_definitions/pasos.js`), job `bdd-smoke` en `.github/workflows/ci.yml`, `docs/bdd.md` (nuevo), `.gitignore` (`**/e2e/app/`)
- **Evidencia (comandos ejecutados y salida resumida):**
  ```
  $ npm install (e2e)        -> 462 paquetes; npx cypress verify -> Verified Cypress 13.17.0
  $ npx ng build             -> build de producción del frontend actual, copiado a e2e/app
  $ npx serve -s app -l 4200 && CYPRESS_BASE_URL=http://localhost:4200 npm run test:smoke   (01-smoke-local.txt)
    Specs: 1 found (login.feature)      <- el filtro @smoke deja afuera salud.feature
    √ Un administrador con credenciales válidas entra a su página
    √ Con credenciales inválidas sigo en el login y veo el error
    2 passing
  ```
- **Criterio de "hecho":** cumplido para `@smoke`. `@e2e` está NO VERIFICADO.
- **Decisiones tomadas:** D49 aplicada con las versiones exactas. La contraseña del escenario real sale de `CYPRESS_E2E_PASSWORD` y se escribe con `log: false`. Los escenarios `@smoke` simulan también los GET de la app (`**/api/**`), para que la página de destino no dependa de un backend.
- **NO VERIFICADO / riesgos:** `npm run test:e2e` contra el cluster. Comandos en `docs/evidencia/C22/cluster-pendiente.txt`. El job `bdd-smoke` en GitHub Actions se ve después del push.
- **Hallazgos nuevos que cambian el plan:** las pruebas encontraron un bug de la app: con credenciales inválidas, `LoginComponent` lanza un `TypeError` al leer `login.userName` de un resultado vacío. No se corrigió, porque es código de negocio; los pasos ignoran solo ese error y está documentado en `docs/bdd.md`. Además, en esta PC Electron necesitó `--no-sandbox --disable-gpu` por el entorno restringido de la sesión de IA; en GitHub Actions no hace falta.
- **Uso de IA registrado en docs/USO_IA.md:** sí (fila del bloque B5)
