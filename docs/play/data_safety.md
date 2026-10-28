# Seguridad de los datos (Data safety) — respuestas para Play Console

Respuestas para **Play Console > Contenido de la app > Seguridad de los datos**.
Documento interno en español; la consola puede mostrar las preguntas en inglés
o en el idioma de la cuenta, así que cada respuesta lleva la redacción de Play
entre comillas.

**Declaración resultante que verá el usuario en la ficha:** «No se recogen ni
se comparten datos» ("No data shared with third parties" / "No data
collected"). Es la misma declaración que en iOS («Data Not Collected», ver
`docs/APPSTORE.md` §7 y `docs/PRIVACY.md`).

## Antes de responder: condiciones que deben ser ciertas en el AAB final

Estas respuestas solo son verdaderas si la build de Android (carril A)
cumple lo siguiente. Hay que comprobarlo sobre el AAB que se vaya a subir,
no sobre la intención:

1. El **manifiesto fusionado** no contiene `android.permission.INTERNET`
   (ni `ACCESS_NETWORK_STATE` para telemetría). Ojo: una biblioteca puede
   añadir el permiso por fusión aunque el manifiesto de la app no lo pida.
2. Sin SDK de analíticas, publicidad, informes de fallos ni atribución.
3. Sin modelos que se descarguen en tiempo de ejecución (p. ej. modelos de
   Play Services que bajan ficheros tras la instalación): la segmentación y
   el diccionario van incluidos en el paquete.
4. Sin cuentas, sin inicio de sesión y sin identificación del dispositivo.

Si alguna condición cambiara (por ejemplo, un informe de fallos), este
formulario habría que rehacerlo y ya no se podría declarar «No data
collected».

## Respuestas, sección por sección

### 1. Recogida y uso compartido de datos

| Pregunta de Play | Respuesta | Motivo |
|---|---|---|
| "Does your app collect or share any of the required user data types?" | **No** | La app no tiene red: ningún dato sale del dispositivo |
| "Is all of the user data collected by your app encrypted in transit?" | No aplica (la consola la omite o la deja sin efecto al no recogerse datos) | No hay datos en tránsito porque no hay transmisión |
| "Do you provide a way for users to request that their data is deleted?" | No aplica | No existe ningún dato en poder del desarrollador que borrar; lo guardado en el teléfono se borra al desinstalar la app o borrar sus datos en los ajustes de Android |

### 2. Tipos de datos (todos en «No»)

En cada tipo, tanto «recogido» ("Collected") como «compartido»
("Shared"): **No**.

| Categoría de Play | Respuesta | Nota |
|---|---|---|
| Ubicación (aproximada y precisa) | No / No | La app no pide permiso de ubicación y no lee la posición de las fotos |
| Información personal (nombre, correo, dirección, teléfono, identificadores de cuenta…) | No / No | Sin cuentas ni formularios |
| Información financiera | No / No | El pago único lo procesa Google Play; la app no ve ni guarda datos de pago |
| Salud y actividad física | No / No | Sin funciones de salud |
| Mensajes (correo, SMS, mensajes en la app) | No / No | Sin mensajería |
| **Fotos y vídeos** | **No / No** | Ver explicación siguiente |
| Archivos de audio | No / No | La app no graba ni lee audio |
| Archivos y documentos | No / No | Solo lee las imágenes que el usuario elige analizar |
| Calendario | No / No | — |
| Contactos | No / No | — |
| Actividad en la app (interacciones, historial de búsqueda, contenido generado…) | No / No | Las combinaciones guardadas y los resultados viven en una base de datos local del dispositivo y nunca salen de él |
| Navegación web | No / No | Sin navegador ni vistas web |
| Información y rendimiento de la app (registros de fallos, diagnósticos) | No / No | Sin informes de fallos ni diagnósticos automáticos; ver «diagnóstico opcional» abajo |
| Identificadores del dispositivo u otros | No / No | No se lee ningún identificador (ni publicitario ni de otro tipo) |

### Por qué «Fotos y vídeos» es «No» aunque la app lea fotos

En la definición de Play, un dato está «recogido» cuando se **transmite
fuera del dispositivo**. ChromaSol procesa las fotos solo en el teléfono
(el motor de color C se ejecuta en local y la app no tiene permiso de red),
así que las fotos no se recogen ni se comparten en el sentido de este
formulario. Lo mismo vale para los resultados derivados (paletas y
combinaciones guardadas): se quedan en el almacenamiento privado de la app.

Matices a vigilar en la build final:

- Si el port incluye «Exportar diagnóstico» como en iOS, el fichero lo crea
  el usuario a petición y lo envía él mismo a quien quiera (transferencia
  iniciada por el usuario, y sin fotos). No es recogida por el
  desarrollador, igual que en la declaración de la App Store.
- Compartir la tarjeta de una combinación es también una acción explícita
  del usuario desde la hoja de compartir del sistema; la app no la sube a
  ningún sitio.
- El acceso a la galería sí es un permiso de Android, y puede exigir su
  propia declaración de permisos en Play Console (ver `app_content.md`),
  pero eso es independiente de este formulario.

### 3. Prácticas de seguridad y política de privacidad

| Campo | Valor |
|---|---|
| URL de la política de privacidad | `https://andreseloysv.github.io/colorsApp_public/privacy.en.html` (antes de publicar hay que aplicar los cambios de `site_changes.md` para que cubra también Android) |
| Revisión de seguridad independiente ("Independent security review") | No (no se ha hecho ninguna; no marcar la insignia si la consola la ofrece) |
| Compromisos de familias / programa Diseñado para Familias | No aplica: la app no se dirige a menores de 13 años (ver `app_content.md`) |

## Texto corto reutilizable (por si la consola pide una explicación)

> ChromaSol works fully offline and requests no network permission. Photos
> are analyzed on the device only; no photo, result or identifier is ever
> transmitted, collected or shared. The app has no accounts, no ads, no
> analytics and no crash reporting. Data the app saves (found combinations)
> stays in the app's private storage and is deleted when the app is
> uninstalled.
