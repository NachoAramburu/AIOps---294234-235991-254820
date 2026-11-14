# Despliegue de PharmaGo en Kubernetes (Minikube)

Esta guía describe cómo desplegar la aplicación PharmaGo en un cluster Minikube **multinodo (5 nodos)**.

## Inicio rápido (desde cero)

Desde **Git Bash**, con Docker Desktop corriendo. Los scripts se pueden correr desde cualquier directorio:

```bash
cd "Implementacion K8S/Codigo/k8s"
./cluster-up.sh      # crea/arranca el cluster de 5 nodos, metrics-server y etiquetas node-type
./build-images.sh    # construye las imágenes y las carga en todos los nodos
./apply-k8s.sh       # aplica namespace, secrets, configmaps, volúmenes y deployments
./seed-db.sh         # carga Backend/seed-data.sql (roles y usuarios de prueba)
```

`seed-db.sh` es imprescindible: sin él no hay roles ni usuarios y no se puede iniciar sesión. Se puede correr más de una vez.

Después, para entrar a la app, abrí **PowerShell como administrador**, corré `minikube tunnel` y **dejá esa ventana abierta**. La app queda en http://127.0.0.1/ (ver [Acceso a los Servicios](#acceso-a-los-servicios)).

## Arquitectura

Cada nodo tiene una etiqueta `node-type` y cada Deployment usa `nodeAffinity` sobre esa etiqueta:

| Nodo Minikube | `node-type` | Corre |
|---|---|---|
| `minikube` (control-plane) | `frontend` | `pharmago-ui` |
| `minikube-m02` | `gateway` | `pharmago-api-gateway` |
| `minikube-m03` | `users` | `pharmago-users-service` |
| `minikube-m04` | `pharmacy` | `pharmago-pharmacy-service` |
| `minikube-m05` | `ops` | `pharmago-db` (SQL Server Express), otlp-collector, prometheus, grafana, elasticsearch, kibana |

Los DaemonSets (fluent-bit, node-exporter) corren en todos los nodos.

**Requisito de memoria**: cada nodo tiene 4 GB (`--memory 4096`), es decir hasta 20 GB en total; en la práctica el cluster usa bastante menos (ver `docs/evidencia/C02/`). En Windows, Docker Desktop (WSL2) tiene que tener la memoria necesaria en `%UserProfile%\.wslconfig`.

## Prerrequisitos

1. **Minikube** (referencia v1.39.0) y **kubectl**
2. **Docker Desktop** con backend WSL2 (para el driver y para construir las imágenes)
3. **Git Bash** en Windows: los scripts son solo bash (los `.ps1` se eliminaron, decisión D06)

## Configuración Inicial

### 1. Crear el cluster multinodo

```bash
./cluster-up.sh
```

Es idempotente. Si el cluster no existe lo crea con:

```bash
minikube start --driver=docker --container-runtime=docker --cni=calico \
  --kubernetes-version=v1.33.13 --nodes 5 --cpus 2 --memory 4096
```

- `--container-runtime=docker`: Fluent Bit usa el parser `docker` para los logs.
- `--cni=calico`: hace cumplir las `NetworkPolicy` (caos de red).
- Si hay pods `Pending` por memoria: `minikube delete` y `MINIKUBE_MEMORY=4608 ./cluster-up.sh`.

Después habilita `metrics-server` (para `kubectl top`) y etiqueta los nodos:

```bash
kubectl label node minikube     node-type=frontend --overwrite
kubectl label node minikube-m02 node-type=gateway  --overwrite
kubectl label node minikube-m03 node-type=users    --overwrite
kubectl label node minikube-m04 node-type=pharmacy --overwrite
kubectl label node minikube-m05 node-type=ops      --overwrite
kubectl get nodes -L node-type
```

### 2. Construir y cargar imágenes Docker

**IMPORTANTE**: Usa `minikube image load` para cargar las imágenes en Minikube (no `minikube docker-env`).

#### Opción 1: Script automatizado (Recomendado)

```bash
cd k8s
chmod +x build-images.sh
./build-images.sh
```

#### Opción 2: Manual

Las imágenes propias se etiquetan con el SHA corto de git (D21), nunca con `latest`. Desde el directorio `Implementacion K8S/Codigo`:

