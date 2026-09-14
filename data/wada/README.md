# data/wada: diccionario de Sanzo Wada

Datos del libro *A Dictionary of Color Combinations* (Sanzo Wada, 1933–34; reedición Seigensha
2010/2011): 159 colores y 348 combinaciones numeradas (120 de 2 colores, 120 de 3, 108 de 4).
Este directorio es la única fuente de verdad del diccionario para el motor y la app.

## Archivos

| Archivo | Quién lo escribe | Contenido |
|---|---|---|
| `source/colors.json` | nadie (copia sin modificar) | Dataset de mattdesl/dictionary-of-colour-combinations 1.0.2 (MIT). Ver `source/PROVENANCE.md` y `source/LICENSE`. |
| `dictionary.json` | generado | Colores (índice, nombre, `hex`, `rgb`, `cmyk`, `swatch`) y combinaciones (`id`, `size`, `colors` con índices ascendentes). |
| `errata.json` | generado | Discrepancias conocidas del dataset frente al libro (issue #1 y PR #2 de mattdesl). Solo documenta; nada se corrige. |
| `CONVERSION_CHECK.md` | generado | Informe de la reconversión CMYK → sRGB con un perfil SWOP local (o constancia de que no hay perfil). |
| `names.es.json` | **curado a mano** | 348 entradas `{id, name, lang, status, notes}`. El generador solo la crea si no existe; nunca la sobreescribe. |
| `../../engine/Sources/CColorEngine/ce_dict_data.h` | generado (`--emit-c`) | Header C con los mismos datos, todo `static const`. |

## Regenerar

```sh
make dict                    # regenera dictionary.json, errata.json y el header C; equivale a:
uv run --project oracle python -m oracle.build_dictionary --emit-c
```

Comprobar sin escribir (CI; sale con código 1 si algo en disco no coincide con lo que produciría
el generador):

```sh
uv run --project oracle python -m oracle.build_dictionary --check --emit-c
```

Tests:

```sh
uv run --project oracle pytest oracle/tests/test_dictionary.py -q
```

El generador es determinista: dos ejecuciones producen bytes idénticos (claves JSON ordenadas,
indentación 2, UTF-8, salto de línea final). `--check` ignora en `errata.json` los campos que
dependen de la máquina (`conversion_profile`, `derived_rgb_candidate`) y no compara
`CONVERSION_CHECK.md`.

Opciones: `--source`, `--out-dir`, `--header` (rutas), `--swop-profile RUTA` o variable
`COLORSAPP_SWOP_PROFILE` (perfil ICC CMYK a usar), `--no-icc` (salida independiente del entorno).

## Formato de `dictionary.json`

```json
{
  "schema": 1,
  "source": "mattdesl/dictionary-of-colour-combinations 1.0.2 (MIT)",
  "generated_by": "oracle.build_dictionary",
  "colors": [
    {"index": 0, "name": "Hermosa Pink", "hex": "#f9c1ce", "rgb": [249, 193, 206], "cmyk": [0, 30, 6, 0], "swatch": 0}
  ],
  "combinations": [
    {"id": 1, "size": 2, "colors": [65, 117]}
  ]
}
```

- `index`: posición 0..158, estable, coincide con el índice del header C.
- `swatch`: capítulo del libro, 0..5 (38/49/23/23/20/6 colores).
- `cmyk`: valores del libro (0..100) tal cual están en el fuente, erratas incluidas.
- `id`: número de lámina 1..348; `colors`: índices ascendentes, sin repetidos.
- **No hay Lab.** El motor calcula Lab D65 en C desde `rgb`. El campo `lab` del fuente es D50
  (PCS ICC) y no se propaga.

## Reglas

1. **El motor recibe solo sRGB8.** `ce_dict_data.h` contiene `rgb` (uint8 ×3), nombres en inglés,
   `swatch` y las combinaciones (`id`, `size`, `colors[7]`, relleno `CE_DICT_NONE = 0xFF`).
   `CE_DICT_MAX_COLORS` es 7 como reserva para el Vol. 2 (combinaciones de 3 a 7 colores).
   Cualquier otro espacio de color se deriva en C con el pipeline del motor, verificado contra
   el oráculo Python.
2. **Los nombres de combinación se curan en `names.es.json`.** El libro solo numera las láminas;
   ponerles nombre (en español o alemán, campo `lang`) es trabajo de curación y obra propia.
   `status` pasa de `pending` a lo que decida el curador; `notes` es libre. El generador no toca
   este archivo una vez creado.
3. **`source/colors.json` no se edita.** Las discrepancias con el libro se documentan en
   `errata.json` (`status: pending`). Si algún día se decide corregir un valor, se hará como una
   capa de overrides explícita y versionada, no editando el fuente.
4. **Nombres de color** en inglés tal cual vienen del fuente (nomenclatura de Ridgway 1912, con
   sus erratas: "Rosolanc", "Vandar Poel's", "Calamine BLue"...). Los nombres en español de los
   colores individuales no forman parte del MVP.
5. **Licencia y procedencia**: datos MIT (mattdesl, a partir de la transcripción de
   dblodorn/sanzo-wada). Se usan solo datos (nombres, CMYK, numeración); nunca escaneos ni
   textos del libro. Detalles en `source/PROVENANCE.md`.

## Sobre `CONVERSION_CHECK.md` y `derived_rgb_candidate`

Los `rgb` del fuente se derivaron de CMYK con LittleCMS (perfil *U.S. Web Coated (SWOP) v2* →
sRGB, relative colorimetric + compensación de punto negro). Si en la máquina hay un perfil SWOP
(`/Library/ColorSync/Profiles`, `/System/Library/ColorSync/Profiles`, perfiles de Adobe, o
`--swop-profile`), el generador repite esa conversión para los 159 colores, escribe la diferencia
máxima por canal en `CONVERSION_CHECK.md` y añade a cada errata CMYK un `derived_rgb_candidate`
(el sRGB que tendría el color con el CMYK del libro). Sin perfil, el informe lo dice y no hay
candidatos. El perfil de Adobe no se incluye en el repo (licencia de Adobe).
