# Notas de adaptación de la ficha (no se sube a Play Console)

Notas internas en español. Este fichero **no** se pega en Play Console: sirve para
saber qué se cambió respecto a la ficha de la App Store y qué frases hay que
confirmar contra la build de Android (carril A, app en `android/`; carril B,
segmentación) **antes de enviar a revisión**. Si una función marcada como
«pendiente de confirmar» no entra en la primera versión de Android, se borra su
línea de `full_description.txt` en los tres idiomas y se vuelve a ejecutar
`python3 docs/play/tools/check_limits.py`.

## Fuentes

- Textos de partida: `fastlane/metadata/{es-ES,de-DE,en-US}/` del checkout
  principal (`description.txt`, `subtitle.txt`, `promotional_text.txt`,
  `release_notes.txt`), `docs/APPSTORE.md` (§5 textos, §7 privacidad, §8 edad) y
  `docs/PRIVACY.md`.
- Tono revisado también contra la otra ficha de Play del propietario:
  `~/DEVELOP/RelaGame/docs/store/listing_*.md` (frases cortas, sin superlativos,
  mención explícita de «sin cuentas, sin anuncios, sin compras, sin red»).

## Qué se eliminó o se reescribió por ser de iOS

| En la ficha de la App Store | En la ficha de Play |
|---|---|
| «Todo en tu iPhone», «on your iPhone», «auf deinem iPhone» | «en tu teléfono» / «on your phone» / «auf deinem Telefon» |
| «Escanea tu carrete», «Scan your photo library», «Fotomediathek» | «una foto de tu galería» / «from your gallery» / «aus deiner Galerie» |
| «según el idioma de tu iPhone» | «según el idioma del sistema de tu dispositivo» (equivalentes de/en) |
| «funciona también con acceso limitado» (Fotos de iOS) | «funciona también con un acceso limitado a unas fotos concretas» (selector de fotos de Android / acceso parcial a medios) |
| Cabeceras en mayúsculas («QUÉ HACE», «PRIVACY»…) | Cabeceras en caja de frase («Qué hace», «Privacy and offline use»…): Play penaliza el caps-lock |
| Comillas tipográficas y guion largo en el título de Wada | Texto plano sin comillas especiales en la descripción completa |
| «Primera versión.» (notas de la versión) | «Primera versión para Android…» con una frase de qué hace la app |
| App gratuita (iOS 1.0.0 se publicó gratis; ver `docs/APPSTORE.md` §4) | Se añade el apartado «Precio / Price / Preis»: pago único, sin anuncios, sin compras dentro de la app y sin suscripción. El importe (2,99 USD) **no** va en el texto: lo muestra Play y varía por país e impuestos |

No había menciones a iCloud en los textos de la App Store; no se ha añadido
ninguna. El comprobador (`tools/check_limits.py`) falla si aparece «iPhone»,
«iOS», «iCloud», «App Store», «Apple Vision», «carrete», «Fotomediathek» o
«photo library» en cualquier fichero de la ficha.

## Verificación contra la build de Android (carril W7, 2026-10-28)

Todas las líneas que este fichero marcaba «pendientes de confirmar» se
comprobaron en la app real (emulador `chromasol-w7`, API 37, APK debug de
esta rama; permisos sobre el APK release) con las 8 fotos CC0 de
`harness/people` escaneadas. Resultado: **ningún texto de
`full_description.txt`/`short_description.txt` hubo que cambiar**; la
evidencia, línea a línea:

| Línea | Evidencia en Android |
|---|---|
| aísla personas, piel fuera, un color por prenda | Resultado: «Solo ropa · piel excluida · un color por prenda»; Ajustes con «Solo ropa» y «Excluir piel» |
| varias personas por separado | Ajustes: Todas / principal / elegida; selector de persona en el resultado |
| Extraer paso a paso | «Ver capas» abre la pantalla de capas (raster, máscara, peso, imagen reducida…) |
| galería y acceso limitado | Escaneo día 0 del carrete + `READ_MEDIA_VISUAL_USER_SELECTED`; selector `PickVisualMedia` sin permiso |
| foto nueva | Botón de cámara en Extraer (`TakePicture`, sin permiso `CAMERA`) |
| Rejilla y combinación del día | Pestaña Rejilla con las 348 y tarjeta «Combinación del día» en el Feed |
| Jardín | Pestaña Jardín: cosechas del escaneo y guardadas |
| tarjeta compartible | Compartir en feed y resultado (hoja del sistema) |
| mismos resultados en cada teléfono | Motor C compartido; «Acerca de» lo afirma (musl: mismos bits iOS/Android/WASM) |
| sin conexión / no usa la red | `aapt2 dump permissions` del APK release: solo permisos de medios; sin `INTERNET` (ver `data_safety.md`) |
| es/de/en según el sistema | Recursos `values`/`values-de`/`values-en`; capturas generadas en los tres idiomas |

Las capturas de esta verificación son las de la ficha:
`docs/play/screenshots/<locale>/` (script `tools/store/capture_play.py`).

## Decisiones de redacción para Play

- Título (≤ 30): «ChromaSol» + descriptor corto por idioma. Nada de «gratis»,
  precios, ni llamadas a la acción en el título (política de metadatos de Play).
- Descripción corta (≤ 80): una sola idea (qué combinación llevas) + «sin
  conexión» como rasgo diferencial.
- Descripción completa: sin emojis, sin superlativos («best», «la mejor»,
  «#1»), sin listas de palabras clave. Las palabras con las que la gente busca
  (colores, paleta, ropa, combinación, Wada) aparecen dentro de frases
  normales, no como lista.
- El precio no se escribe en ningún texto ni en el gráfico destacado: lo fija
  Play Console por país (2,99 USD de referencia) y un importe en el texto
  quedaría desactualizado.
