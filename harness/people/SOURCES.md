# Fotos de prueba con personas (`harness/people/`)

Ocho fotografías de Wikimedia Commons con licencia **CC0 1.0** (dedicación al dominio
público), verificada en la página de cada fichero (plantilla de licencia del wikitext y
`LicenseShortName` de la API; las de Unsplash llevan `{{Unsplash}}`, que Commons solo
admite para fotos publicadas en Unsplash antes del 5 de junio de 2017, cuando Unsplash
dejó CC0). No se usó ninguna CC BY/CC BY-SA. Uso: inspección de la extracción de sujeto
(personas, pose, piel, máscara); **no** son verdad de color ni entran en L4.

Descarga: miniatura de 1280 px de ancho servida por Commons (JPEG recomprimido por su
servidor de miniaturas, no el original de cámara), con `curl`. Normalización y
verificación: `build_people.py` (ver cabecera). Los originales descargados se borraron.

```sh
uv run --project oracle python harness/people/build_people.py check   # offline
uv run --project oracle python oracle/tools/to_ppm.py harness/people/03_couple_denim_street.png <scratch>/03.ppm
```

## Cobertura

| Pedido | Fotos |
|---|---|
| 1 persona de cuerpo entero (una con ropa negra) | 01 (negro), 02 |
| 2 o 3 personas (al menos una con denim) | 03 (denim), 04, 05 (denim) |
| Grupos de 4 o más | 06 (5), 07 (6) |
| Fondo muy cargado de color | 08 (y también 07) |

Casos difíciles incluidos a propósito: paraguas negro que puede entrar en la máscara (02),
personas de espaldas sin cara (03, 04), contraluz y manta que no es de nadie (04), mano en
primer plano y tamaños empatados (05), oclusiones y objeto amarillo saturado (06), ropa
blanca sobre mural saturado (07), cara tapada por mascarilla y ropa blanca con dominante
azul (08).

## `expected.json`

Anotación hecha a mano mirando cada PNG: valores **orientativos para inspección visual de
las capas**, no verdad de color ni gate de ningún umbral.

- `people`: número aproximado de personas reconocibles (sin contar figuras diminutas).
- `largest_person.bbox_hint`: `[x0, y0, x1, y1]` en píxeles del PNG, origen arriba a la
  izquierda, caja aproximada de la persona que parece mayor en área; si hay empate lo dice
  `notes`.
- `garments[].color_hex`: mediana sRGB de un parche de esa prenda medido sobre el PNG
  (incluye sombra y dominantes de la foto); `part` es `torso`, `legs` o `full`.
- `notes`: resto de personas y prendas, objetos que no son ropa y trampas del fondo.

## Límites

- Tamaño: PNG sin pérdidas a 1024 px da ~0,7–1,3 MB por foto; con 8 fotos el límite
  de 8 MB obligó a descartar candidatas con mucho detalle fino (grafiti de cuerpo entero,
  grupos en plaza con 10 personas) y a reescalar con BICUBIC en vez de LANCZOS (−4 %).
- Sin fotos de interior con luz cálida, ni de móvil (todas son de cámara y de fotógrafo);
  ninguna en HEIC ni Display P3. No sustituyen al set dorado de L4.
- Colores de `expected.json` medidos por mí sobre el PNG, sin consenso de jueces.

## Fuentes

