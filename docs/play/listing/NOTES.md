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

## Líneas que dependen de funciones de Android aún no construidas

Estado al escribir esto: la app de Android la está construyendo el carril A y la
segmentación de personas (equivalente a Vision en iOS) la investiga el carril B.
Las líneas siguientes describen el comportamiento de la versión de iOS ya
publicada y el objetivo del port, pero **todavía no están verificadas en
Android**. Antes de enviar a revisión hay que confirmar cada una contra el
AAB final; las que no se cumplan se borran de los tres `full_description.txt`.

| Línea de `full_description.txt` (es; equivalentes de/en) | Depende de | Si no entra en la 1.0 de Android |
|---|---|---|
| «aísla a las personas, deja fuera la piel y reduce la ropa a sus colores reales: un color por prenda» | Segmentación de personas + exclusión de piel + paleta por prenda del motor C vía NDK (carriles A y B) | Reescribir el párrafo inicial sin aislamiento de personas ni piel |
| «Fotos con varias personas: reconoce a cada una y analiza su ropa por separado» | Separación por persona (instancias) en Android | Borrar la viñeta |
| «Extraer: inspecciona paso a paso cómo se llegó al resultado (recorte, piel, prendas y paleta)» | Pestaña de inspección por capas portada a Android | Borrar la viñeta |
| «…o a tu galería si se lo permites, y funciona también con un acceso limitado a unas fotos concretas» | Permiso de medios de Android y/o selector de fotos del sistema; escaneo de la galería si el port lo incluye | Dejar solo «las fotos que tú eliges» si solo hay selector |
| «Rejilla: … con las que ya has llevado marcadas; la combinación del día…» | Pestaña Rejilla y combinación del día portadas | Borrar o recortar la viñeta |
| «Jardín: tu colección de combinaciones desbloqueadas y guardadas» | Pestaña Jardín y persistencia local portadas | Borrar la viñeta |
| «Tarjeta compartible con tu paleta y el número de combinación» | Compartir imagen (hoja de compartir de Android) portado | Borrar la viñeta |
| «Los mismos resultados en cada teléfono, siempre» | Paridad del motor C compilado con el NDK (`-ffp-contract=off`, sin fast-math) verificada por el carril A | Suavizar a «los mismos criterios de cálculo» si la paridad bit a bit no está demostrada |
| «la app funciona sin conexión… no usa la red» | Manifiesto fusionado final sin `android.permission.INTERNET` y sin SDK que descarguen modelos (verificable solo con el AAB del carril A) | No publicar hasta que sea cierto: es también la base de `data_safety.md` |
| «Español, alemán e inglés, según el idioma del sistema» | Recursos `values-es` / `values-de` / `values` completos en el AAB | Publicar solo los idiomas realmente incluidos |

Lo que **no** depende de funciones pendientes y puede quedarse tal cual: las
348 combinaciones y los nombres originales de Wada (van en el diccionario del
motor), el cálculo CIELAB/CIEDE2000 (motor C compartido), el pago único sin
anuncios ni compras integradas y los créditos.

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
