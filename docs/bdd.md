# Pruebas BDD con Cypress y Cucumber (C22)

La letra nombra "BDD: Cypress + Cucumber". Las pruebas están en `Implementacion K8S/Codigo/e2e/`, con su propio `package.json` para no mezclar dependencias con Angular 14.

## Cómo está armado

- **Cucumber** lee los escenarios escritos en español en archivos `.feature` (`Dado`, `Cuando`, `Entonces`).
- Cada frase se conecta con un paso en código en `cypress/support/step_definitions/pasos.js`.
- **Cypress** ejecuta esos pasos en un navegador real contra la app.
- El preprocesador `@badeball/cypress-cucumber-preprocessor` filtra por tags: `@smoke` o `@e2e`.

## Escenarios

| Feature | Tag | Escenario | Qué comprueba | Necesita cluster |
|---|---|---|---|---|
| `login.feature` | `@smoke` | Un administrador con credenciales válidas entra a su página | El formulario manda el login, la app guarda la sesión y el guard de rutas deja entrar a `/admin` | No: la API está simulada |
| `login.feature` | `@smoke` | Con credenciales inválidas sigo en el login y veo el error | Ante un rechazo, la app se queda en `/login` y muestra el aviso "Login failed" | No |
| `salud.feature` | `@e2e` | La API de medicamentos responde | `GET /api/drug` por el Ingress devuelve 200 | Sí |
| `salud.feature` | `@e2e` | El administrador del seed inicia sesión de verdad | Login real contra users-service y la base, hasta `/admin` | Sí |

**`@smoke`** prueba la pantalla con la API simulada (`cy.intercept`), así que corre en el pipeline sin cluster. Si alguien rompe el login del frontend, el pipeline lo detecta.

**`@e2e`** va contra la app desplegada. Sirve para confirmar que el sistema quedó sano después de un despliegue o de un experimento de caos.

## Cómo correrlas

Una vez, dentro de `Implementacion K8S/Codigo/e2e`:

```bash
npm ci
```

**`@smoke` contra un build local del frontend:**

```bash
cd "Implementacion K8S/Codigo/Frontend" && npm install && npm run build
cp -r dist/pharma-go ../e2e/app
cd ../e2e
npx serve -s app -l 4200            # dejar corriendo en otra terminal
CYPRESS_BASE_URL=http://localhost:4200 npm run test:smoke
```

**`@e2e` contra el cluster**, con `minikube tunnel` abierto:

```bash
CYPRESS_BASE_URL=http://127.0.0.1 CYPRESS_E2E_PASSWORD='<contraseña del admin de seed-data.sql>' npm run test:e2e
```

La contraseña se pasa por variable de entorno y Cypress no la muestra en el log. Nunca va en el código. El login tiene un rate limit de 10 por minuto por réplica del gateway.

En el pipeline, el job `bdd-smoke` hace lo mismo que `@smoke`: toma el build del job `frontend`, lo sirve y corre los escenarios (ver `docs/ci-cd.md`).

## Un bug de la app que encontraron las pruebas

Con credenciales inválidas, `login.service` devuelve un resultado vacío y `LoginComponent` igual intenta leer `login.userName`. Eso lanza un `TypeError` en el navegador. Para el usuario la pantalla se comporta bien: muestra el aviso y se queda en el login. Pero Cypress considera fallido cualquier error no capturado de la app.

Corregirlo sería tocar código de negocio, que este obligatorio no modifica. Por eso los pasos ignoran **solo** ese error puntual (`reading 'userName'`) y el escenario sigue verificando lo que ve el usuario. Cualquier otro error de la app hace fallar la prueba.

## Si Cypress no arranca en Windows

En entornos restringidos, Electron (el navegador que trae Cypress) puede fallar con "GPU process isn't usable" o "Renderer process crashed". Se resuelve agregando, solo en esa PC:

```bash
ELECTRON_EXTRA_LAUNCH_ARGS="--no-sandbox --disable-gpu --disable-software-rasterizer --in-process-gpu" npm run test:smoke
```

En GitHub Actions no hace falta.