```bash
TAG=$(git rev-parse --short HEAD)
cd Backend
docker build -f PharmaGo.UsersService/Dockerfile -t pharmago-users-service:$TAG .
docker build -f PharmaGo.PharmacyService/Dockerfile -t pharmago-pharmacy-service:$TAG .
docker build -f PharmaGo.ApiGateway/Dockerfile -t pharmago-api-gateway:$TAG .
cd ../Frontend
docker build -f Dockerfile -t pharmago-ui:$TAG .
for img in pharmago-users-service pharmago-pharmacy-service pharmago-api-gateway pharmago-ui; do minikube image load $img:$TAG; done
```

`build-images.sh` hace lo mismo y agrega `-dirty` al tag si hay cambios sin commitear. `apply-k8s.sh` usa el mismo tag: los manifiestos tienen `IMAGE_TAG` y el script lo reemplaza al aplicar.

### Actualizar una versión sin caídas y volver atrás

```bash
./build-images.sh            # construye y carga las imágenes con el tag del commit actual
./deploy.sh <tag>            # RollingUpdate de users, pharmacy, gateway y ui, uno por uno
./rollback.sh                # vuelve los 4 a la revisión anterior
./rollback.sh pharmago-ui    # o solo uno
kubectl rollout history deployment/pharmago-api-gateway -n pharmago
```

Si un rollout no termina en 180 s, `deploy.sh` hace rollback de ese Deployment y corta. La técnica y su justificación están en `docs/despliegue-seguro.md`.

**Nota**: en un cluster multinodo, `minikube image load` carga las imágenes en todos los nodos.

## Despliegue

**IMPORTANTE**: Asegúrate de haber creado el cluster (paso 1) y construido y cargado las imágenes Docker (paso 2). Al terminar, corré `./seed-db.sh`.

### Opción 1: Script automatizado (Recomendado)

```bash
cd k8s
chmod +x apply-k8s.sh
./apply-k8s.sh
```

### Opción 2: Despliegue manual

```bash
cd k8s

# 1. Namespace
kubectl apply -f namespace.yaml

# 2. Secrets
kubectl apply -f secrets/db-secret.yaml

# 3. ConfigMaps
kubectl apply -f configmaps/

# 4. PersistentVolumes
kubectl apply -f persistent-volumes/

# 5. Database
kubectl apply -f services/ops/db-service.yaml
kubectl apply -f deployments/ops/db-deployment.yaml
kubectl wait --for=condition=ready pod -l app=pharmago-db -n pharmago --timeout=300s

# 6. Ops services (Elasticsearch primero)
kubectl apply -f services/ops/elasticsearch-service.yaml
kubectl apply -f deployments/ops/elasticsearch-deployment.yaml
kubectl wait --for=condition=ready pod -l app=elasticsearch -n pharmago --timeout=300s

kubectl apply -f services/ops/
kubectl apply -f deployments/ops/

# 7. Backend services
kubectl apply -f services/backend/
kubectl apply -f deployments/backend/

# 8. Frontend
kubectl apply -f services/frontend/
kubectl apply -f deployments/frontend/
```

## Verificación

### Ver estado de los pods

```bash
# Ver todos los pods
kubectl get pods -n pharmago -o wide

# Ver pods por nodo (con un nodo, todos aparecen en minikube)
kubectl get pods -n pharmago -o wide --field-selector spec.nodeName=minikube
```

### Ver servicios

```bash
kubectl get svc -n pharmago
```

### Ver logs

```bash
# Logs de un pod específico
kubectl logs -n pharmago <pod-name>

# Logs con seguimiento
kubectl logs -n pharmago -f <pod-name>
```

## Acceso a los Servicios

### La aplicación: Ingress + `minikube tunnel`

La UI y la API se acceden por un Ingress (`ingress/pharmago-ingress.yaml`): `/api` va al gateway y `/` a la UI. El Ingress reparte entre los pods sanos, así que sigue funcionando aunque se caiga un pod. Un `port-forward`, en cambio, se corta cuando muere el pod al que apunta.

En Windows con el driver docker, el Ingress se expone en tu PC con `minikube tunnel`. Abrí **PowerShell como administrador** (usa los puertos 80 y 443), corré esto y **dejá esa ventana abierta** mientras uses la app:

```bash
minikube tunnel
```

Con el túnel activo:
- **App**: http://127.0.0.1/
- **API**: http://127.0.0.1/api/... (por ejemplo http://127.0.0.1/api/drug)

El frontend usa `apiUrl: ''` en producción, así que llama a `/api/...` en el mismo host desde el que se cargó.

