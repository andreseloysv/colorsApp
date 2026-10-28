# Contenido de la app y datos de la ficha — respuestas para Play Console

Respuestas para **Play Console > Contenido de la app** y para los campos
generales de la ficha que no son textos. Documento interno en español.
Los textos por idioma están en `listing/`; la seguridad de los datos en
`data_safety.md`; la clasificación por edad en `content_rating.md`.

## Declaraciones de «Contenido de la app»

| Declaración | Respuesta | Motivo |
|---|---|---|
| **Política de privacidad** | `https://andreseloysv.github.io/colorsApp_public/privacy.en.html` | Es la página pública ya usada en iOS. Antes de enviar hay que aplicar los cambios de `site_changes.md` para que también cubra Android, y comprobar que la URL responde |
| **Anuncios** ("Ads") | **No, la app no contiene anuncios** | Sin SDK de publicidad, sin banners ni anuncios propios |
| **Acceso a la app** ("App access") | **Todas las funciones están disponibles sin acceso especial** | No hay inicio de sesión, ni cuenta, ni códigos; el revisor entra y puede probarlo todo tras conceder permiso a las fotos o elegir una foto |
| **Clasificación de contenido** | Cuestionario IARC todo en «No» | Ver `content_rating.md` |
| **Seguridad de los datos** | No se recoge ni se comparte ningún dato | Ver `data_safety.md` |
| **Público objetivo** ("Target audience and content") | **13 años o más** (marcar los grupos 13-15, 16-17 y más de 18) | Ver apartado siguiente |
| **App de noticias** ("News app") | **No** | No hay noticias ni contenidos periodísticos |
| **Apps gubernamentales** ("Government app") | **No** | Es una app de un desarrollador independiente, sin relación con ningún gobierno |
| **Funciones financieras** ("Financial features") | **No** | Sin banca, pagos entre usuarios, préstamos, inversión ni criptomonedas. Que la app sea de pago único en Play no cuenta como función financiera: el cobro lo hace Google Play |
| **Funciones de salud** ("Health features" / declaración de apps de salud si la consola la pide) | **No** | Sin datos ni afirmaciones de salud; no accede a Health Connect |
| **Eliminación de cuenta** ("Data deletion" / "Account deletion") | **No aplica** | La app no permite crear cuentas, así que no hay cuenta que eliminar ni URL de eliminación que dar. Los datos locales (combinaciones guardadas) se borran al desinstalar la app o al borrar sus datos en los ajustes de Android |
| **Compras en la app** | **No hay** | Pago único de la app en la ficha; nada se vende dentro de la app |

### Público objetivo: por qué 13 años o más

- La app trata de colores de ropa y de un diccionario histórico de
  combinaciones: no está pensada ni diseñada para niños (sin juegos, sin
  personajes dirigidos a menores, sin contenido infantil). La política de
  privacidad ya publicada dice lo mismo («no está dirigida a menores de
  13 años»).
- Marcar solo grupos de 13 años en adelante evita que la app entre en el
  programa y las políticas de Familias de Play, que no le corresponden.
- No se marca «más de 18 únicamente» porque no hay ningún contenido que lo
  exija y porque adolescentes interesados en moda y color son público
  natural de la app.
- A la pregunta de si la ficha podría atraer a menores sin querer: **No**
  (la ficha habla de ropa, paletas y un diccionario de color; el icono es
  un sol botánico, no un personaje infantil). Si Google opinara lo
  contrario, la consola ofrecería añadir la advertencia «no dirigida a
  niños»; se aceptaría tal cual.

### Permisos de la build final (verificado por W7 en el APK release)

| Permiso | Para qué |
|---|---|
| `READ_MEDIA_IMAGES` | Escaneo día 0 del carrete (función principal, ver declaración abajo); pedido en contexto, nunca al arrancar |
| `READ_MEDIA_VISUAL_USER_SELECTED` | Acceso limitado a las fotos que el usuario elige (Android 14+) |
| `READ_EXTERNAL_STORAGE` (≤ API 32) | Equivalente en Android 12 y anteriores |

Sin `INTERNET`, sin `ACCESS_NETWORK_STATE`, sin `CAMERA` (intent de la
cámara del sistema), sin ubicación ni identificadores. Las fotos sueltas
se eligen además con el selector de fotos del sistema, que no necesita
permiso.

### Declaración «Photo and video permissions» (la pide Play por READ_MEDIA_IMAGES)

