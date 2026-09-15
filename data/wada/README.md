# data/wada: diccionario de Sanzo Wada

Datos del libro *A Dictionary of Color Combinations* (Sanzo Wada, 1933–34; reedición Seigensha
2010/2011): 159 colores y 348 combinaciones numeradas (120 de 2 colores, 120 de 3, 108 de 4).
Este directorio es la única fuente de verdad del diccionario para el motor y la app.

## Archivos

| Archivo | Quién lo escribe | Contenido |
|---|---|---|
| `source/colors.json` | nadie (copia sin modificar) | Dataset de mattdesl/dictionary-of-colour-combinations 1.0.2 (MIT). Ver `source/PROVENANCE.md` y `source/LICENSE`. |
| `overrides.json` | **solo el usuario** | Capa explícita de correcciones sobre el fuente (p. ej. al aceptar una errata). El generador la crea vacía si no existe y nunca la sobreescribe. Ruta protegida. |
| `dictionary.json` | generado | Colores (índice, nombre, `hex`, `rgb`, `cmyk`, `swatch`) y combinaciones (`id`, `size`, `colors` con índices ascendentes, `collection`). Raíz con `dict_version` y `status`. |
| `errata.json` | generado | Discrepancias conocidas del dataset frente al libro (issue #1 y PR #2 de mattdesl). Solo documenta; una errata pasa a `accepted` cuando hay un override para su `index`/`field`. |
| `CONVERSION_CHECK.md` | generado | Informe de la reconversión CMYK → sRGB con un perfil SWOP local (o constancia de que no hay perfil). |
| `names.es.json` | **curado a mano** | 348 entradas `{id, name, lang, status, notes}`. El generador solo la crea si no existe; nunca la sobreescribe. |
| `../../engine/Sources/CColorEngine/ce_dict_data.h` | generado (`--emit-c`) | Header C con los mismos datos, todo `static const`, más `CE_DICT_VERSION`. Lo incluye solo `ce_dict.c`; la API pública es `ce_dict_*` en `ce/ce.h`. |
| `../../engine/tests/data/golden_wada_lab.tsv` | generado (`make golden`) | Lab D65 de los 159 colores según el oráculo Python, con `# dict_version:` en la cabecera; `test_dict.c` lo cruza con `ce_dict_version()`. |
| `../../harness/label/names.html` | generado (`make names-html`) | Página autocontenida para curar `names.es.json` por lotes de 20. |

## Regenerar

```sh
make dict                    # regenera dictionary.json, errata.json y el header C; equivale a:
uv run --project oracle python -m oracle.build_dictionary --emit-c
make golden                  # regenera los golden, incluido golden_wada_lab.tsv (nuevo dict_version)
make test                    # test_dict.c comprueba que el motor lleva el mismo dict_version
```

Si cambia el diccionario (override aceptado, colección curada) hay que ejecutar los tres en
ese orden; `make dict-check`, `make test` y `pytest` fallan mientras algo esté desfasado.

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

Opciones: `--source`, `--out-dir`, `--header`, `--overrides` (rutas), `--swop-profile RUTA` o
variable `COLORSAPP_SWOP_PROFILE` (perfil ICC CMYK a usar), `--no-icc` (salida independiente del
entorno).

## Formato de `dictionary.json`

```json
{
  "schema": 1,
  "source": "mattdesl/dictionary-of-colour-combinations 1.0.2 (MIT)",
  "generated_by": "oracle.build_dictionary",
  "status": "provisional",
  "dict_version": "fd95ac692777",
  "colors": [
    {"index": 0, "name": "Hermosa Pink", "hex": "#f9c1ce", "rgb": [249, 193, 206], "cmyk": [0, 30, 6, 0], "swatch": 0}
  ],
  "combinations": [
    {"id": 1, "size": 2, "colors": [65, 117], "collection": null}
  ]
}
```

- `index`: posición 0..158, estable, coincide con el índice del header C.
- `swatch`: capítulo del libro, 0..5 (38/49/23/23/20/6 colores).
- `cmyk`: valores del libro (0..100) tal cual están en el fuente, erratas incluidas (salvo override).
- `id`: número de lámina 1..348; `colors`: índices ascendentes, sin repetidos.
- `collection`: colección temática curada por el usuario; `null` hasta entonces. **No son los
  6 capítulos del libro** (solo 27/348 combinaciones tienen todos sus colores en un capítulo).
- `dict_version`: sha256 corto (12 hex) del JSON canónico (`sort_keys`, sin espacios) de
  `{"colors", "combinations"}` tras aplicar overrides. Cambia con cualquier color, combinación o
  colección; no con los metadatos. El header C lo lleva como `CE_DICT_VERSION`, el motor lo
  expone en `ce_dict_version()` (`ce dict --version`) y la app iOS debe comprobar que coincide
  con el JSON del bundle.
- `status`: `provisional` hasta que el usuario coteje los 348 con el libro Seigensha Vol. 1 y
  cambie `DICT_STATUS` a `book-verified` en `oracle/oracle/build_dictionary.py`. Mientras tanto
  el scorecard imprime `book-verified: no`.
- **No hay Lab.** El motor calcula Lab D65 en C desde `rgb`. El campo `lab` del fuente es D50
  (PCS ICC) y no se propaga.

## Formato de `overrides.json`

```json
{
  "schema": 1,
  "overrides": [
    {"index": 115, "field": "name", "value": "Calamine Blue",
     "reason": "PR #2 de mattdesl; nombre de Ridgway 1912", "accepted_at": "2026-09-14"}
  ]
}
```

- `index`: 0..158; `field`: `cmyk` (4 enteros 0..100), `rgb` (3 enteros 0..255; el generador
  recalcula `hex`) o `name` (ASCII no vacío); `value` distinto del fuente; `reason` y
  `accepted_at` (fecha ISO) obligatorios. Un solo override por `(index, field)`.
- El fuente **nunca** se edita: los overrides se aplican en memoria y el resultado debe seguir
  pasando la validación (hex y nombres únicos...); si no, `make dict` sale con 2.
- Tras editarlo: `make dict && make golden && make test` (cambia `dict_version`).
- Las 4 erratas CMYK quedan pendientes hasta tener el perfil SWOP (`derived_rgb_candidate`
  con error <= 1/255); las 2 de nombre pueden aceptarse sin ICC.

## Reglas

1. **El motor recibe solo sRGB8.** `ce_dict_data.h` contiene `rgb` (uint8 ×3), nombres en inglés,
   `swatch` y las combinaciones (`id`, `size`, `colors[7]`, relleno `CE_DICT_NONE = 0xFF`).
   `CE_DICT_MAX_COLORS` es 7 como reserva para el Vol. 2 (combinaciones de 3 a 7 colores).
   Cualquier otro espacio de color se deriva en C con el pipeline del motor, verificado contra
   el oráculo Python.
2. **Los nombres de combinación se curan en `names.es.json`.** El libro solo numera las láminas;
   ponerles nombre (en español o alemán, campo `lang`) es trabajo de curación y obra propia.
   `status` pasa de `pending` a lo que decida el curador; `notes` es libre. El generador no toca
   este archivo una vez creado. Herramientas: `make names-todo` (pendientes e ids) y
   `make names-html` → `harness/label/names.html` (lotes de 20 con swatches grandes, número,
   tamaño, nombres en inglés, campos de nombre/idioma/estado/notas y botón que descarga
   `names.es.json`; sin servidor ni red). El agente solo puede proponer `names.suggested.json`.
3. **`source/colors.json` no se edita.** Las discrepancias con el libro se documentan en
   `errata.json` (`status: pending`). Corregir un valor = añadir un override en `overrides.json`
   (solo el usuario), nunca editar el fuente.
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

## Propuestas de nombres

`names.suggested.json` es una **propuesta** del agente (348 entradas `{id, name_es, name_de,
rationale}`, una por lámina, revisadas para evitar duplicados, anglicismos y palabras clave
repetidas más de tres veces). No es el fichero curado y el generador no lo lee.

Para aceptar un nombre: copiar `name_es` **o** `name_de` al campo `name` de la entrada con el
mismo `id` en `names.es.json`, poner `lang` en `es` o `de` según el que se haya elegido y
`status` en `accepted` (`notes` es libre). También se puede hacer desde
`harness/label/names.html` (`make names-html`), pegando el nombre elegido en el campo de la
lámina y descargando el `names.es.json` resultante. Si ninguna de las dos opciones convence,
se puede pedir al agente otra ronda (para un `id` concreto, un lote o todo el diccionario);
el agente solo reescribe `names.suggested.json`, nunca `names.es.json`.
