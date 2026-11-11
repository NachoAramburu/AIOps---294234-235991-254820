# Detección de anomalías

Cubre el ítem 5 de la rúbrica: *"Deben implementarse los algoritmos IsolationForest y Support Vector Machine con función núcleo RBF para datasets que serán provistos por los docentes."*

**Estado: dataset de los docentes pendiente de recepción.** El cuaderno que lo procesa ya está listo y probado con un CSV de prueba (ver [Cómo correrlo](#cómo-correrlo)).

| Archivo | Qué es |
|---|---|
| `laboratorio_comparacion_detectores.ipynb` | Laboratorio del curso, completo: k-sigma, MAD, Isolation Forest y One-Class SVM RBF sobre 300 minutos sintéticos de un servicio de checkout, con las respuestas a las 7 preguntas y el exit ticket (sección 10). |
| `deteccion_dataset_docentes.ipynb` | Aplica Isolation Forest y One-Class SVM RBF a un CSV cualquiera, con los mismos hiperparámetros. Es el que se usa con el dataset de los docentes. |
| `requirements.txt` | Versiones fijas. Con otras versiones los números pueden cambiar. |

## Cómo correrlo

Desde Git Bash, dentro de `anomaly-detection/`, con Python 3.12:

```bash
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt     # en Linux/macOS: .venv/bin/python
.venv/Scripts/jupyter nbconvert --to notebook --execute --inplace laboratorio_comparacion_detectores.ipynb
```

Si `python -m venv` falla con un error de `ensurepip` (pasa con algunas instalaciones de Python en Windows), creá el venv con `python -m venv --without-pip .venv` y después instalá pip con `python -m pip --python "$(cygpath -w "$PWD/.venv/Scripts/python.exe")" install pip`.

`.venv/` está en el `.gitignore`. Para abrirlos de forma interactiva: `.venv/Scripts/jupyter notebook`.

### Con el dataset de los docentes

Copiá el CSV a `datos/dataset_docentes.csv` o pasá la ruta por variable de entorno. `FEATURES` son las columnas numéricas que entran al modelo; si no se indican, se usan todas las numéricas. `LABEL_COL` es opcional y **solo se usa para evaluar**.

```bash
DATA_PATH=datos/dataset_docentes.csv \
FEATURES=requests,error_rate,latency_ms,cpu_pct \
LABEL_COL=is_anomaly \
  .venv/Scripts/jupyter nbconvert --to notebook --execute --output resultado_docentes.ipynb deteccion_dataset_docentes.ipynb
```

El cuaderno muestra cuántas alertas da cada método, una tabla con cada fila que enciende al menos uno (con su score y su puesto en el ranking) y, si hay etiquetas, precisión, recall y F1. Si `DATA_PATH` no existe, lo avisa y termina sin error.

Se probó pasándole el dataset del laboratorio exportado a CSV: da exactamente las mismas métricas que el laboratorio (`docs/evidencia/C15/04-docentes-con-dataset-lab.txt`).

## Protocolo: por qué es no supervisado

- No hay etiquetas para entrenar. `StandardScaler` y los dos modelos se ajustan sobre **todas** las filas, incluidas las anómalas.
- La etiqueta (`kind` e `is_anomaly` en el laboratorio, `LABEL_COL` en el otro cuaderno) se mira recién al final, para calcular precisión, recall y F1.
- **Isolation Forest** arma 300 árboles con cortes al azar. Un punto raro queda aislado con pocos cortes. `IsolationForest(n_estimators=300, max_samples=min(256, n), contamination=0.10, random_state=42)`, score `-score_samples(X)`.
- **One-Class SVM con núcleo RBF** traza una frontera alrededor de la región donde están la mayoría de los puntos. `OneClassSVM(kernel="rbf", nu=0.10, gamma="scale")`, score `-decision_function(X)`.
- Los dos miran las cuatro métricas juntas. Por eso detectan combinaciones raras donde ningún valor, solo, es extremo.
- Semilla fija: dos corridas dan resultados idénticos bit a bit (`docs/evidencia/C15/05-reproducibilidad.txt`).

## Por qué `contamination` y `nu` son un presupuesto de alertas

`contamination=0.10` y `nu=0.10` no dicen cuántas anomalías hay: dicen **cuántas alertas está dispuesto a investigar el equipo**. Con 300 minutos, eso es unas 30 alertas (Isolation Forest da 30 y One-Class SVM 29).

En el laboratorio la tasa real es 17.7 % (53 minutos), así que con 30 alertas el recall máximo posible es 30/53 = 0.566. Subir el presupuesto aumenta el recall a costa de más falsos positivos. Se elige según cuántas alertas por hora puede atender quien esté de guardia, no según la tasa de anomalías, que en producción no se conoce.

## Tabla comparativa (laboratorio, semilla 42)

Sobre las 300 ventanas:

| Método | Vista | Precisión | Recall | F1 | Alertas |
|---|---|---|---|---|---|
| k-sigma error | univariado | 1.000 | 0.189 | 0.317 | 10 |
| k-sigma latencia | univariado | 1.000 | 0.151 | 0.262 | 8 |
| MAD error | univariado | 0.944 | 0.321 | 0.479 | 18 |
| MAD latencia | univariado | 1.000 | 0.679 | 0.809 | 36 |
| **Isolation Forest** | 4D | **0.800** | **0.453** | **0.578** | 30 |
| **One-Class SVM RBF** | 4D | **0.621** | **0.340** | **0.439** | 29 |

Minutos alertados por tipo de evento:

| Tipo | Minutos | ¿Anómalo? | Isolation Forest | One-Class SVM |
|---|---|---|---|---|
| incidente_5xx | 8 | sí | 8 | 4 |
| micro_burst | 2 | sí | 2 | 2 |
| timeouts | 4 | sí | 4 | 2 |
| cpu_latencia | 5 | sí | 5 | 3 |
| combo_sutil | 7 | sí | 4 | 1 |
| latencia_silenciosa | 6 | sí | 1 | 3 |
| spike_error | 3 | sí | 0 | 2 |
| degradacion | 18 | sí | 0 | 1 |
| batch | 20 | **no** | 4 | 5 |
| pico_carga | 8 | **no** | 0 | 2 |
| normal | 219 | no | 2 | 4 |

Lectura:

- **Isolation Forest gana** con el mismo presupuesto: 24 aciertos y 6 falsos positivos, contra 18 y 11. Detecta todo el `incidente_5xx` y más de la mitad del `combo_sutil`, la combinación que ningún detector univariado ve (ningún minuto pasa de 2.73 en un eje).
- **One-Class SVM** ve un poco mejor lo que se sale por un solo eje (`latencia_silenciosa`, `spike_error`), pero gasta alertas en el borde de tráfico alto (`pico_carga`) y solo detecta la mitad del incidente.
- **MAD sobre latencia** tiene el mejor F1 de la tabla, pero es una sola métrica con 36 alertas (más presupuesto) y no ve nada que no sea latencia: `spike_error` y `combo_sutil` le pasan desapercibidos. No reemplaza a los multivariados; los complementa.
- **Ninguno detecta bien la `degradacion`** (subida lenta de latencia): Isolation Forest 0 de 18, One-Class SVM 1 de 18. Evalúan cada minuto por separado y no tienen memoria. Para eso harían falta features de tendencia, como la diferencia contra los últimos N minutos.

## Falsos positivos con historia

`batch` y `pico_carga` son comportamiento **legítimo** que se parece a una anomalía:

- **Job batch** (20 minutos): CPU de 71 a 82 % cuando el máximo normal es 54.6 %, con tráfico normal o bajo. Es la mayoría de los falsos positivos: 4 de 6 en Isolation Forest y 5 de 11 en One-Class SVM. Un detector no supervisado mide *rareza*, no *daño*, y un proceso programado poco frecuente es raro.
- **Pico de carga** (8 minutos): hasta 183 requests por minuto, más que cualquier minuto normal (máximo 178), pero el error, la latencia y la CPU suben en la proporción habitual. Isolation Forest no lo marca. One-Class SVM marca 2 minutos porque su frontera castiga el borde poco poblado de la nube.

En operación, estos falsos positivos se reducen con contexto, no subiendo el umbral: excluir o etiquetar las ventanas de jobs conocidos, entrenar con varios días que incluyan picos de horario, o usar como features la relación entre métricas (por ejemplo, la latencia que sobra respecto de la esperada para ese tráfico) en vez de los valores crudos. El detalle por minuto está en las respuestas 4, 5 y en el exit ticket del laboratorio.