Uso principal (core use) a declarar: el escaneo inicial de la galería.
Texto para el formulario, en inglés y español:

> **EN:** ChromaSol's core feature is finding, in the clothes people wear
> in your photos, the closest of Sanzo Wada's 348 colour combinations.
> On day 0 the app offers to scan your most recent 200 photos on the
> device to build your initial collection (which combinations you have
> already worn). This requires broad photo access: the system photo
> picker alone is not enough because the user would have to hand-pick
> hundreds of photos one by one for a bulk, on-device scan, and the
> picker gives no durable access to re-scan later (Ajustes offers
> "Redo photo library scan"). All analysis happens on the device (the
> app requests no INTERNET permission); only derived colours are stored,
> never the photos. Limited access (selected photos) is fully supported,
> and single photos can also be analyzed through the system photo
> picker with no permission at all.

> **ES:** La función principal de ChromaSol es buscar, en la ropa de las
> personas de tus fotos, la combinación más parecida de las 348 de Sanzo
> Wada. El día 0 la app ofrece escanear en el dispositivo tus últimas
> 200 fotos para crear tu colección inicial (qué combinaciones ya has
> llevado). Eso exige acceso amplio a las fotos: el selector de fotos
> del sistema por sí solo no basta, porque el usuario tendría que elegir
> a mano cientos de fotos una a una para un escaneo masivo en el
> dispositivo, y el selector no da acceso duradero para reescanear
> después (Ajustes ofrece «Rehacer escaneo del carrete»). Todo el
> análisis ocurre en el teléfono (la app no pide permiso de INTERNET);
> solo se guardan los colores derivados, nunca las fotos. El acceso
> limitado (fotos seleccionadas) funciona por completo, y las fotos
> sueltas también se analizan con el selector del sistema, sin permiso.

## Categoría y etiquetas de la ficha

**Recomendación: Arte y diseño ("Art & Design").**

|  | Arte y diseño | Fotografía |
|---|---|---|
| Qué espera encontrar quien navega la categoría | Paletas, color, diseño, referencia creativa | Editores de fotos, cámaras, galerías, filtros |
| Encaje con ChromaSol | La mitad de la app es el diccionario: explorar las 348 combinaciones, la del día, la colección guardada; la foto es la entrada | La app no edita, no organiza ni mejora fotos; quien busque un editor se sentirá engañado |
| Competencia en la categoría | Apps de paletas y ruedas de color: vecindario natural y comparable | Editores generalistas con funciones que ChromaSol no tiene |

El análisis de fotos es el medio, pero el contenido y el valor
permanente de la app son el color y las combinaciones de Wada, así que la
categoría honesta es Arte y diseño. (En la App Store la principal es «Foto
y vídeo» con «Estilo de vida» secundaria, porque ahí no existe una
categoría de arte y diseño equivalente; en Play sí existe y solo se elige
una.)

Etiquetas ("Tags", si la consola las ofrece para la categoría): elegir las
relativas a color, paletas, diseño o moda de la lista que muestre la
consola; no inventar etiquetas fuera de esa lista.

## Datos de contacto y del desarrollador

| Campo | Valor |
|---|---|
| Correo de contacto de la ficha ("Contact email") | `andreslaley@msn.com` |
| URL de la política de privacidad | `https://andreseloysv.github.io/colorsApp_public/privacy.en.html` |
| Páginas por idioma (enlazadas entre sí desde la propia web) | es: `…/colorsApp_public/privacy.es.html` · de: `…/colorsApp_public/privacy.html` · en: `…/colorsApp_public/privacy.en.html` (base `https://andreseloysv.github.io`) |
| Nombre público de la app | ChromaSol (en los tres idiomas, con descriptor por idioma en el título; ver `listing/`) |
| Precio | De pago, precio de referencia **2,99 USD** (la conversión a cada moneda la propone Play Console; revisar el redondeo por país) |
| applicationId | `com.andreseloy.colorsapp` |

**Aviso para el propietario:** el correo de contacto pedido para Play
(`andreslaley@msn.com`) no es el mismo que el publicado hoy en la política
de privacidad y en el soporte de iOS (`andreseloysv@gmail.com`). Ambos
pueden coexistir (Play muestra el suyo en la ficha), pero conviene
confirmar qué buzón se quiere como contacto público único; si debe
unificarse, el cambio en la página de privacidad está descrito en
`site_changes.md`.