### Herramientas de operación: port-forward

```bash
cd k8s
./port-forward.sh
```

- **Prometheus**: http://127.0.0.1:9090
- **Grafana**: http://127.0.0.1:3000 (admin/admin)
- **Kibana**: http://127.0.0.1:5601
- **Elasticsearch**: http://127.0.0.1:9200 (o el puerto de `ES_LOCAL_PORT`)

Para detener: `./port-forward.sh --stop`

## Configuración de Replicas

Para cambiar el número de réplicas de cualquier componente, edita el archivo de deployment correspondiente:

```yaml
spec:
  replicas: 1  # Cambiar este valor
```

Luego aplica los cambios:

```bash
kubectl apply -f deployments/<component>/<deployment>.yaml
```

## Troubleshooting

### Pods no se inician (Pending / telemetría)

Si los pods de telemetría (otel-collector, prometheus, grafana, elasticsearch, kibana, fluent-bit) quedan en `Pending`:

1. **Falta etiqueta en el nodo**: cada pod requiere un nodo con su `node-type` (frontend, gateway, users, pharmacy u ops).
   - Corré `./cluster-up.sh`, que etiqueta los 5 nodos, o etiquetá a mano (ver paso 1).

   ```bash
   kubectl get nodes -L node-type
   ```

2. Verificar eventos del pod:
   ```bash
   kubectl describe pod <pod-name> -n pharmago
   ```

3. Ver logs:
   ```bash
   kubectl logs <pod-name> -n pharmago
   ```

### Imágenes no encontradas

Si los pods fallan con `ImagePullBackOff`:

1. Verificar que las imágenes están cargadas en Minikube:
   ```bash
   minikube image ls | grep pharmago
   ```

2. Si faltan imágenes, reconstruirlas y cargarlas:
   ```bash
   ./build-images.sh
   ```

3. Verificar que los deployments usan `imagePullPolicy: Never` (ya configurado).

### Base de datos no está lista

Si los servicios backend no pueden conectarse a la base de datos:

1. Verificar que el pod de la base de datos está corriendo:
   ```bash
   kubectl get pods -n pharmago -l app=pharmago-db
   ```

2. Verificar logs de la base de datos:
   ```bash
   kubectl logs -n pharmago -l app=pharmago-db
   ```

3. Verificar el secret:
   ```bash
   kubectl get secret db-secret -n pharmago -o yaml
   ```

### PersistentVolumes no se montan

En Minikube, los PersistentVolumes usan `hostPath` con `DirectoryOrCreate`, que crea los directorios automáticamente. Si tienes problemas:

```bash
# Conectarse al nodo y crear directorios manualmente
minikube ssh
sudo mkdir -p /mnt/data/{sql,elasticsearch,prometheus,grafana}
sudo chmod 777 /mnt/data/{sql,elasticsearch,prometheus,grafana}
exit
```

**Nota**: El deployment de SQL Server incluye un initContainer que configura los permisos para el usuario `mssql` (UID 10001).

### Elasticsearch OOMKilled (Out of Memory)

Si Elasticsearch está en `CrashLoopBackOff` con `OOMKilled`:

1. **Verificar memoria disponible en el nodo:**
   ```bash
   kubectl describe node minikube-m05 | grep -A 5 "Allocated resources"
   ```

2. **Aumentar memoria de Minikube (por nodo):**
   ```bash
   minikube delete
   MINIKUBE_MEMORY=4608 ./cluster-up.sh
   ```

3. **Reducir memoria heap de Elasticsearch:**
   Edita `deployments/ops/elasticsearch-deployment.yaml` y reduce `ES_JAVA_OPTS`:
   ```yaml
   - name: ES_JAVA_OPTS
     value: "-Xms1g -Xmx1g"  # Reducir de 2g a 1g
   ```
   Luego aumenta el límite de memoria del contenedor a 3-4Gi para compensar.

4. **Deshabilitar características que consumen memoria:**
   Agrega estas variables de entorno en el deployment:
   ```yaml
   - name: xpack.monitoring.collection.enabled
     value: "false"
   - name: xpack.security.enabled
     value: "false"  # Ya está configurado
   ```

5. **Verificar logs:**
   ```bash
   kubectl logs -n pharmago -l app=elasticsearch --tail=50
   ```

**Nota**: Elasticsearch requiere al menos 2GB de heap de Java y memoria adicional para el sistema operativo y otros procesos. En un entorno con recursos limitados (Minikube), considera usar una versión más ligera o deshabilitar características no esenciales.

