# Seguridad de los datos (Data safety) — respuestas para Play Console

Respuestas para **Play Console > Contenido de la app > Seguridad de los datos**.
Documento interno en español; la consola puede mostrar las preguntas en inglés
o en el idioma de la cuenta, así que cada respuesta lleva la redacción de Play
entre comillas.

**Declaración resultante que verá el usuario en la ficha:** «No se recogen ni
se comparten datos» ("No data shared with third parties" / "No data
collected"). Es la misma declaración que en iOS («Data Not Collected», ver
`docs/APPSTORE.md` §7 y `docs/PRIVACY.md`).

## Verificación sobre la build final (carril W7, 2026-10-28)

Comprobado sobre el APK release de esta rama
(`aapt2 dump permissions app-release-unsigned.apk`); repetir sobre el AAB
que se suba:

```
uses-permission: android.permission.READ_MEDIA_IMAGES
uses-permission: android.permission.READ_MEDIA_VISUAL_USER_SELECTED
uses-permission: android.permission.READ_EXTERNAL_STORAGE maxSdkVersion=32
(permiso propio de firma …DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION, de AndroidX)
```

1. Sin `android.permission.INTERNET` ni `ACCESS_NETWORK_STATE`: el
   manifiesto de la app los elimina en la fusión (`tools:node="remove"`)
   precisamente porque una dependencia los pedía.
2. Sin SDK de analíticas, publicidad, informes de fallos ni atribución;
   sin permiso `CAMERA` (la foto se hace con el intent de la cámara del
   sistema) y sin cuentas ni identificadores.
3. El modelo de segmentación (MediaPipe) y el diccionario van **incluidos
   en el paquete**; nada se descarga en tiempo de ejecución.
4. **Matiz datatransport:** el dex de release contiene clases de
   `com.google.android.datatransport` (arrastradas por MediaPipe
   tasks-vision; se ven `CctBackendFactory` y el programador de tareas).
   Esas clases **no pueden transmitir nada**: sin permiso de red en el
   manifiesto fusionado cualquier intento de conexión falla en el sistema,
   y la app no registra eventos en esa biblioteca. Por tanto la respuesta
   del formulario sigue siendo «No se recoge ni se comparte ningún dato»;
   si Play preguntara en revisión, la explicación es esta (clases inertes
   de una dependencia, sin permiso de red).

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