| PNG | Categoría | Página de Commons | Autor | Licencia | Fecha foto | Evidencia | Descarga | Original → miniatura → PNG | sha256 del PNG |
|---|---|---|---|---|---|---|---|---|---|
| `01_single_black_outfit.png` | 1 persona, cuerpo entero, ropa negra | [Woman Entrance Gate Signs (Unsplash).jpg](https://commons.wikimedia.org/wiki/File:Woman_Entrance_Gate_Signs_(Unsplash).jpg) | Brooke Cagle brookecagle | Creative Commons Zero, Public Domain Dedication (`{{Unsplash}}`, http://creativecommons.org/publicdomain/zero/1.0/deed.en) | 2016-01-30 | id Unsplash photo-1454210801264 = 2016-01-31 UTC; categoría Commons *Images from Unsplash (review needed)* | 2026-09-15 | 5078x3385 → 1280x853 → 1024x682 | `f2d0fedf2529d9e2e1a5ffc65d71faff055cbc112633fd5405321b5801be1faa` |
| `02_single_dress_umbrella.png` | 1 persona, cuerpo entero, vestido azul marino estampado, paraguas negro | [Woman with umbrella (Unsplash).jpg](https://commons.wikimedia.org/wiki/File:Woman_with_umbrella_(Unsplash).jpg) | Nicklas Bajema nrbthe1st | Creative Commons Zero, Public Domain Dedication (`{{Unsplash}}`, http://creativecommons.org/publicdomain/zero/1.0/deed.en) | 2015-08-01 | categoría Commons *Images from Unsplash (review needed)* | 2026-09-15 | 2000x3000 → 1280x1920 → 683x1024 | `69d059dc22b178769901d118446950f42cffc1d7dcf474bbccb658429b2330ca` |
| `03_couple_denim_street.png` | 2 personas, denim | [Moscow, Taganka, people April 2025 01.jpg](https://commons.wikimedia.org/wiki/File:Moscow,_Taganka,_people_April_2025_01.jpg) | Retired electrician | Creative Commons Zero, Public Domain Dedication (`{{self\|cc-zero}}`, http://creativecommons.org/publicdomain/zero/1.0/deed.en) | 2025-04-24 13:26:31 | — | 2026-09-15 | 2845x4267 → 1280x1920 → 683x1024 | `8000ffae9e65d289ba06cef31884f152cac1c875fa47b28ada3aa99fd4874c81` |
| `04_two_women_backlit.png` | 2 personas, contraluz, ropa oscura | [Females in jeans at Joplin (Unsplash).jpg](https://commons.wikimedia.org/wiki/File:Females_in_jeans_at_Joplin_(Unsplash).jpg) | Brooke Cagle brookecagle | Creative Commons Zero, Public Domain Dedication (`{{Unsplash}}`, http://creativecommons.org/publicdomain/zero/1.0/deed.en) | 2016-02-16 | categoría Commons *Images from Unsplash (review needed)* | 2026-09-15 | 5472x3648 → 1280x853 → 1024x682 | `5c6ede6b96ad0704e727c89e481d307f937906f6bd232896f42eec82c91c4ce5` |
| `05_three_friends_closeup.png` | 3 personas, plano medio posado, denim | [Friends show off engagement ring (Unsplash).jpg](https://commons.wikimedia.org/wiki/File:Friends_show_off_engagement_ring_(Unsplash).jpg) | Colin Maynard invent | Creative Commons Zero, Public Domain Dedication (`{{Unsplash}}`, http://creativecommons.org/publicdomain/zero/1.0/deed.en) | 2017-05-27 | id Unsplash photo-1495911112171 = 2017-05-27 UTC; categoría Commons *Images from Unsplash (review needed)* | 2026-09-15 | 4361x6541 → 1280x1920 → 683x1024 | `39c1b8d4e3eb0ab667c38da3849ec04615719a320f983f22e1a77a9f9d3666f2` |
| `06_group_courier_street.png` | grupo de 4 o más, calle, objeto amarillo saturado, denim | [Moscow, Taganka, people April 2025 15.jpg](https://commons.wikimedia.org/wiki/File:Moscow,_Taganka,_people_April_2025_15.jpg) | Retired electrician | Creative Commons Zero, Public Domain Dedication (`{{self\|cc-zero}}`, http://creativecommons.org/publicdomain/zero/1.0/deed.en) | 2025-04-24 13:49:16 | — | 2026-09-15 | 3167x4201 → 1280x1698 → 772x1024 | `78e6311982bfbdc335f5d72aff193c929469c63022f32d4a3c120ecde8619342` |
| `07_group_mural_white_outfits.png` | grupo de 4 o más, mural muy saturado | [Goddesses Among Men (Unsplash).jpg](https://commons.wikimedia.org/wiki/File:Goddesses_Among_Men_(Unsplash).jpg) | Clarke Sanders clar_san | Creative Commons Zero, Public Domain Dedication (`{{Unsplash}}`, http://creativecommons.org/publicdomain/zero/1.0/deed.en) | Taken on 11 August 2016, 06:15 (according to Exif data) | id Unsplash photo-1493655161922 = 2017-05-01 UTC; categoría Commons *Images from Unsplash (review needed)* | 2026-09-15 | 5184x3456 → 1280x853 → 1024x682 | `be9339e10c9559517549b8970d7f403cb0f2e0d58b428e359cd4cfe323f69139` |
| `08_artist_colorful_mural.png` | fondo muy cargado de color (mural saturado), 1 persona con mascarilla | [Artist spray painting flowers (Unsplash).jpg](https://commons.wikimedia.org/wiki/File:Artist_spray_painting_flowers_(Unsplash).jpg) | Maxime Bhm maximebhm | Creative Commons Zero, Public Domain Dedication (`{{Unsplash}}`, http://creativecommons.org/publicdomain/zero/1.0/deed.en) | 2016-07-11 | id Unsplash photo-1468235301632 = 2016-07-11 UTC; categoría Commons *Images from Unsplash (review needed)* | 2026-09-15 | 5184x3456 → 1280x853 → 1024x682 | `bb096c840a2c7e5dce037a07c24a98be04c5f2ebbaf2a1633084d2bd0c11bf6f` |

## Notas de licencia

- Fotos de Unsplash (plantilla `{{Unsplash}}`): la página de cada fichero dice "published
  prior to 5 June 2017 under the Creative Commons CC0 1.0". Evidencia de fecha: campo
  `date` del fichero y, cuando el wikitext archiva la URL `images.unsplash.com/photo-<ms>`,
  su marca de tiempo Unix (columna Evidencia). La más ajustada es la 05 (2017-05-27).
- La categoría *Images from Unsplash (review needed)* indica que ningún revisor de Commons
  ha confirmado aún la licencia; ninguna tenía solicitud de borrado al revisarlas a mano
  (2026-09-15).
- Fotos con `{{self|cc-zero}}`: obra propia del autor en Commons.
- CC0 no exige atribución; se registra igualmente. Hay personas identificables: CC0 cubre
  el copyright, no los derechos de imagen (la página de la 05 lo advierte). Uso interno de
  prueba; no usar en material promocional. Sin menores en primer plano ni contextos
  sensibles. Si alguien pide retirarlas, se borran del repo.
- Los murales de fondo de 07 y 08 son obras con posibles derechos propios (en EE. UU. no
  hay libertad de panorama para obras 2D); Commons no las ha marcado. Aceptable como
  fixture interno de prueba; no redistribuir fuera del repo.

## Derivada sintética: `synthetic_tight_selfie.png`

Selfie apretada **derivada de `05_three_friends_closeup.png`** (misma licencia CC0 1.0, mismo
autor; no es foto del usuario). Reproduce el fallo que vio el usuario con una foto suya:
`VNGeneratePersonInstanceMaskRequest` junta en una instancia a dos adultos pegados. La mujer de
la derecha se recorta con su máscara de Vision, se desplaza 70 px a la izquierda por detrás de
la central y su hueco se rellena con la mediana por fila de la pared; lado mayor 320 px
(BICUBIC) para que el directorio siga < 8 MB (7,99 MB con ella: lo comprueba
`build_people.py check`). Se probaron dx 40–130, delante/detrás y 320–1024 px; se eligió una
variante en la que Vision junta a dos personas (con dx 70 detrás lo hace en todos los tamaños:
medidos 320, 352, 384 y 448 px, los cuatro dan 2 instancias → 3 personas tras separar).
Generador: `make_tight_selfie.py` (cabecera: máscaras con `visionmask
--variants selected0,selected1,selected2 --layers`; opciones `--dx 70 --order behind
--long-side 320`). 213×320, sha256
`9ab2c9e30d67bef15ed5287fff7c2c0d665059a1d12950657ffe6e887d3ae918`. Vision (macOS 26,
2026-09-16): 2 instancias (las dos mujeres de la izquierda en una) → 3 personas tras separar
con caras y poses. No está en `expected.json` ni en `SOURCES` de `build_people.py`.

## Derivadas sintéticas: `faces/` (caras que no son personas)

`faces/build_faces.py` genera en `harness/out/faces` (no se versiona) ocho PNG derivados de
`01_single_black_outfit.png` y `05_three_friends_closeup.png` (las dos CC0 1.0): un retrato
enmarcado y una pantalla encendida con una cara, cada uno solo, pegado a la silueta de la
persona, detrás de ella y sobre su torso. Sirven para medir las **personas fantasma** que
crearía una cara que no es una persona al separar instancias (ADR-010). La máscara de Vision de
la persona de 01 está versionada (`faces/person01_mask.png`, PNG de 1 bit, 2 KB) para que
`build` y `check` funcionen sin Vision, y `faces/faces.json` guarda el sha256 de los píxeles de
cada imagen. `make subject-faces` las genera; `make visionmask-faces` mide personas por fixture
con la regla de evidencia corporal, sin ella y sin separar.

## Formato

PNG RGB 8 bits, sRGB (perfil "sRGB built-in" embebido), lado mayor 1024 px, sin EXIF.
`oracle/tools/to_ppm.py` las convierte a PPM sin tocar el color.
