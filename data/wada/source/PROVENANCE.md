# Procedencia de los datos

`colors.json` es una copia sin modificar de
https://raw.githubusercontent.com/mattdesl/dictionary-of-colour-combinations/master/colors.json
(repositorio `mattdesl/dictionary-of-colour-combinations`, licencia MIT, ver `LICENSE`),
descargada el 2026-09-14.

Contenido: 159 colores (`name`, `combinations`, `swatch`, `cmyk`, `lab`, `rgb`, `hex`)
que reconstruyen las 348 combinaciones (120 de 2 colores, 120 de 3, 108 de 4) del
libro "A Dictionary of Color Combinations" (Sanzo Wada, Seigensha 2010/2011).

Notas:
- El campo `lab` del archivo fuente está en D50 (PCS ICC). NO se usa: el motor recalcula
  Lab D65 desde `rgb` con su propio pipeline.
- Los `rgb`/`hex` fueron derivados por mattdesl de CMYK con LittleCMS
  (U.S. Web Coated SWOP v2 -> sRGB IEC61966-2.1, relative colorimetric + BPC).
- Errores conocidos frente al libro (issue #1 del repo, abierto): Citrine K 0->7;
  Rainette Green K 10->28; Diamine Green (87,32,91,18)->(87,20,100,10);
  Dull Violet Black (95,106,38,50)->(100,90,38,50); nombre "Mars Brown/Tobacco";
  typo "Calamine BLue". Las 348 combinaciones sí coinciden con el libro.
- Los nombres en inglés provienen de la nomenclatura de Ridgway (1912, dominio público);
  varios están deformados ("Rosolanc" = Rosolane, "Vandar Poel's" = Vanderpoel's, etc.).
- La obra de Wada (fallecido en 1967) está en dominio público en Japón (vida+50 expiró el
  2017-12-31; la extensión a 70 años de 2018 no es retroactiva). Se usan solo datos
  (nombres, CMYK, numeración); nunca escaneos ni textos del libro.
