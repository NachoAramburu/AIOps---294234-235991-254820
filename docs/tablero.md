# Tablero del equipo

**URL del Project:** PENDIENTE. Franco crea en GitHub un Project tipo Board llamado `PharmaGo AIOps` y reemplaza este texto por su URL.

**Columnas:** Por hacer, En curso, Hecho.

| Rol | Integrante |
|---|---|
| A | Franco |
| B | Martin |
| C | Nacho |

## Tarjetas para cargar en el tablero

El 13/11 los 17 commits que faltaban se agruparon en 9 bloques, 3 por integrante. Cada bloque es un commit; su mensaje empieza con las tareas que incluye (por ejemplo `C07-C09:`).

**Hecho:**

- C01 · Base de trabajo del equipo · Franco
- C02 · Cluster multinodo y prueba de memoria · Martin
- C15 · Detección de anomalías · Nacho
- C04 · Acceso estable por Ingress y rutas del gateway · Franco
- C04-verificación · Evidencia de C04 en el cluster · Martin
- C05 · Endpoints de salud y resiliencia de la base · Martin
- C03 · Separación de microservicios por nodo y diagrama · Nacho
- C06 · Réplicas, probes rápidas y secretos · Nacho

**Bloques:**

| Bloque | Responsable | Tareas | Qué resuelve | Antes | Cuándo |
|---|---|---|---|---|---|
| B1 | Franco | C07, C08, C09 | Circuit breaker en el gateway, despliegue sin caídas y su prueba | Nada | vie 13/11 |
| B2 | Martin | C16, C17 | Scripts de caos de los 6 tipos de falla | Nada | vie 13/11 |
| B3 | Nacho | C10, C11, C12 | Métricas por OTLP, trazas con Jaeger y métricas de pod y nodo | B1 | sáb 14/11 |
| B4 | Nacho | C19 | Plan de contención de incidentes | Nada | sáb 14/11 |
| B5 | Franco | C21, C22 | Pipeline CI/CD y pruebas BDD | B3 | sáb 14 o dom 15/11 |
| B6 | Martin | C13, C14 | Alertas de Grafana y logs JSON en Kibana | B1, B3 | sáb 14 o dom 15/11 |
| B7 | Nacho | C18, C20 | Experimentos de caos y playbooks | B2, B6 | dom 15/11 |
| B8 | Martin | C23 | Runbook de la defensa y ensayo con los 3 | B7 | dom 15 o lun 16/11 |
| B9 | Franco | C24 | Informe, matriz de cumplimiento y zip | B5, B8 | lun 16/11 |
