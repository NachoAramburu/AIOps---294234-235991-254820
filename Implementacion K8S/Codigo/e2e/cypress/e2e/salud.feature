# language: es
@e2e
Característica: La app desplegada responde
  Como equipo de operaciones
  quiero comprobar contra el cluster real que la app responde y se puede iniciar sesión
  para confirmar que el sistema quedó sano después de un despliegue o de un experimento de caos.

  Corre contra el Ingress (CYPRESS_BASE_URL=http://127.0.0.1, con minikube tunnel).
  La contraseña del usuario de prueba se pasa por CYPRESS_E2E_PASSWORD; nunca va en el código.

  Escenario: La API de medicamentos responde
    Cuando pido GET "/api/drug"
    Entonces la respuesta tiene estado 200

  Escenario: El administrador del seed inicia sesión de verdad
    Cuando abro la pantalla de login
    Y ingreso el usuario "admin" con la contraseña de prueba
    Y presiono el botón Login
    Entonces veo la página de administración
