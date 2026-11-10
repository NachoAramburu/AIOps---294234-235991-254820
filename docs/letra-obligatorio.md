# Letra del obligatorio de AIOps (transcripción fiel del .docx)

> Transcripción de `Obligatorio AIOps.docx` para que la IA la pueda leer. **Si algo difiere con `AGENTS.md`, manda este archivo.** No editar el contenido.

**Materia:** AIOps · Ingeniería y Licenciatura en Sistemas · Fecha de la letra: 7 de septiembre

## Condiciones

- Puntaje máximo: 0 puntos *(así figura en el original; la rúbrica suma 40)*
- Puntaje mínimo: 40 puntos *(así figura en el original)*
- Fecha de entrega: 16/11/2026 hasta las 21:00 horas en gestion.ort.edu.uy (max. 40Mb en formato zip, rar o pdf)

### Uso de material de apoyo y/o consulta: Inteligencia Artificial Generativa

- **Seguir las pautas de los docentes:** se deben seguir las instrucciones específicas de los docentes sobre cómo utilizar la IA en cada curso.
- **Citar correctamente las fuentes y usos de IA:** siempre que se utilice una herramienta de IA para generar contenido, se debe citar adecuadamente la fuente y la forma en que se utilizó. Se debe indicar: la/las herramientas utilizadas, y el contexto de uso (por ejemplo, generación de ideas, redacción inicial, análisis de datos, corrección de estilo, etc.).
- Todo contenido producido por IAG debe ser revisado y verificado; cualquier error presente será responsabilidad del estudiante.
- **Ser responsables con el uso de la IA:** conocer los riesgos y desafíos, como la creación de "alucinaciones", los peligros para la privacidad, las cuestiones de propiedad intelectual, los sesgos inherentes y la producción de contenido falso.
- El uso de herramientas de Inteligencia Artificial Generativa (IAG) puede emplearse como apoyo en el proceso de aprendizaje. Sin embargo, no sustituye el razonamiento crítico ni la elaboración personal. El estudiante es responsable de que el trabajo presentado refleje su propia comprensión, análisis y proceso cognitivo sobre el tema.
- La defensa es obligatoria y eliminatoria.
- La defensa será presencial salvo en casos en que se habilite la defensa oral sincrónica en forma remota.
- En caso de existir dudas sobre la autoría, plagio o uso no atribuido de IAG, el docente tendrá la opción de convocar al equipo de obligatorio a una defensa específica e individual sobre el tema.

### Defensa

Fecha de defensa: 23/11/2026. La defensa es obligatoria y eliminatoria. El docente es quien definirá y comunicará la modalidad y mecánica de defensa. La no presentación a la misma implica la pérdida de la totalidad de los puntos del Obligatorio.

### Importante

1) Inscribirse
2) Formar grupos de hasta 3 personas del mismo dictado
3) Subir el trabajo a Gestión antes de la hora indicada (ver hoja al final del documento: “RECORDATORIO”)

Aquellos de ustedes que presenten alguna dificultad con su inscripción o tengan inconvenientes técnicos, por favor contactarse con la Coordinadora de cursos o Coordinación Adjunta antes de las 20:00h del día de la entrega, a través del mail: adjuntos_ei@ort.edu.uy.

## Objetivo

El objetivo del obligatorio es experimentar con herramientas técnicas para mejorar la respuesta a incidentes, partiendo de un proyecto ya existente con un stack tecnológico usado en varias materias de la carrera. Las actividades del obligatorio se iniciarán en clase, y los equipos de trabajo deben customizarlas para el contexto de sus obligatorios.

Los equipos de trabajo deberán implementar requerimientos no funcionales para mejorar diferentes sub-atributos de calidad de la disponibilidad, desplegabilidad y mantenibilidad. Deberán también implementar un plan de contención de incidentes operacionales, y scripts que permitan simular incidentes operacionales. También deberán implementar técnicas de aprendizaje automático para detectar anomalías en datasets de datos operacionales.

Finalmente, el equipo deberá realizar una defensa de proyecto que consistirá en un war-room, que resultará de la ejecución de un script de ingeniería de caos provisto por los docentes. En dicha instancia, los estudiantes deberán llevar adelante el plan de mitigación de incidentes operacionales diseñado durante el curso y presentar hallazgos.

## Actividades

- Reducir el MTTR de un conjunto de fallos en tiempo de ejecución al mínimo posible, idealmente al orden de pocos segundos.
- Implementar técnicas de despliegue/reemplazo de componentes seguro.
- Diseñar, capturar y visualizar métricas de aplicación e infraestructura.
- Implementar logs estructurados y trazas con propagación de contexto de acuerdo a OpenTelemetry.
- Implementar un plan de mitigación de incidentes operacionales.
- Entrenar dos técnicas no supervisadas de detección de anomalías.
- Diseñar e implementar experimentos de ingeniería del caos.
- Reflexionar sobre el impacto de las prácticas de ingeniería de software ágil.

## Entregas y esfuerzo

El proyecto consiste en una única entrega, que se realizará a través de Gestión. Además, todos los productos de trabajo deben estar versionados en GitHub.

## Rúbrica de evaluación

