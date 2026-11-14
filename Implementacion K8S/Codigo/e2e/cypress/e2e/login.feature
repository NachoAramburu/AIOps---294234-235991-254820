# language: es
@smoke
Característica: Inicio de sesión
  Como usuario de PharmaGo
  quiero iniciar sesión con mi usuario
  para usar las funciones de mi rol.

  La API está simulada: este escenario prueba la pantalla y corre en el pipeline sin cluster.

  Escenario: Un administrador con credenciales válidas entra a su página
    Dado que la API acepta el login como administrador
    Cuando abro la pantalla de login
    Y ingreso el usuario "admin" y la contraseña "clave-de-prueba"
    Y presiono el botón Login
    Entonces veo la página de administración

  Escenario: Con credenciales inválidas sigo en el login y veo el error
    Dado que la API rechaza el login
    Cuando abro la pantalla de login
    Y ingreso el usuario "admin" y la contraseña "clave-incorrecta"
    Y presiono el botón Login
    Entonces sigo en la pantalla de login
    Y veo un aviso que contiene "Login failed"
