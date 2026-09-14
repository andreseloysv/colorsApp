# Diccionario de Sanzo Wada: datos, formato y licencia

Investigación del 2026-09-14. Verificado contra fuentes primarias donde se indica; los archivos descargados (`mattdesl-colors.json`, `ridgway.html`, `bunka-2018.txt`, `maerz.txt`) están en este mismo directorio.

## 1. El libro

- **Original**: 配色総鑑 (*Haishoku Sōkan*), 6 volúmenes, 1933–1934, de Sanzo Wada (和田三造, 1883-03-03 – 1967-08-22, Tokio). Fundó en 1927 la Japan Standard Color Association (hoy Japan Color Research Institute).
- **Reedición Seigensha (Vol. 1)**: edición japonesa 配色事典―大正・昭和の色彩ノート, ISBN 978-4-86152-247-5, 1 jul 2010, A6, 352 pp., 1.500 ¥, comentario de 近江源太郎 (Japan Color Research Institute). Seigensha confirma "348通りの配色見本" y "すべての色表にCMYK値" + chips de color. La edición bilingüe inglés/japonés circula fechada 2011 (Wikipedia, Draw Down). **Seigensha no publica el número de colores**; el "159" sale del dataset: 159 entradas, 157 nombres distintos (dos pares A/B: "Eugenia Red | A/B", "Grayish Lavender - A/B").
- **Vol. 2**: ISBN 978-4-86152-772-2, 1 mar 2020, 336 pp., 1.500 ¥, bilingüe. Contenido: 72 combinaciones de 3–7 colores por las estaciones (6 por mes) + 165 de moda/interiores/gráfico (Japón 1910s–1930s) = **237 combinaciones**, **172 chips**. Fuentes: obras de Wada de 1935–36 y 1938. No existe dataset MIT limpio de Vol. 2 (solo shikifucodex.com sin licencia y su scrape estevesjh). Para el MVP no vale la pena; sí conviene que el esquema admita combinaciones de 2 a 7 colores.

## 2. Fuentes digitales

**mattdesl/dictionary-of-colour-combinations** (MIT, 506★, npm `dictionary-of-colour-combinations@1.0.2`, último push 2024-04-27). `colors.json` = array de 159 objetos:
`{ name, combinations: [int 1..348], swatch: 0..5, cmyk: [C,M,Y,K 0-100], lab: [L,a,b] (D50), rgb: [r,g,b], hex }`.
Las combinaciones no son entidades: se reconstruyen invirtiendo `combinations` (id → índices de color). Verificado localmente:
- ids 1..348 completos, sin huecos; **120 de 2 colores, 120 de 3, 108 de 4** (1.032 slots).
- `swatch` 0..5 (6 capítulos del libro): 38/49/23/23/20/6 colores.
- Sin hex, CMYK ni nombres duplicados; `hex == rgb`; todo color aparece ≥1 vez (Black en 23, 11 colores en una sola).

**dblodorn/sanzo-wada** (MIT, 333★): origen de la transcripción manual (`swatches_a..f.json` con `name/cmyk/combinations`). Sitio **sanzo-wada.dmbk.io** vivo (HTTP 200, `access-control-allow-origin: *`), sirve `/assets/colors.json` con hex "ingenuo" (Hermosa Pink → `#ffb3f0` frente a `#f9c1ce` en mattdesl). `sanzowada.app` no resuelve.

Otros: **shikifucodex.com** (171 colores, 581 combinaciones vol. 1+2, hex/RGB/CMYK/HSL/Lab/OKLCH + nombres japoneses, "transcribed from photographs of the printed book's swatch index", **sin licencia declarada**); **estevesjh/sanzo-wada-colors** (Python, MIT sobre el código, datos scrapeados de shikifucodex); **wada-sanzo-colors.com** (Paul Ungerer; classic 348 + seasons 72; RGB/HEX/LAB; "corrected a few values and names" de mattdesl sin detallar; sin licencia); **colorcombinations.org**, **sanzocolors.com**; R **jmaasch/sanzo** (GPL-3, 60 combos); **meodai/sanzoWadaColors** (MIT).