| Objetivo | Puntaje | Resultados esperados |
|---|---|---|
| Implementación de plataforma | 5 | El sistema debe correr sobre Kubernetes. Cada microservicio debe ejecutar en un pod independiente. Los microservicios no pueden ejecutar en mismos nodos físicos. Se debe implementar un diagrama de despliegue de los componentes principales de la plataforma. |
| Alta disponibilidad | 5 | Los microservicios deben curarse automáticamente en casos de errores en tiempo de ejecución. Es decir, una vez que las réplicas de la aplicación llegan a un estado READY, ellas deben poder volver al mismo estado luego de excepciones. El sistema debe ser resiliente a ataques que inciten fallas reiteradas. Se debe implementar algún patrón que mitigue la eventualidad de tener un alto volumen de solicitudes fallidas. |
| Despliegues seguros | 5 | El sistema debe poder reemplazar sus componentes garantizando 100% de disponibilidad. Se necesita documentar y explicar la técnica elegida. |
| Telemetría | 5 | La aplicación debe contar con: logs estructurados en JSON; trazas de acuerdo a OTLP; métricas a nivel de pod/contenedor y nodo físico (se sugiere tener CPU, memoria, storage y red). Las métricas deben recolectarse con OTLP hacia Prometheus, visualización con Grafana. Los logs deben poder consultarse en alguna herramienta de manejo de logs como Kibana con ElasticSearch. Se deben configurar, por lo menos, 5 alertas en Grafana para detección de anomalías de las métricas ya definidas. |
| Técnicas de detección de anomalías | 5 | Deben implementarse los algoritmos IsolationForest y Support Vector Machine con función núcleo RBF para datasets que serán provistos por los docentes. |
| Plan de contención de incidentes operacionales | 5 | Se debe realizar un plan de mitigación de incidentes operacionales. |
| Scripts de caos | 5 | Se deben implementar al menos un script de caos que pruebe: inyección de requests, sobrecarga de CPU, sobrecarga de memoria, sobrecarga de storage, interrupción de tráfico de red y desconexión de componentes internos de la aplicación. |
| Defensa | 5 | Se debe ejecutar el script de caos implementado, mostrar sus efectos mediante telemetría y la respuesta del sistema. Se deben explicar cómo los mecanismos implementados en el obligatorio garantizan el comportamiento observado. |

## Tecnología y herramientas

- Tableros, repositorios y pipelines CI/CD: GitHub
- BDD: Cypress + Cucumber
- Desarrollo: .NET / Angular
- Grafana, OTLP y Prometheus.

Se espera que el equipo investigue y aplique técnicas y herramientas sobre el pipeline que permitan mejorar el valor entregado al cliente, en el contexto tecnológico específico del proyecto, tales como: *(en el original la lista está vacía)*

Incluir estos elementos de extensión pueden ayudar a compensar otras áreas débiles del proyecto.

## Guía para la realización del informe académico final

El informe final debe tener una sección para cada elemento de la rúbrica, explicando los desafíos enfrentados y los resultados obtenidos. La extensión no puede ser mayor a 10 páginas.

## RECORDATORIO: IMPORTANTE PARA LA ENTREGA

La entrega de los obligatorios será en formato digital online, a excepción de algunas materias que se entregarán en Bedelía y en ese caso recibirá información específica en el dictado de la misma.

Los principales aspectos a destacar sobre la entrega online de obligatorios son:

- Ingresá al sistema de Gestión.
- En el menú, seleccioná el ítem “Evaluaciones” y la instancia de evaluación correspondiente, que figura bajo el título “Inscripto”.
- Para iniciar la entrega hacé clic en el ícono: [IMAGEN]
- Ingresá el número de estudiante de cada uno de los integrantes y hacé clic en “Agregar”. El sistema confirmará que los integrantes estén inscriptos al obligatorio y, de ser así, mostrará el nombre y la fotografía de cada uno de ellos. Una vez agregados todos los integrantes, hacé clic en “Crear equipo”.

Cualquier integrante podrá:

- Modificar la integración del equipo.
- Subir el archivo de la entrega.

- Seleccioná el archivo que deseás entregar. Verificá el nombre del archivo que aparecerá en la pantalla y hacé clic en “Subir” para iniciar la entrega. Cada equipo (hasta 2 estudiantes) debe entregar un único archivo en formato zip o rar (los documentos de texto deben ser pdf, y deben ir dentro del zip o rar). El archivo a subir debe tener un tamaño máximo de 40mb *[nota del equipo: las condiciones dicen grupos de hasta 3]*

Cuando el archivo quede subido, se mostrará el nombre generado por el sistema (1), el tamaño y la fecha en que fue subido.

- El sistema enviará un e-mail a todos los integrantes del equipo informando los detalles del archivo entregado y confirmando que la entrega fue realizada correctamente.
- Podés cerrar la pestaña de entrega y continuar utilizando Gestión o salir del sistema.
- La hora tope para subir el archivo será las 21:00 del día fijado para la entrega.
- La entrega se podrá realizar desde cualquier lugar (ej. hogar del estudiante, laboratorios de la Universidad, etc).
- Aquellos de ustedes que presenten alguna dificultad con su inscripción o tengan inconvenientes técnicos, por favor contactarse con la Coordinadora de Cursos o Coordinación Adjunta antes de las 20:00h del día de la entrega, a través del mail: adjuntos_ei@ort.edu.uy.
