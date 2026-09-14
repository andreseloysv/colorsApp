# Comprobación de la conversión CMYK -> sRGB

Generado por `oracle.build_dictionary`, no editar a mano.

Los `rgb`/`hex` de `source/colors.json` los derivó mattdesl de los CMYK del libro con
LittleCMS: perfil *U.S. Web Coated (SWOP) v2* -> *sRGB IEC61966-2.1*, intent relative
colorimetric, compensación de punto negro, entrada y salida de 8 bits, CMYK escalado con
`round(v / 100 * 255)`. Este informe repite esa receta con Pillow/ImageCms y compara el
resultado con el `rgb` del fuente para los 159 colores.

## Resultado: sin perfil SWOP en esta máquina

No se encontró ningún perfil ICC cuyo nombre contenga `SWOP` o `WebCoated` en:

- `/System/Library/ColorSync/Profiles`
- `/Library/ColorSync/Profiles`
- `~/Library/ColorSync/Profiles`
- `/Library/Application Support/Adobe/Color/Profiles`
- `~/Library/Application Support/Adobe/Color/Profiles`

Tampoco está definida la variable de entorno `COLORSAPP_SWOP_PROFILE`.

Consecuencias:

- No se ha podido verificar la reproducibilidad de los `rgb` de mattdesl.
- `errata.json` no lleva `derived_rgb_candidate`.

Para hacer la comprobación: instalar el perfil *U.S. Web Coated (SWOP) v2.icc* (viene con
las aplicaciones de Adobe y con su paquete de perfiles ICC, sujeto a la licencia de Adobe;
no lo añadas al repositorio) y volver a ejecutar el generador, o pasar la ruta con
`--swop-profile` o `COLORSAPP_SWOP_PROFILE`.

## Anexo informativo: `Generic CMYK Profile.icc` (NO es una validación)

Perfil: *Generic CMYK Profile* (`/System/Library/ColorSync/Profiles/Generic CMYK Profile.icc`). No es el perfil SWOP con
el que se calcularon los `rgb`, así que las diferencias solo muestran cuánto depende el
resultado del perfil de imprenta elegido; no señalan errores del dataset.

- Diferencia máxima por canal (recalculado - fuente): R 23, G 14, B 28.
- Colores idénticos: 1 de 159.
- Colores con diferencia <= 1 en todos los canales: 2 de 159.
- Colores con diferencia <= 3 en todos los canales: 5 de 159.

Colores con diferencia > 1 en algún canal: 157 (tabla omitida en el anexo).