## 3. Estado legal

- Wada murió el 22-08-1967. Ley japonesa: plazo contado desde el 1 de enero siguiente (Art. 57); vida+50 → expiró el 31-12-2017. La extensión a vida+70 (Art. 51, CP-TPP, vigente desde 30-12-2018) **no revive obras expiradas** (Art. 7 disp. suplementarias del "TPP Development Act"; bunka.go.jp: "extensions will not be applied retroactively"; solo afecta a autores fallecidos en 1968 o después). Conclusión: la obra de Wada está en dominio público en Japón.
- **Seigensha**: los CMYK son datos técnicos; los nombres ingleses son nomenclatura de Ridgway (1912, dominio público). Riesgo residual: derecho de compilación (Art. 12: "selection or arrangement") si la edición 2010 seleccionó/ordenó, más derechos sobre diseño, escaneos y comentario. Mitigación: usar solo datos (nombres, CMYK, numeración), nunca escaneos ni textos del libro.
- **Nombres ingleses**: 143/159 aparecen en Ridgway, *Color Standards and Color Nomenclature* (1912, Gutenberg #63087). Las erratas del dataset son deformaciones de nombres de Ridgway: "Rosolanc"→Rosolane Purple, "Vandar Poel's"→Vanderpoel's Blue, "Krongbergs"→Kronberg's Green, "Veronia"→Vernonia Purple, "Vistoris Lake"→Victoria Lake, "Fresh Color"→Flesh Color, Antwarp/Cerulian/Sulpher/Pomegranite/Artemesia/"Calamine BLue". Maerz & Paul (1930) reutiliza nombres de Ridgway, así que la atribución a M&P no es incompatible, pero **no se verificó**. 16 nombres no están en Ridgway (Light Brown Drab, Carmine Red, Pale Burnt Lake, Ivory Buff, Cream Yellow, Golden Yellow, Maple, Khaki, Pale Raw Umber, Dull Viridian Green, Blackish Olive, Deep Lyons Blue, Deep Indigo, Dark Soft Violet, Dusky Madder Violet, Warm Gray); 4 de ellos sí aparecen en el OCR de M&P.

## 4. Calidad de los valores

- Conversión (verificada en `src/augment_sanzo.py` y `src/cmyk_icc/__init__.py`): CMYK → sRGB con LittleCMS (`littlecms==0.1b3`), perfil **U.S. Web Coated (SWOP) v2.icc → sRGB IEC61966-2.1.icc**, intent relative colorimetric + black point compensation. **`lab` es D50** (PCS ICC), no D65: no mezclar con Lab D65 calculado desde sRGB; recalcular con el pipeline propio.
- Errores conocidos (issue #1 de mattdesl, cotejo con el libro, abierto): Citrine K 0→7; Rainette Green K 10→28; Diamine Green (87,32,91,18)→(87,20,100,10); Dull Violet Black (95,106,38,50)→(100,90,38,50) (nótese M=106, imposible); nombre "Mars Brown/Tobacco"; typo "Calamine BLue" (#2). Issue #47 de dblodorn: Dull Violet Black se ve verde. El mismo cotejo dice que **las 348 combinaciones coinciden con el libro**.
- Colores casi indistinguibles (ΔE76, Lab D50): Isabella Color–Maple 2.9; Taupe Brown–Violet Carmine 4.0; Pale Lemon Yellow–Naples Yellow 4.0; Jasper Red–Peach Red 4.1; Coral Red–Fresh Color 4.5 → el match debe decidir sobre combinaciones completas y devolver top-3.
- **No existe** dataset con valores medidos (espectrofotómetro o escaneo calibrado) del libro impreso.

## 5. Nombres de combinaciones

Solo números 1–348 (láminas numeradas; los datasets llevan ints; colorcombinations.org y shikifucodex hablan de "numbered plates"). No hay nombres propios → ponerles nombre es trabajo de curación nuevo y obra propia del usuario. Los colores sí tienen nombre inglés (y japonés en la edición bilingüe; los japoneses digitalizados solo en shikifucodex).

## Findings (claim · confidence · URL)

1. Seigensha Vol. 1: ISBN 978-4-86152-247-5, 2010-07-01, 352 pp., 1.500 ¥, 348 combinaciones, CMYK en todas, chips · verified · https://www.seigensha.com/books/978-4-86152-247-5/ y https://en.seigensha.com/books/978-4-86152-247-5/
2. Vol. 2: ISBN 978-4-86152-772-2, 2020-03-01, 336 pp., 72 (3–7 colores) + 165 combinaciones, 172 chips, fuentes 1935–36 y 1938 · verified · https://en.seigensha.com/books/978-4-86152-772-2/
3. Wada: 1883-03-03 – 1967-08-22; 配色総鑑 6 vols 1933–34 · verified · https://en.wikipedia.org/wiki/Sanzo_Wada
4. mattdesl JSON: 159 colores, campos name/combinations/swatch/cmyk/lab/rgb/hex; 348 combos = 120×2 + 120×3 + 108×4; sin duplicados · verified (análisis local) · https://raw.githubusercontent.com/mattdesl/dictionary-of-colour-combinations/master/colors.json
5. mattdesl licencia MIT (c) 2020 Matt DesLauriers; npm 1.0.2 · verified · https://github.com/mattdesl/dictionary-of-colour-combinations
6. Conversión SWOP v2 → sRGB, relative colorimetric + BPC, Lab D50, LittleCMS · verified · https://raw.githubusercontent.com/mattdesl/dictionary-of-colour-combinations/master/src/augment_sanzo.py
7. Issue #1: 4 discrepancias CMYK y 1 de nombre frente al libro; combinaciones coinciden · verified · https://github.com/mattdesl/dictionary-of-colour-combinations/issues/1
8. dblodorn/sanzo-wada MIT (c) 2024 Dain Blodorn; transcripción original en swatches_a..f.json · verified · https://github.com/dblodorn/sanzo-wada
9. sanzo-wada.dmbk.io vivo, sirve assets/colors.json con hex ingenuo · verified (curl) · https://sanzo-wada.dmbk.io/assets/colors.json
10. 143/159 nombres están en Ridgway 1912; erratas explicables solo por Ridgway · verified (grep local) · https://www.gutenberg.org/files/63087/63087-h/63087-h.htm
11. Maerz & Paul 1930 contiene nombres de Ridgway (Corinthian Pink, Cotinga Purple…) · verified (OCR archive.org) · https://archive.org/details/dictionaryofcolo0000aloy
12. Japón: extensión a 70 años vigente 30-12-2018, no retroactiva; solo fallecidos ≥1968; cómputo desde 1 de enero siguiente (Art. 57) · verified · https://www.bunka.go.jp/english/policy/copyright/pdf/93468601_03.pdf
13. Art. 12 (compilaciones), 12-2 (bases de datos), 51, 57 · verified · https://www.japaneselawtranslation.go.jp/en/laws/view/4207/en
14. shikifucodex: 171 colores, 581 combos, transcritos de fotos, sin licencia · verified · https://shikifucodex.com/about
15. wada-sanzo-colors.com: classic 348 + seasons 72; corrige valores sin documentar; sin licencia · verified · https://www.wada-sanzo-colors.com/about
16. Combinaciones solo numeradas · likely · https://colorcombinations.org/about/
17. jmaasch/sanzo GPL-3, 60 combos · verified · https://raw.githubusercontent.com/jmaasch/sanzo/master/DESCRIPTION