### Kibana no está Ready

Si Kibana está `Running` pero no `Ready`:

1. **Verificar que Elasticsearch está funcionando:**
   ```bash
   kubectl get pods -n pharmago -l app=elasticsearch
   ```

2. **Verificar logs de Kibana:**
   ```bash
   kubectl logs -n pharmago -l app=kibana --tail=50
   ```

3. **Kibana espera a Elasticsearch:** Si Elasticsearch no está listo, Kibana no puede conectarse y permanecerá en `Running` pero no `Ready`.

## Limpieza (Equivalente a `docker-compose down`)

### Opción 1: Script automatizado (Recomendado)

```bash
cd k8s
chmod +x cleanup.sh
./cleanup.sh
```

**Conservar volúmenes persistentes:**
```bash
./cleanup.sh --keep-volumes
```

### Opción 2: Comando manual

```bash
# Eliminar namespace (elimina todos los recursos dentro de él)
kubectl delete namespace pharmago

# Eliminar PersistentVolumes (están fuera del namespace)
kubectl delete pv sql-pv elasticsearch-pv prometheus-pv grafana-pv
```

### Opción 3: Eliminar recursos individualmente

```bash
# Eliminar recursos en orden inverso al despliegue
kubectl delete -f deployments/
kubectl delete -f services/
kubectl delete -f configmaps/
kubectl delete -f secrets/
kubectl delete -f persistent-volumes/
kubectl delete -f namespace.yaml
```

**Nota**: Eliminar el namespace es la forma más simple y equivalente a `docker-compose down`, ya que elimina todos los recursos (pods, services, deployments, configmaps, secrets, PVCs) de una vez. Los PersistentVolumes deben eliminarse por separado ya que están fuera del namespace.

## Notas Importantes

1. **Logs**: Fluent Bit (DaemonSet) recolecta los logs de los pods y los envía directamente a Elasticsearch con índice `pharmago-logs-*`. Kibana se usa para visualizarlos.

2. **PersistentVolumes**: Los PVs usan `hostPath` que es adecuado para desarrollo pero no para producción. En producción, usa storage classes apropiadas.

3. **Secrets**: La contraseña de la base de datos está en texto plano en el secret. Para producción, considera usar herramientas como Sealed Secrets o external secret managers.

4. **Health Checks**: Los deployments incluyen health checks básicos. Asegúrate de que tus aplicaciones expongan endpoints `/health` o ajusta las configuraciones según corresponda.

5. **Recursos**: Los límites de recursos están configurados de forma conservadora. Ajusta según las necesidades de tu entorno.

## Estructura de Archivos

```
k8s/
├── namespace.yaml
├── configmaps/
│   ├── prometheus-config.yaml
│   ├── otel-collector-config.yaml
│   ├── grafana-provisioning.yaml
│   └── fluent-bit-config.yaml
├── secrets/
│   └── db-secret.yaml
├── persistent-volumes/
│   ├── sql-pv.yaml
│   ├── elasticsearch-pv.yaml
│   ├── prometheus-pv.yaml
│   └── grafana-pv.yaml
├── deployments/
│   ├── frontend/
│   │   └── ui-deployment.yaml
│   ├── backend/
│   │   ├── api-gateway-deployment.yaml
│   │   ├── users-service-deployment.yaml
│   │   └── pharmacy-service-deployment.yaml
│   └── ops/
│       ├── db-deployment.yaml
│       ├── otel-collector-deployment.yaml
│       ├── prometheus-deployment.yaml
│       ├── grafana-deployment.yaml
│       ├── elasticsearch-deployment.yaml
│       ├── kibana-deployment.yaml
│       └── fluent-bit-daemonset.yaml
├── services/
│   ├── frontend/
│   │   └── ui-service.yaml
│   ├── backend/
│   │   ├── api-gateway-service.yaml
│   │   ├── users-service-service.yaml
│   │   └── pharmacy-service-service.yaml
│   └── ops/
│       ├── db-service.yaml
│       ├── otel-collector-service.yaml
│       ├── prometheus-service.yaml
│       ├── grafana-service.yaml
│       ├── elasticsearch-service.yaml
│       └── kibana-service.yaml
├── build-images.sh
├── apply-k8s.sh
├── deploy.sh
├── rollback.sh
├── cleanup.sh
└── README-k8s.md
```

