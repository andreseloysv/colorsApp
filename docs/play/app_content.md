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

### Permisos: punto a confirmar con la build (carril A)

Las declaraciones anteriores presuponen la build final. En concreto:

- Si el port lee la galería con un permiso amplio de fotos en lugar del
  selector de fotos del sistema, Play puede pedir la **declaración del
  permiso de fotos y vídeos** justificando que el acceso amplio es una
  función principal (analizar los colores de la ropa en las fotos del
  usuario). Eso se rellena cuando se sepa qué permisos trae el AAB.
- El manifiesto fusionado **no** debe contener
  `android.permission.INTERNET`; si lo contuviera, las declaraciones de
  datos y varios textos de la ficha dejarían de ser ciertos.

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
