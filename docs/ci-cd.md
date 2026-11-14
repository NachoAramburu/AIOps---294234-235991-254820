# Pipeline CI/CD (C21 y C22)

La letra pide "Tableros, repositorios y pipelines CI/CD: GitHub" y pruebas BDD con Cypress y Cucumber. El pipeline está en `.github/workflows/ci.yml` y corre en GitHub Actions.

## Cuándo corre

- En cada push a `team/obligatorio` o a `main`.
- En cada Pull Request hacia `main`.

## Qué hace cada job

| Job | Qué hace | Si falla, significa que… |
|---|---|---|
| `backend` | Instala .NET 6, compila la solución y corre los 291 tests de `PharmaGo.Test` | Algún cambio rompió la compilación o un test |
| `frontend` | Con Node 16, igual que el Dockerfile, instala dependencias y hace el build de producción de Angular. Guarda el build como artefacto | El frontend no compila |
| `manifests` | Valida todos los YAML de `k8s/` con kubeconform contra los esquemas de Kubernetes | Hay un manifiesto mal formado o con un campo inválido |
| `bdd-smoke` | Toma el build del frontend, lo sirve y corre los escenarios BDD `@smoke` con Cypress y Cucumber. La API está simulada, así que no necesita cluster | La pantalla de login dejó de funcionar como describe `docs/bdd.md` |
| `images` | Corre solo si pasaron los cuatro anteriores. Construye las 4 imágenes con el tag del SHA corto del commit. En un push a `main`, además las publica en `ghcr.io/<dueño del repo>/` | Algún Dockerfile no construye |

El orden protege lo importante: no se construye ni publica ninguna imagen si fallan los tests, el build, los manifiestos o las pruebas BDD.

## Por qué el despliegue es local (decisión D47)

El pipeline construye y valida, pero no despliega. El cluster es Minikube y corre en la PC de cada integrante: el runner de GitHub no tiene forma de llegar a él. El despliegue se hace con los scripts de `k8s/`:

```bash
./build-images.sh      # construye las imágenes con el tag del commit actual
./deploy.sh <tag>      # RollingUpdate sin caídas (docs/despliegue-seguro.md)
./rollback.sh          # vuelve a la versión anterior
```

## Cómo se relacionan los tags

El pipeline y `build-images.sh` usan el mismo criterio: los primeros 7 caracteres del SHA del commit. Una imagen construida en el pipeline para el commit `be11702` se llama `pharmago-api-gateway:be11702`, igual que la que construye `build-images.sh` en una PC con ese commit. `build-images.sh` agrega `-dirty` si hay cambios sin commitear, para no confundir una imagen de trabajo con una versión real.

Si en algún momento git necesita más de 7 caracteres para identificar un commit, `git rev-parse --short` devuelve más y los tags dejan de coincidir. En un repo de este tamaño no pasa.

## Ver el resultado

En GitHub, pestaña **Actions** del repo: cada push muestra los 5 jobs con su estado. En un Pull Request a `main`, el resultado aparece al pie del PR.
