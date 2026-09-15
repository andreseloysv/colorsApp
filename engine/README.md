# Motor de color (capas 1, 2 y 3, máscaras de ropa y piel, capas de depuración)

Librería C11 sin I/O, sin `malloc` y sin dependencias (solo `<math.h>`), con
todo en `double`. La misma fuente compila a nativo (iOS/macOS vía Swift Package
o CMake) y a WebAssembly (Emscripten). Cubre:

- **Capa 1** (`ce_math.c`): sRGB (IEC 61966-2-1) ⇄ XYZ (D65) ⇄ CIELAB, en 8 bits
  y en `double`; ΔE*ab (1976) y ΔE00 (CIEDE2000, Sharma/Wu/Dalal 2005) con
  `kL, kC, kH`; adaptación cromática de Bradford entre A, D50, D65, D75 y F2.
- **Diccionario** (`ce_dict.c` + `ce_dict_data.h` generado): los 159 colores y
  348 combinaciones de Wada, solo sRGB8; el Lab lo calcula el motor.
- **Capa 2** (`ce_ctx.c`, `ce_image.c`, `ce_palette.c`): contexto reservado por
  el llamante y extracción determinista de la paleta dominante (ver más abajo).
- **Capa 3** (`ce_match.c`): match de la paleta contra las 348 combinaciones
  (`ce_match`) y análisis completo imagen → paleta → match (`ce_analyze`), ver
  más abajo.
- **Máscaras** (`ce_mask.c`): regiones de ropa a partir de la pose, recorte de
  cabeza sin pose y exclusión de piel con un modelo adaptativo por persona
  (ver «Máscaras: regiones de ropa y piel»).
- **Capas de depuración** (`ce_debug.c`): imagen reducida, peso, swatch y
  cluster por píxel, destino de cada cluster y explicación del score (ver
  «Capas de depuración»).
- **libm portable** (`ce_libm.c`, fase 5): `ce_cbrt`, `ce_pow`, `ce_exp`,
  `ce_atan2`, `ce_sin` y `ce_cos` copiados de musl 1.2.6 (sin FMA) y
  compilados con el motor en todas las plataformas: Lab, ΔE00, pesos, scores y
  hashes son **bit a bit idénticos** en nativo y WASM (ver «Determinismo nativo
  vs WASM» y «Paridad nativo/WASM»).

API pública: `Sources/CColorEngine/include/ce/ce.h` (documentada en español).
Wrapper Swift: `Sources/ColorEngine/ColorEngine.swift` (`Lab`, `srgbToLab`,
`labToSrgb8`, `deltaE2000`, `deltaE76`, `Swatch`, `PaletteOptions`,
`extractPalette`, `nearestDictionaryColor`, `MatchOptions`, `Hit`,
`AnalysisResult`, `analyze`, accesores `dictionary*`). Desde la fase 6
`extractPalette` y `analyze` aceptan `mask:` opcional (`UnsafeBufferPointer<UInt8>?`,
width × height bytes sin stride, 0 anula el píxel; corto => `.maskTooSmall`), que
va tal cual a `ce_image.mask`; la app la usa para la máscara de persona. Máscaras
de ropa y piel (`clothingRegions`, `cutHead`, `fitSkinModel`, `excludeSkin`) y
capas de depuración (`paletteDebugLayers`, `explainMatch`): ver sus secciones.

## Compilar y probar

Desde la raíz del repo (todas las rutas del `Makefile` son relativas a él):

| Comando            | Qué hace                                                          |
|--------------------|-------------------------------------------------------------------|
| `make test`        | CMake Release (-O2) en `build/`, `ctest` nativo                    |
| `make test-asan`   | Igual con `-fsanitize=address,undefined` en `build-asan/`          |
| `make test-wasm`   | `emcmake cmake` en `build-wasm/`; el test sale como `.js` y corre con node |
| `make golden`      | Regenera `tests/data/golden_*.tsv` con el oráculo Python           |
| `make diff-oracle` | 100 000 colores sRGB8 por `ce convert` contra el oráculo estricto  |
| `make swift-test`  | `swift test` del paquete (XCTest)                                  |
| `make fuzz [FUZZ_SECONDS=600] [FUZZ_SEED=1]` | Fuzz loop propio bajo ASan/UBSan en `build-asan/` (`mk/engine.mk`): paleta + capas, parser PNM, regiones de ropa, piel |
| `make bench-palette` | Imprime `PERF_1024_RGBA_MS` de `test_palette` (nativo -O2); anotar en `BENCHLOG.md` |
| `make bench-match` | Imprime `MATCH_MS`, `ANALYZE_1024_MS` y el recall exacto de `test_match` (nativo -O2) |
| `make parity [PARITY_TOP=10]` | Paridad nativo/WASM: `ce match --json` de `build/` y `build-wasm/` sobre las 20 fixtures de `harness/wasm/fixtures/` (`harness/wasm/run_parity.js`) y capas/máscaras byte a byte (`tests/layers_parity.js`); ver «Paridad nativo/WASM» |
| `make parity-fixtures` | Regenera `harness/wasm/fixtures/` (20 PPM ≤ 128 px + `manifest.json`) con `uv` y comprueba que es idéntico byte a byte |
| `make clean`       | Borra `build*/` y `engine/.build`                                  |

Requisitos: cmake ≥ 3.20, clang, Emscripten (`emcc`, `emcmake`, node), Xcode
(para XCTest) y `uv` para el oráculo (`oracle/`, dependencias ya fijadas en
`pyproject.toml`).

CLI de pruebas (`build/tools/ce`, también `node build-wasm/tools/ce.js`):

```
ce version
ce lab 180 90 30                     # -> L a b (%.12f)
ce de2000 50 2.6772 -79.7751 50 0 -82.7485
ce de2000 < pares.txt                # líneas "L1 a1 b1 L2 a2 b2" -> ΔE00
ce convert < colores.txt             # líneas "R G B" -> "L a b" (%.15e)
ce dict --version | --list | --id 12 # diccionario embebido
ce palette foto.ppm --json           # paleta dominante (capa 2), ver abajo
ce match foto.ppm --top 3 --json     # paleta + match contra el diccionario (capa 3)
ce analyze foto.ppm --json           # alias exacto de match
ce batch lista.txt --json            # JSONL: una línea por "imagen [mascara]" de la lista
ce match foto.ppm --json --debug-dir capas/   # + capas de depuración en capas/
ce regions --size 200x400 --mask persona.pgm --pose pose.txt --out ropa.pgm
ce skin --image foto.ppm --sample cara.pgm --mask ropa.pgm --out sin_piel.pgm
ce cut-head --mask persona.pgm --fraction 0.2 --out sin_cabeza.pgm
```

Opciones CMake: `CE_BUILD_TESTS` (ON), `CE_BUILD_CLI` (ON), `CE_SANITIZE`
(OFF; solo la activa `make test-asan` / `make fuzz`), `CE_ROUNDTRIP_STEP`
(1; paso del round-trip exhaustivo).

## Capa 2: extracción de paleta (`ce_ctx.c`, `ce_image.c`, `ce_palette.c`)

**Contexto.** El motor no reserva memoria: el llamante pide `ce_ctx_size()`
bytes (2 044 176 B = 1,949 MiB; cota dura 2 MiB por `_Static_assert` y por
`test_ctx_size_budget`, que corre en nativo, ASan y WASM), alineados a 16, y los
inicializa con `ce_ctx_init` (limpia el bloque y construye la caché Lab de los
159 colores con `ce_dict_color_lab`). Dentro viven la imagen reducida
(256×256×3 B), los pesos por píxel (`double`), el histograma de 32 768 bins
(Σw, Σw·r, Σw·g, Σw·b, conteo, centro asignado), las cajas del median cut y los
centros de Lloyd. Un contexto por tarea; sin estáticos mutables ni RNG.

**Entrada** (`ce_image`): buffer sRGB de 8 bits del llamante, no premultiplicado,
formatos `CE_RGBA8` / `CE_RGBX8` (4 B/píxel, alpha ignorada) o `CE_RGB8`
(3 B/píxel), `stride_bytes >= width·bpp`, `height·stride <= INT_MAX`, lados en
`[1, 16384]`, máscara opcional de `width·height` bytes (0..255 multiplica el
peso). Todo se valida antes de leer; nunca se lee fuera del buffer.

**Algoritmo** (`ce_palette_extract`; `ce_palette_opts_default`: `k_init` 6,
`max_iters` 20, `max_colors` 5, `max_side` 256, `center_sigma` 0.35,
`merge_de` 5.0, `min_weight` 0.05, `skin_rule` 0), determinista y sin RNG:

1. Box-downscale entero: factor `f = ceil(max(w,h)/max_side)`, media entera
   redondeada por bloque (bloques parciales del borde promedian lo que hay);
   la máscara se reduce igual.
2. Peso por píxel = gaussiana al centro (`sigma = center_sigma·min(rw,rh)` en
   píxeles de la imagen reducida; `<= 0` ⇒ 1.0 exacto) × máscara (factor
   entero 0..255; la escala global se cancela al normalizar) × regla de piel
   opcional (Chai-Ngan, YCbCr JFIF: 77 ≤ Cb ≤ 127 y 133 ≤ Cr ≤ 173 ⇒ peso 0).
3. Histograma de 5 bits por canal acumulado en `double`; el color de cada bin
   es la media ponderada sin cuantizar y su Lab sale de `ce_srgb_to_lab`. En
   modo uniforme sin máscara las sumas son enteras (≤ 255·65536 < 2⁵³) y
   exactas: el resultado es **bit-idéntico bajo barajado de píxeles**.
4. Median cut modificado (Heckbert / Leptonica `colorquant2.c`): el 85 % de
   los cortes por población y el resto por población × volumen, siempre en el
   eje más largo a partir de la mediana de población, hasta `k_init` cajas;
   centro inicial = media ponderada en Lab de cada caja.
5. Lloyd ponderado en Lab (asignación por ΔE76², empates al centro de índice
   menor, bins en orden de índice; media ponderada) ≤ `max_iters` o hasta que
   nada cambie.
6. Fusión iterativa del par de centros más próximo mientras ΔE00 < `merge_de`
   (media ponderada); descarte de centros con peso relativo < `min_weight`
   (el más pesado siempre queda).
7. Orden por peso descendente (desempate por L, a, b, índice), recorte a
   `min(max_colors, cap)` y renormalización a Σ weight = 1 (± 1e-12). `rgb` del
   swatch = Lab → sRGB8 con clamp (`ce_lab_to_srgb8`).

Si el peso total es 0 (máscara toda a 0, sigma minúscula) devuelve 1 swatch
con el color medio sin ponderar de la imagen reducida y `weight` 1. Errores:
códigos negativos de `ce_status` documentados en `ce.h` (`CE_ERR_ARG`,
`CE_ERR_CTX`, `CE_ERR_DIMS`, `CE_ERR_STRIDE`, `CE_ERR_FORMAT`, `CE_ERR_OPTS`;
`CE_ERR_NOT_IMPLEMENTED` queda reservado: desde la fase 3 no lo devuelve
ninguna función), sin escribir en la salida y sin abortar nunca. `ce_dict_nearest_color` (sin contexto) da el
índice del color del diccionario más cercano por ΔE00 (empates al índice
menor). `ce_swatch_hash` / `ce_result_hash`: FNV-1a de 64 bits sobre los bits
de (L, a, b, weight) de cada swatch; solo comparable en la misma plataforma
(los bits de libm difieren entre nativo y WASM, ver más abajo).

**CLI** (contrato fijo que consume el oráculo Python, `oracle/oracle/l2.py`):

```
ce palette <imagen.ppm> [--mask <mascara.pgm>] [--raw WxH] [--center-sigma F]
           [--max-colors N] [--min-weight F] [--merge-de F] [--k-init N]
           [--max-iters N] [--max-side N] [--skin-rule 0|1] [--json]
```

Entrada P6 binario con maxval 255 (o `.rgb` crudo de `w·h·3` bytes con
`--raw`), máscara P5 de las mismas dimensiones. `--json` escribe
`{"engine","dict_version","width","height","reduced_width","reduced_height",
"opts":{…efectivas…},"swatches":[{"rgb","hex","lab","weight"},…],"hash"}` con
`lab`/`weight` en `%.17g`, swatches por peso descendente, Σ weight = 1 y
`hash` = FNV-1a de 16 hex. Salida: 0 ok, 1 error del motor (código negativo),
2 uso o fichero inválido. El parser P6/P5 (`tools/ce_pnm.c`, fuera del target
SPM porque es entrada no confiable) admite comentarios `#` y separadores
arbitrarios, exige maxval 255 y lados en `[1, 16384]`, y rechaza cuerpos
truncados sin leer fuera del buffer; lo comparten el CLI, `test_palette` y el
fuzz loop.

**Swift.** `extractPalette(rgba:width:height:stride:options:) throws -> [Swatch]`
reserva el contexto con `ce_ctx_size()` solo durante la llamada y lanza
`ColorEngineError` (`bufferTooSmall` o `engine(code:)`); `PaletteOptions.default`
replica `ce_palette_opts_default`. Nada de lógica de color en Swift.

**Tests** (`ctest`; los mismos binarios corren en nativo, ASan/UBSan y WASM):

- `tests/test_ctx.c` (6): presupuesto ≤ 2 MiB y múltiplo de 16; rechazos de
  `ce_ctx_init` (NULL, tamaño corto, desalineado a 8); opciones por defecto;
  todos los códigos de error de `ce_palette_extract` sin escribir en la salida;
  errores de argumentos de `ce_match`/`ce_analyze`; `ce_reduced_dims`.
- `tests/test_palette.c` (14): (a) 200×200 con bloques 50/30/20 (ΔE00 mutuo
  > 15) → 3 swatches exactos, peso ± 0.02; (b) barajado de píxeles en modo
  uniforme → `memcmp` idéntico (bandas y ruido); (c) dos ejecuciones y dos
  contextos → mismo hash; (d) máscara que anula un bloque → desaparece y los
  pesos se renormalizan (0.625/0.375; máscara parcial 128 exacta); (e) 1×1, 1×N,
  N×1 y `cap` = 1; (f) RGBA/RGBX/RGB con stride mayor que el mínimo → bytes
  idénticos; (g) pesos todos 0 → 1 swatch con el color medio, sin NaN; (h)
  `ce_dict_nearest_color` a ΔE00 = 0 para los 159 colores; además downscale
  1024×1024 y 1000×700 iguales a la reducida (y redondeo de la media), regla de
  piel, fusión/descarte/recorte, parser PNM (válidos y todos los rechazos),
  fixtures PPM/PGM para los tests del CLI (`cli_palette_json`,
  `cli_palette_truncated` → exit 2) y rendimiento.
- `tests/fuzz_palette.c` (`fuzz_smoke` 2 s en ctest; `make fuzz` 600 s por
  defecto): PRNG xorshift64* con semilla; entrada (1) `ce_palette_extract` con
  dims 0..300 (y 16384 ± 1), stride a veces menor que el mínimo, formatos
  inválidos, máscaras, punteros nulos, contexto sin inicializar y opciones
  absurdas (k_init −1..64+, max_colors 0..16, sigma negativa, NaN, ±inf);
  entrada (2) `ce_pnm_parse` con cabeceras/cuerpos aleatorios, truncados o
  gigantes y ficheros válidos mutados, que luego pasan por el motor. Invariantes:
  código de error exactamente el documentado, sin escritura en `out`;
  1 ≤ n ≤ min(max_colors, cap), Σ weight = 1 ± 1e-9, pesos no crecientes, Lab
  finitos, rgb = Lab→sRGB8, determinismo cada 8 casos. Medido: 120 s bajo
  ASan/UBSan = 43 040 iteraciones por entrada (359 it/s), 0 fallos.

**Rendimiento** (1024×1024 RGBA con gradiente + ruido, opciones por defecto,
mejor de 5; cota `CE_PERF_GATE_MS` = 150 solo en nativo -O2 sin sanitizers):
2,3 ms nativo -O2 (Apple M4 Pro, clang 21), 6,1 ms con ASan/UBSan, 2,6 ms en
WASM (node 24); con `k_init` 64 y 8 colores, 6,2 ms nativo. Historial en
`BENCHLOG.md`.

## Capa 3: match contra el diccionario (`ce_match.c`)

**Score.** Para una combinación C = {c_j} (Lab de la caché del contexto) y
los swatches s_i de peso w_i (tal cual llegan: la paleta ya suma 1), bajo una
hipótesis de adaptación h aplicada a los swatches (ver «Hipótesis»):

```
score_h(C) = Σ_i w_i · min_j ΔE00(h(s_i), c_j)  +  λ · (1/|C|) · Σ_j min_i ΔE00(c_j, h(s_i))
           + exposure_penalty · |EV_h| + illuminant_penalty · [X_h ≠ D65]
score(C)   = min_h score_h(C)
```

El primer término mide cuánto se aleja cada swatch de su color más cercano de
C (ajuste); el segundo, cuánto se aleja cada color de C de su swatch más
cercano (cobertura: penaliza las combinaciones con colores que la foto no
tiene). ΔE00 es `ce_de2000_k(kL, kC, kH)`. Menor es mejor. `ce_match`
evalúa las 348 combinaciones **sin poda** bajo cada hipótesis: 8 × 159 ΔE00
por hipótesis (una vez por swatch y color, 16 KiB de pila) y después solo
mínimos y sumas; el mejor score de cada combinación se guarda en una tabla de
348 doubles y de ahí salen los `top_k` (1..`CE_MATCH_MAX_HITS` = 10) mejores
por score ascendente con **desempate por id ascendente** (comparación exacta
de doubles), y `ambiguous` = 1 si hay ≥ 2 hits y `score[1] − score[0] <
ambiguous_gap`.

**Hipótesis** (match v1, corrección de F3/F5; ADR-009). ΔE00 no es invariante
a un cambio global de exposición ni a un iluminante sin balance de blancos,
las dos degradaciones de L3 que el match v0 fallaba (exposure @1 22 %,
illuminant @3 68 %) y que ningún ajuste de kL/kC/λ/σ arreglaba (barrido en
`BENCHLOG.md`). El motor prueba un conjunto fijo de hipótesis sobre los
swatches (Lab → XYZ → transformación → Lab, todo con las funciones del motor):
la **identidad** (siempre, y evaluada la primera: gana los empates);
**exposición** g = 2^EV en XYZ lineal con EV = k · 0,5 y |EV| ≤
`exposure_ev_max` (1,0 ⇒ −1, −0,5, +0,5, +1 EV); **iluminante** «la foto se
tomó bajo A, D50, D75 o F2 sin balance de blancos», es decir, Bradford X → D65
(`illuminant_search` = 1); y sus combinaciones (5 × 5 = 25 hipótesis por
defecto). Cada hipótesis suma una penalización lineal (2,0 ΔE por EV, 2,0 ΔE
por iluminante ≠ D65) para que una foto limpia siga ganando con la identidad.
Con `exposure_ev_max` = 0 e `illuminant_search` = 0 el score es **bit a bit**
el de la fase 3 (match v0), que el scorecard conserva como columna informativa
`noadapt`. Los iluminantes hipotéticos son los estándar CIE del motor y
coinciden con los que usa el generador de L3 (A, F2, D75): la mejora en
`illuminant` es en parte tautológica y la prueba real es L4 (fotos); el barrido
con rejillas que **no** contienen ±1 EV ni F2/D75 (`BENCHLOG.md`) sigue
pasando los umbrales, así que el mecanismo no está ajustado a los parámetros
exactos del generador.

**Opciones** (`ce_match_opts_default`: kL 1, kC 1, kH 1, `coverage_lambda`
1.0, `ambiguous_gap` 1.0, `exposure_ev_max` 1.0, `exposure_penalty` 2.0,
`illuminant_search` 1, `illuminant_penalty` 2.0). Las opciones reales deben
ser finitas (NaN o ±inf ⇒ `CE_ERR_OPTS`); λ < 0, `exposure_ev_max` fuera de
[0, `CE_MATCH_EV_MAX_LIMIT` = 4], penalización < 0 o `illuminant_search` ∉
{0, 1} ⇒ `CE_ERR_OPTS`; kL/kC/kH ≤ 0 se tratan como 1.0 (como
`ce_de2000_k`); gap ≤ 0 ⇒ nunca ambiguo. Swatches: Lab finito y peso finito
≥ 0 (si no, `CE_ERR_ARG`); `n` en 1..8 y `top_k` en 1..10 (`CE_ERR_ARG`);
contexto sin `ce_ctx_init` ⇒ `CE_ERR_CTX`. Ningún error escribe en las
salidas. Propiedades: score ≥ 0 y finito; con λ = 0 todas las combinaciones
que contienen exactamente un swatch empatan a 0 y gana la de **menor id**, no
la más pequeña (en el Vol. 1 coinciden para todos los colores, pero es una
propiedad del desempate, no del score).

**`ce_analyze`** = `ce_palette_extract` (cap 8) + `ce_match` (top 10) en el
mismo contexto; valida las opciones de match antes de extraer, así que ningún
error escribe en `out`; en éxito rellena `ce_result` por completo (posiciones
no usadas a cero, campos escritos uno a uno: el resultado es comparable byte a
byte) y devuelve `n_hits`. `ce_result_hash`: FNV-1a 64 de los bits de
(L, a, b, weight) de los swatches, (combo_id, score) de los hits y
`ambiguous`; solo determinismo run-a-run en la misma plataforma.

**Paridad nativo/WASM.** Desde la fase 5 el motor lleva su propia libm
(`ce_libm.c`), así que Lab, scores, `ambiguous` y `hash` son **bit a bit
idénticos** en nativo y WASM: sobre las 20 fixtures de `make parity` la
salida JSON de `ce match` es byte a byte la misma en las dos plataformas
(|Δ| = 0 en Lab, pesos y scores; hash igual en 20/20), ver la sección
«Paridad nativo/WASM» más abajo. El contrato de 1e-9 se mantiene como
tolerancia de respaldo para otras plataformas.

**CLI** (contrato fijo que consume `oracle/tests/test_l3_match.py`):

```
ce match <imagen.ppm> [opciones de palette: --mask, --raw, --center-sigma, --max-colors,
         --min-weight, --merge-de, --k-init, --max-iters, --max-side, --skin-rule]
         [--top K] [--kL F] [--kC F] [--kH F] [--coverage-lambda F] [--ambiguous-gap F]
         [--exposure-ev-max F] [--exposure-penalty F] [--illuminant-search 0|1]
         [--illuminant-penalty F] [--json]
ce analyze ...            alias exacto (misma salida byte a byte)
ce batch <lista.txt> [mismas opciones] [--json]
```

`--json` escribe `{"engine","dict_version","file","width","height",
"reduced_width","reduced_height","opts":{"palette":{…},"match":{kL, kC, kH,
coverage_lambda, ambiguous_gap, exposure_ev_max, exposure_penalty,
illuminant_search, illuminant_penalty, "top":K}},
"swatches":[…como ce palette…],"hits":[{"id","score","size","colors":[…]}…],
"ambiguous":0|1,"hash"}` con scores en `%.17g`; `--top K` en 1..10 (defecto
3) y `hash` = `ce_result_hash` del resultado truncado a los K hits impresos
(así `--top 3` y `--top 10` dan hashes distintos; el wrapper Swift calcula el
mismo hash con su `topK`). `ce batch` lee una ruta por línea (vacías, `#` y
CR ignorados) y escribe una línea JSON por imagen (JSONL) con los mismos
campos; un fichero ilegible o un error del motor produce
`{"file":…,"error":…}` y el proceso continúa; `--mask`/`--raw` se aplican a
todas. Salida: 0 ok, 1 error del motor (en batch: si alguna imagen falló), 2
uso o fichero inválido (en batch, solo la lista). Sin `--json`: tabla de
swatches, hits con tamaño y colores, y `ambiguous`.

**Swift.** `analyze(rgba:width:height:stride:paletteOptions:matchOptions:topK:)
throws -> AnalysisResult` (`swatches`, `hits: [Hit]`, `ambiguous`, `hash`
con `n_hits = topK`); `MatchOptions.default` replica `ce_match_opts_default`;
`topK` fuera de 1...10 lanza `.engine(code: CE_ERR_ARG)`. Accesores del
diccionario sin lógica (`dictionaryVersion`, `dictionaryComboCount`,
`dictionaryCombo(id:)`, `dictionaryColorRGB/Lab/Name(index:)`).

**Tests** (`tests/test_match.c`, 8; en nativo, ASan/UBSan y WASM):

1. Recall exacto: 348 imágenes 120×120 de bandas verticales con proporciones
   iguales de los colores sRGB8 exactos de cada combinación → `ce_analyze`
   (uniforme) da `hits[0].id == id` en **348/348**, la paleta recupera todos
   los colores (348/348; el ΔE00 intra-combinación mínimo es 5,16 > `merge_de`
   5 y ningún par comparte bin de 5 bits), **0 ambiguas** con gap 1.0 (0 con
   0.5 y 2.0; 2 con 5.0), gap mínimo top-1/top-2 = 4,38. Score 0 exacto en
   206/348 (WASM: 195/348); el resto ≤ 1,6e-14 por el redondeo de la media
   ponderada de Lloyd (`(w·L)/w`), no por el match.
1b. Hipótesis de adaptación (`test_adaptation_hypotheses`): las 348 paletas
   exactas degradadas como en L3 (−1 EV, +1 EV, iluminante A, F2, D75 y
   A − 0,5 EV, con `ce_bradford_matrix` D65 → X y ganancia en XYZ) → con las
   hipótesis por defecto recall@1 **348/348 en los seis casos**; con la
   búsqueda apagada (match v0) 102, 150, 27, 234, 348 y 26; el mejor score
   con hipótesis nunca es mayor que sin ellas (mínimo sobre un
   superconjunto). `test_adaptation_opts_validation`: NaN, negativos,
   `exposure_ev_max` > 4 e `illuminant_search` ∉ {0, 1} ⇒ `CE_ERR_OPTS` sin
   escribir; rejilla máxima (17 ganancias × 5 iluminantes) con penalizaciones
   0 sigue dando score 0 e id correcto a la paleta exacta; con la búsqueda
   apagada las penalizaciones no influyen.
2. Paletas exactas (`ce_dict_color_lab`, pesos iguales): score **0 exacto** y
   `hits[0].id == id` en 348/348; segundo score mínimo 4,38 (no hay conjuntos
   de colores duplicados). Empate artificial: λ = 0 y un swatch igual al color
   158 (presente en 23 combinaciones) → los 10 hits puntúan 0 exacto y salen
   por id ascendente; prefijos idénticos con `top_k` 1 y 2.
3. Propiedades: 60 paletas aleatorias (LCG del test) → score ≥ 0 finito, orden
   total, determinismo bit a bit, kL/kC/kH ≤ 0 ≡ 1.0, kL = 2 y λ = 0 no suben
   el mejor score; todos los errores (`ARG`, `CTX`, `OPTS`, NaN/±inf en cada
   opción, λ < 0, swatch no finito o peso negativo, `top_k` 0/11, `n` 0/9) sin
   escribir en `out` ni en `ambiguous`; semántica del gap (0, negativo, 1e9,
   igual a la diferencia ⇒ no ambiguo; un hit ⇒ nunca).
4. `ce_result_hash`: dos análisis idénticos (mismo y distinto contexto) →
   `memcmp` idéntico y mismo hash; otra imagen → otro hash; truncar `n_hits`
   cambia el hash.
5. Rendimiento (cotas solo en nativo -O2): `MATCH_MS` < 2 y
   `ANALYZE_1024_MS` < 10 (ver abajo).
6. Fixtures `match_{1,100,348}.ppm` y `batch_list.txt` (3 rutas + una
   inexistente + vacía + comentario) para los tests del CLI: `cli_match_json`,
   `cli_analyze_alias` (`cmp`), `cli_match_missing_file` (exit 2),
   `cli_batch_jsonl` (exit 1, 4 líneas, 1 `error`, 3 `hash`) y
   `cli_match_contract` (`tests/cli_match_check.js` con node: claves y orden
   exactos del contrato, tipos, rangos, pesos, orden de hits, `--top`, alias,
   determinismo, códigos 1/2, JSONL del batch, hash batch == hash match,
   opciones de hipótesis propagadas y validadas; desde las máscaras, `"mask"`
   en las líneas del batch; 413 comprobaciones).

**Rendimiento** (Apple M4 Pro; `make bench-match`): con las 25 hipótesis por
defecto `MATCH_MS` = 1,23 ms nativo -O2 (5 swatches × 348 combinaciones,
mejor de 200; media 1,32), 2,09 ms con ASan/UBSan, 1,49 ms en WASM (cota
`CE_MATCH_GATE_MS` = 5 en nativo); `ANALYZE_1024_MS` = 3,8 ms nativo, 8,6 ms
ASan, 4,4 ms WASM (cota 10 ms). El match v0 (una hipótesis) costaba 0,047 ms
nativo con `ce_libm.c` (0,034 con la libm de Apple). Historial en
`BENCHLOG.md`.

## Máscaras: regiones de ropa y piel (`ce_mask.c`)

Requisito del usuario tras la primera build en su iPhone: fotos con varias
personas, fondo sucio y piel meten error. La plataforma (Vision en iOS,
MediaPipe en la web) aporta **máscara de instancia de la persona, puntos de la
pose y muestra de piel de la cara**; la geometría y la estadística viven en el
motor para que iOS y WASM den los mismos bits. Todas las máscaras son
`width × height` bytes sin stride (0..255); ninguna función reserva memoria ni
modifica la máscara cuando devuelve un error.

**Regiones de ropa** (`ce_mask_clothing_regions`, opciones `ce_region_opts`):
la máscara sale con `min(máscara, región)`, evaluando cada píxel en su centro
`(x + 0.5, y + 0.5)` sin antialiasing:

```
región(p) = lado(p) ∧ ¬mano(p) ∧ (torso(p) ∨ cápsulas(p))
```

| Pieza | Regla exacta |
|---|---|
| Puntos | Un punto cuenta si `confidence` es finita, > 0 y ≥ `min_confidence` (0,3) y `x`, `y` son finitos con \|x\|, \|y\| ≤ `CE_POSE_COORD_MAX` (2^20). |
| Simetría | Si falta un solo hombro: `S = 2·NECK − S_otro`; si falta una sola cadera: `H = 2·ROOT − H_otra` (Vision define cuello y raíz como puntos medios). Sin el punto de simetría o con los dos ausentes: `CE_ERR_POSE` (−8). También `CE_ERR_POSE` si el ancho de hombros `sw` < 1 px o el punto medio de las caderas cae sobre la recta de los hombros. |
| `lado` | Semiplano de la recta hombro–hombro que contiene las caderas (inclusivo): nada por encima de la línea de hombros (cabeza, brazos levantados). |
| `torso` | Distancia a la envolvente convexa de {LS, RS, RH, LH} ≤ `torso_margin·sw` (0,12). |
| `cápsulas` | Distancia al segmento ≤ `limb_width·sw/2` (ancho total 0,45·sw) para hombro→codo (`include_upper_arms` 1), codo→muñeca (`include_forearms` 0), cadera→rodilla (`include_legs` 1), rodilla→tobillo (`include_lower_legs` 1), si existen los dos extremos. |
| `mano` | Siempre excluida para cada muñeca presente: cápsula desde la muñeca hasta muñeca + 0,45·sw en la dirección codo→muñeca con radio 0,2·sw (sin codo, disco de radio 0,45·sw). Antropometría: la mano mide ~0,47·sw. |

Todo se calcula relativo a un punto (`p − A`, `B − A`) con +, −, ×, ÷ y sqrt en
orden fijo (sin funciones trascendentes): con coordenadas cuyas operaciones son
exactas (p. ej. múltiplos de 1/4) el resultado es exactamente invariante a
espejo horizontal con L/R intercambiados y a traslaciones enteras; con
coordenadas arbitrarias solo pueden cambiar píxeles a ~1e-12 px de un borde.
Devuelve los píxeles > 0 resultantes. `ce_mask_cut_head` es el fallback sin
pose: anula las `floor(fraction·H + 0.5)` filas superiores del bbox (fraction
en [0, 0,5]); máscara vacía → 0.

**Piel adaptativa** (`ce_skin_model_fit`, `ce_mask_exclude_skin`): no hay regla
de color fija (la YCbCr de Chai y Ngan borra camel, beige y salmón, colores de
Wada: en L3 bajó el recall@1 de 97 % a 66 %). El modelo es una gaussiana en
CIELAB ajustada a la muestra de la cara de cada persona (píxeles con muestra ≥
128, al menos `CE_SKIN_MIN_SAMPLES` = 50, si no `CE_ERR_SKIN_SAMPLES` (−9)):
media y covarianza poblacional en dos pasadas en orden de índice, **regularizada
con ε = 1 (unidades Lab²) en la diagonal** (`CE_SKIN_COV_EPSILON`: suelo de 1
ΔE*ab de desviación típica; una muestra plana sigue siendo invertible) e
invertida por adjuntos. `ce_mask_exclude_skin` pone a 0 los píxeles de la
máscara con distancia de Mahalanobis ≤ `max_mahalanobis` (2,5); **si fuera a
excluir más de `max_excluded_fraction` (35 %) de la máscara no toca nada y
devuelve `CE_SKIN_GUARD` (1)**: una prenda parecida a la piel no se borra. El
modelo se valida (valores finitos, n ≥ 50, parte simétrica de `inv_cov` definida
positiva por Sylvester) antes de tocar la máscara. El Lab de cada píxel es
bit a bit el de `ce_srgb8_to_lab`, calculado con una tabla por canal de
`ce_srgb8_to_xyz` (`ce_srgb8_xyz_table`, 18 KiB de pila) que ahorra las tres
potencias por píxel; `test_mask` lo comprueba en los 16 777 216 colores.

Medido en `test_mask` (cara, brazos desnudos y torso con ruido ±4 por canal):

| Piel | Brazos eliminados | Prenda roja | Azul marino | Beige (228,192,150), ΔE00 6,09 de la piel clara |
|---|---:|---:|---:|---:|
| clara (236,198,172) | 100 % | 0 % | 0 % | 0 % |
| media (198,145,110) | 100 % | 0 % | 0 % | 0 % |
| oscura (110,72,50) | 100 % | 0 % | 0 % | 0 % |

Con el torso entero del color de la piel salta la salvaguarda (máscara intacta).
Aviso honesto: con ruido ±4 la covarianza es estrecha y la beige queda lejos
(~4 desviaciones); una cara real con sombras tiene más varianza, el elipsoide
crece y una prenda a ΔE00 ~6 puede caer parcialmente: eso lo mide la capa 4.

**Tiempos** (Apple M4 Pro, nativo -O2, `test_mask`, sin cota): regiones en
1024×2048 con máscara llena 28 ms; ajuste del modelo 1,8 ms; exclusión de piel
en 1024×1024 con máscara llena y dos pasadas completas 42 ms (158 ms antes de
la tabla por canal).

**CLI**:

```
ce regions --size WxH --mask persona.pgm --pose pose.txt --out ropa.pgm \
           [--min-confidence F] [--torso-margin F] [--limb-width F] \
           [--upper-arms 0|1] [--forearms 0|1] [--legs 0|1] [--lower-legs 0|1]
    # pose.txt: 15 líneas "x y confidence" en el orden de ce_joint ('#' y vacías ignoradas)
    # stdout {"pixels", "mask_pixels"}; CE_ERR_POSE -> exit 1 sin escribir --out
ce skin --image foto.ppm --sample cara.pgm --mask ropa.pgm --out sin_piel.pgm \
        [--max-mahalanobis F] [--max-excluded F]
    # stdout {"excluded", "guard", "mask_pixels", "candidates", "model": {n, mean, cov, inv_cov}}
ce cut-head --mask persona.pgm --fraction 0.2 --out sin_cabeza.pgm   # {"pixels"}
ce batch lista.txt --json
    # cada línea: imagen.ppm [mascara.pgm] (espacio o tabulador; rutas con espacios
    # entre comillas dobles); la máscara de la línea gana a --mask; JSONL con
    # "mask": ruta|null tras "file"; una entrada ilegible da {"file","mask","error"}
```

**Tests** (`tests/test_mask.c`, nativo, ASan/UBSan y WASM): (1) pose de frente
200×400: nada por encima de los hombros ni en discos de 0,15·sw alrededor de
las muñecas, torso y muslos dentro, recuento igual a un **rasterizador de
referencia independiente** del propio test (envolvente de Andrew, distancias
con sqrt y vector unitario, normal orientada) y a los dorados 26 012 (por
defecto), 28 090 (con antebrazos) y 7 680 (solo torso sin margen = área exacta
del trapecio); (2) espejo y traslación de 7 px exactos, escala ×2 → ×3,9999;
(3) `CE_ERR_POSE` con máscara intacta, simetría de cadera y hombro idéntica al
punto real, confianza bajo el umbral, coordenadas no finitas, pose degenerada,
`CE_ERR_ARG`; (4) `ce_mask_cut_head`; (5) piel en tres tonos (tabla de arriba),
salvaguarda, < 50 muestras, modelos degenerados; tabla Lab exhaustiva; (6)
determinismo y `MASK_HASH` = `36160cbd7630fb2b` igual en nativo, ASan y WASM.
Fuzz (`make fuzz`): entradas 3 (regiones y recorte con poses NaN/±inf/fuera de
imagen/confianzas absurdas, dims 0..512) y 4 (piel con covarianza singular o
indefinida, n pequeño, valores enormes). CLI: `cli_batch_masks`, `cli_regions`,
`cli_skin`, `cli_debug_dir` y `cli_mask_contract` (`tests/cli_mask_check.js`,
node: CLI == API byte a byte).

**Swift** (`ColorEngine.swift`): `Joint`, `Keypoint`, `Pose`, `RegionOptions.default`,
`clothingRegions(pose:options:mask:width:height:)`, `cutHead(mask:width:height:fraction:)`,
`SkinModel`, `SkinOptions.default`, `fitSkinModel(rgba:width:height:stride:sampleMask:)`,
`excludeSkin(rgba:width:height:stride:model:options:mask:)` y las constantes
`ColorEngineError.poseMissing` / `.tooFewSkinSamples` (no son casos nuevos del
enum: los `switch` exhaustivos de la app siguen compilando).

## Capas de depuración (`ce_debug.c`, `--debug-dir`)

Requisito del usuario: «The colors are not right. It will be helpful for me to
see the layers from which the color is being extracted». Cada etapa del motor
se puede ver como una capa, en la app (un único análisis y un único `ce_ctx`)
y desde la línea de comandos. `ce_palette_extract` rellena, con contabilidad
paralela de enteros y copias que no toca ninguna operación de coma flotante
(`golden-check` 20/20 + 50/50 en verde y 280 salidas de `ce match/palette`
byte a byte iguales a las de HEAD; `make parity` sin cambios), un estado de depuración en el contexto
(`ce_ctx_size()` pasa de 2 044 176 a 2 047 936 B, ≤ 2 MiB):

| Capa | API C | Qué muestra |
|---|---|---|
| Imagen reducida | `ce_debug_reduced_rgb` | Lo que ve el clustering tras el box-downscale (≤ 256 px). |
| Peso por píxel | `ce_debug_weight_map` | máscara × gaussiana al centro × regla de piel, escalado al máximo: `floor(w/w_max·255 + 0.5)`. |
| Swatch por píxel | `ce_debug_label_map` | Píxel → bin del histograma → centro de Lloyd → grupo de fusión → índice del swatch final; `CE_LABEL_NONE` (255) si su peso es 0, `CE_LABEL_DISCARDED` (254) si su cluster se descartó o se recortó. |
| Cluster por píxel | `ce_debug_cluster_map` (extensión) | Cluster de Lloyd antes de fusionar (`CE_LABEL_NONE` si peso 0). |
| Clusters | `ce_palette_debug_info` | Lab/rgb/peso de cada cluster de Lloyd, `fate` (0 conservado, 1 fusionado en `final_index`, 2 descartado por `min_weight`, 3 recortado por `max_colors`/cap — extensión), `group_head` (extensión), iteraciones de Lloyd, peso total, fracción de peso 0, sigma usada. |
| Por qué ganó | `ce_match_explain_combo` | Para una combinación: `score` bit a bit igual al de `ce_match` y `fit_term + coverage_term + hypothesis_penalty == score`; EV e iluminante de la hipótesis ganadora; por swatch, su color más cercano de la combinación y ΔE00; por color, su swatch más cercano y ΔE00. |

`CE_ERR_CTX` si el contexto no tiene una extracción válida (recién iniciado o
tras una llamada fallida: cualquier `ce_palette_extract` o `ce_analyze`
invalida el estado anterior); `CE_ERR_ARG` con buffers nulos o cortos, sin
escribir.

**CLI**: `ce palette|match|analyze <imagen> [opciones] --debug-dir DIR` deja
stdout idéntico y escribe en `DIR` (lo crea): `reduced.ppm`, `weights.pgm`,
`labels.pgm` (índices crudos), `labels.ppm` (color de su swatch; NONE negro,
DISCARDED gris 128), `clusters.pgm`/`clusters.ppm`, `swatch_<k>.pgm` (255
donde el píxel alimenta el swatch k), `mask.pgm` (máscara reducida con la
misma caja entera que el motor, solo con `--mask`) y `debug.json`
(`palette_debug` con cada cluster y su destino y recuento de píxeles, swatches
con píxeles, recuentos NONE/DISCARDED, opciones y, en match, los hits y la
explicación de los top-K con `score_equals_match`). Ejemplo:

```
build/tools/ce match foto.ppm --mask ropa.pgm --top 3 --json --debug-dir out/capas
```

**Swift**: `paletteDebugLayers(rgba:width:height:stride:paletteOptions:matchOptions:topK:mask:)`
devuelve `PaletteDebugLayers` (`analysis` idéntico a `analyze`, `debug:
PaletteDebug` con `clusters: [ClusterDebug]`, `reducedRGB`, `weightMap`,
`labelMap`, `clusterMap` y `explanations: [MatchExplanation]` de los hits), y
`explainMatch(swatches:options:comboId:)` explica una combinación cualquiera.
Constantes `paletteLabelNone` / `paletteLabelDiscarded`.

**Tests** (`tests/test_debug.c`, nativo, ASan y WASM): composición 200×200 de
tres bloques + magenta 6×6 con un cuarto enmascarado (label map exacto, NONE,
DISCARDED, fate 2, `zero_weight_fraction` 0,25); dos rojos en bins distintos
fusionados (fate 1, `final_index` del rojo); recorte a 2 colores (fate 3);
Σ weight_map por etiqueta = peso del swatch ±0,01 también con gaussiana y
reducción; explicación bit a bit en el top-10 con opciones por defecto, match
v0 y 20 paletas aleatorias con kL 2 y λ 0,5; errores; `DEBUG_LAYERS_HASH` =
`60b15a4bf131c4bf` igual en nativo, ASan y WASM. `make parity` ejecuta además
`tests/layers_parity.js`: `--debug-dir` de las 20 fixtures y `regions`/`skin`/
`cut-head`/`match --mask` sintéticos (coordenadas no diádicas) byte a byte
iguales en nativo y WASM.

## Paridad nativo/WASM (`make parity`, fase 5)

`make parity` compila solo el target `ce` en `build/` (clang) y en `build-wasm/`
(`emcmake`, las mismas flags que `make test-wasm`) y ejecuta
`harness/wasm/run_parity.js` (node) sobre las 20 fixtures de
`harness/wasm/fixtures/`: PPM ≤ 128 px generadas de forma determinista por
`harness/wasm/make_fixtures.py` (`uv`; `make parity-fixtures` las regenera y
comprueba con `--check` que los sha256 no cambian; el script verifica el
sha256 de cada PPM contra `manifest.json` antes de ejecutar nada y sale con 2
si no cuadran). Para cada fixture lanza `ce match <ppm> --json --top 3 [args
del manifest]` en las dos plataformas (mismo cwd y misma ruta relativa, así el
campo `file` coincide) y exige: mismo número de swatches con |ΔL|, |Δa|, |Δb|
y |Δweight| ≤ 1e-9; mismos ids del top-3 en el mismo orden con |Δscore| ≤
1e-9; mismo `ambiguous`; y, con dos ejecuciones por lado, salida byte a byte
idéntica (determinismo run-a-run). `rgb`, los hits 4..K (`PARITY_TOP=10`) y
`hash` se comparan solo a título informativo. Escribe `harness/out/parity.json`
y sale con 1 si algo difiere.

Fixtures (cabecera de `make_fixtures.py`): gris uniforme; rampa de grises
128×40; un solo color del diccionario (Black, en 23 combinaciones) con
`--coverage-lambda 0` (23 empates a 0 → orden por id, idéntico en ambas); los
tres pares casi indistinguibles del diccionario, que la paleta fusiona
(Isabella Color/Maple ΔE00 2,68; Peacock Blue/Green Blue 1,01; Carmine
Red/Pompeian Red 1,80, este con `--ambiguous-gap 30`); combinaciones exactas
en franjas (`--center-sigma 0`), anidado, L y elipses (`--kL 2`); ruido
gaussiano; colores fuera del diccionario (`synth.compose`); textura,
iluminante A, JPEG y distractor de `wada_gen`; primarios sRGB puros; casi
negro/casi blanco 64×64; y 3×2 píxeles con 6 colores.

**Resultado medido (2026-09-15; Apple M4 Pro, clang 21 / emcc 6.0.9 + node
24.21) con `ce_libm.c`: 20/20 fixtures bit-exactas.** La salida JSON de
`ce match --json --top 3` es byte a byte idéntica en las dos plataformas en
las 20 fixtures (también con `PARITY_TOP=10`): 61 swatches con Lab, peso y
rgb idénticos (183/183 componentes Lab bit-idénticas), 60 hits con el mismo
id y el mismo score bit a bit, mismo `ambiguous` (1 en 5 fixtures con el
match v1), `hash` igual en 20/20, determinismo run-a-run en ambos lados.
`run_parity.js` exige ahora esa bit-exactitud además del contrato de 1e-9
(`--no-bitexact` la rebaja a informativo para diagnosticar una plataforma
nueva); `make parity` sale 0 en ~5 s con las builds calientes.

| Magnitud | máx. medido | contrato |
|---|---|---|
| ΔL / Δa / Δb / Δweight | 0 / 0 / 0 / 0 | 1e-9 |
| Δscore (hits 1..10) | 0 | 1e-9 |
| salida JSON nativo vs WASM | idéntica 20/20 | idéntica (bit-exactitud) |
| `hash` | igual 20/20 | igual |

**Historia (mismo día, antes de `ce_libm.c`).** Con la libm del sistema, 19/20
fixtures quedaban a ≤ 4,1e-14 en scores pero `p02_gray_ramp_128x40` llegaba
a 2,4e-8 (hits 4..10: 9,3e-8), con el mismo orden y el mismo `ambiguous`. La
causa, verificada: un swatch gris salía con `a = b = 0` exactos en nativo y
`a = 2,1e-14, b = −8,3e-15` en WASM (cbrt/pow de musl frente a la libm de
Apple), y CIEDE2000 no es Lipschitz en C' = 0 (ΔH' y el término R_T crecen
como √C', h' = atan2(b, a) es arbitrario; medido ΔE(a) − ΔE(0) ≈ 3,6e-3·√a,
idéntico en ambas plataformas para la misma entrada). Ninguna decisión
cambiaba (gap mínimo entre hits 3,9e-3), pero el contrato de 1e-9 se rompía.
La solución adoptada es la prevista en PLAN §5 y ADR-003: `ce_libm.c` con las
seis funciones trascendentes de musl compiladas con el motor (sin FMA), que
elimina la diferencia de raíz en lugar de añadir una tolerancia en ΔE00. La
alternativa barata descartada (regla de Sharma con tolerancia, C' < ε ⇒
h' = 0) habría dejado el `hash` distinto por plataforma y una discontinuidad
de hasta ~1e-2 ΔE en C' = ε para tonos azules.

## Tests (`tests/test_math.c`, Unity)

0. libm portable (fase 5): `test_libm_special_values`, `test_libm_vs_system`
   (≤ 2 ulp frente a la libm del sistema) y `test_libm_golden_hash`
   (`HASH_LIBM` igual en nativo, ASan y WASM); ver «Determinismo nativo vs WASM».
1. Los 34 pares de Sharma, Wu y Dalal (`tests/data/ciede2000testdata.txt`),
   tolerancia 1e-4, en ambos órdenes.
2. Blanco (255,255,255) → L = 100, a = b = 0 (±1e-9); negro → 0 (±1e-12).
3. `golden_lab.tsv` (2271 filas), `golden_de2000.tsv` (2010), `golden_bradford.tsv`
   (80): |Δ| ≤ 1e-9 frente al oráculo estricto. Error medido: 1.1e-13, 1.4e-13
   y 1.1e-15 respectivamente.
4. Matriz Bradford D65→D50 igual al ejemplo de colour-science a 1e-7.
5. Round-trip exhaustivo: los 16 777 216 colores sRGB8 → Lab → sRGB8 devuelven
   el mismo triple. Tiempos medidos: 1.1 s nativo -O2, 1.3 s con ASan/UBSan,
   1.8 s en WASM (node), así que también en WASM se recorren todos.
6. Propiedades de ΔE00: ΔE(x,x) = 0, ΔE ≥ 0, simetría bit a bit en 1000 pares
   generados con un LCG propio.
7. Al final imprime `HASH_GOLDEN_BITS` (FNV-1a de los bytes de los doubles) y
   `HASH_GOLDEN_TEXT` (FNV-1a de las salidas formateadas con `%.15e`) para
   comparar plataformas.

El oráculo (`oracle/oracle/reference.py`) se valida a sí mismo con
`oracle/tests/test_reference.py` (34 pares de Sharma, blanco, Bradford).

## Decisiones numéricas

**Matriz derivada, no la de la norma.** La matriz RGB→XYZ se deriva de los
primarios sRGB (0.64,0.33), (0.30,0.60), (0.15,0.06) y del blanco D65
xy (0.3127, 0.3290), tal como la calcula colour-science con
`use_derived_matrix_RGB_to_XYZ=True`; los 9 coeficientes y su inversa están
incrustados en `ce_math.c` con 17 dígitos (`repr`). Con la matriz de cuatro
decimales de IEC 61966-2-1 el blanco no cae en L = 100, a = b = 0. El blanco de
referencia del Lab se calcula como colour (`Xn = x/y`, `Yn = 1`,
`Zn = (1-(x+y))/y`).

**Constantes CIELAB exactas.** ε = 216/24389 y κ = 24389/27 (no 0.008856 y
7.787), y la inversa usa L directamente para Y.

**CIEDE2000 según Sharma 2005.** h' con `atan2` llevado a [0, 360) y h' = 0 si
a' = b = 0; ΔC' y ΔH' con signo; Δh' = 0 si C1'C2' = 0 y ±360 cuando
|h2'−h1'| > 180; h̄' con los tres casos (suma, +360, −360). x⁷ se calcula por
multiplicaciones, no con `pow`. Se replica el orden de operaciones de colour
(grados con `x·(180/π)`, etc.) para quedar a ~1e-13 del oráculo.

**Iluminantes** xy de CIE 015:2004 (observador 2°), los mismos que colour.
La matriz de Bradford es `inv(CAT)·diag(RGB_dst/RGB_src)·CAT`, con la inversa
3×3 por adjunta. Nota: con estos blancos D65→D50 tiene `m[2][2] = 0.7518742`
(ejemplo de colour); el valor 0.7521316 que circula (Lindbloom) usa blancos
redondeados distintos (0.95047/1.08883, 0.96422/0.82521).

**Sin contracción FMA.** Cada `.c` lleva `#pragma STDC FP_CONTRACT OFF` tras
los includes y CMake añade `-ffp-contract=off`. Apple clang contrae `a*b+c` en
`fmadd` por defecto en arm64 y WASM no tiene FMA: sin el pragma, iOS y web
darían bits distintos. El paquete Swift no usa `unsafeFlags` (haría el paquete
inelegible como dependencia): basta el pragma, verificado con `objdump` sobre
el objeto compilado por SPM (0 instrucciones `fmadd`). Prohibido `-ffast-math`,
`-Ofast` y `-ffp-contract=fast`: ignoran el pragma.

## Determinismo nativo vs WASM (libm)

Las operaciones IEEE básicas (+, −, ×, ÷, √) son bit-exactas entre Apple
arm64 y WASM. Las trascendentes de libm no: Apple usa su libm y Emscripten la
de musl, y `pow`, `cbrt`, `atan2`, `sin`, `cos`, `exp` no están correctamente
redondeadas. Antes de la fase 5 eso hacía diferir los hashes:

| Plataforma (libm del sistema) | HASH_GOLDEN_BITS   | HASH_GOLDEN_TEXT   |
|-------------------|--------------------|--------------------|
| macOS arm64 (clang 21) | `2b22878a87a359cf` | `ea2f38eac978c4a1` |
| WASM (emcc 6.0.9, node 24) | `664d767f2bc729c6` | `7ef2cb24832fc966` |

Magnitud medida entonces con el CLI en ambas plataformas (golden y 200 000
colores / 50 000 pares aleatorios): Lab ~30 % de filas con algún bit distinto,
|Δ| máx 1,2e-13; ΔE00 ~10 % de pares, |Δ| máx 3,1e-13; Bradford 0 diferencias
(solo +, ×, ÷); ambas a ≤ 2,6e-13 del oráculo Python.

**Desde la fase 5 el motor lleva su propia libm** (`ce_libm.c`): `ce_cbrt`,
`ce_pow`, `ce_exp`, `ce_atan2`, `ce_sin` y `ce_cos` son copias de musl 1.2.6
(la de Emscripten 6.0.9; ficheros y sha256 en la cabecera del `.c`) con dos
cambios: el camino con FMA de `pow` (`__FP_FAST_FMA`, que Apple clang
activaría en arm64) queda fijado al camino sin FMA (el que ejecuta WASM), y
`double_t` es `double` (`_Static_assert(FLT_EVAL_METHOD == 0)`). Solo usan
+, −, ×, ÷, `sqrt`, `floor` y bits IEEE 754, así que con FP_CONTRACT OFF
producen los mismos bits en cualquier plataforma; de `<math.h>` el motor solo
conserva `sqrt`, `fabs`, `floor` e `isfinite`/`isnan`. Resultado: Lab, ΔE00,
pesos de la gaussiana, scores y hashes idénticos en nativo y WASM
(`HASH_GOLDEN_BITS` = `664d767f2bc729c6` en las dos: el valor que antes daba
solo WASM). Precisión: < 1 ulp por construcción (pow/exp 0,54 ulp, cbrt 0,67
ulp); frente a la libm de Apple, máximo 1 ulp en las seis funciones y
16 838/18 000 resultados idénticos (`test_libm_vs_system`, cota 2 ulp); en
WASM 18 000/18 000 idénticos a la musl del sistema. `test_libm_golden_hash`
gatea un FNV-1a de los bits de las seis funciones sobre 18 000 casos
(`HASH_LIBM` = `e2a522f84cbcb366`) que debe salir igual en nativo, ASan y
WASM; `test_libm_special_values` cubre NaN, ±inf, ±0, subnormales, los
resultados exactamente representables (2^10, cbrt(27), exp(0)…) y la
reducción de argumento grande (sin(1e22)). Coste: paleta 1024² 2,27 → 2,70 ms,
match v0 0,034 → 0,047 ms (`BENCHLOG.md`).

Tolerancia de respaldo: **1e-9** absoluto en Lab, ΔE00 y XYZ frente a los
golden (el oráculo Python usa la libm de numpy: acuerdo medido ~1e-13), y el
round-trip 8 bits es exacto en ambas plataformas. Las decisiones de las capas
superiores (argmin de ΔE00 sobre el diccionario) siguen desempatando por
índice.

## Layout

```
engine/
  Package.swift                       Swift Package (CColorEngine + ColorEngine + tests)
  CMakeLists.txt                      librería estática, CLI, tests (nativo y Emscripten)
  Sources/CColorEngine/ce_math.c      capa 1: sRGB/XYZ/Lab, ΔE, Bradford
  Sources/CColorEngine/ce_dict.c      diccionario de Wada (tablas static const)
  Sources/CColorEngine/ce_dict_data.h generado por `make dict`
  Sources/CColorEngine/ce_ctx.c       capa 2: contexto (ce_ctx_size / ce_ctx_init)
  Sources/CColorEngine/ce_image.c     capa 2: validación, box-downscale, pesos
  Sources/CColorEngine/ce_palette.c   capa 2: histograma, MMCQ, Lloyd, fusión
  Sources/CColorEngine/ce_match.c     capa 3: score, top-k con desempate por id, ce_analyze
  Sources/CColorEngine/ce_mask.c      máscaras: regiones de ropa por pose, recorte de cabeza, piel adaptativa
  Sources/CColorEngine/ce_debug.c     capas de depuración y ce_match_explain_combo
  Sources/CColorEngine/ce_internal.h  layout del contexto (no es API pública)
  Sources/CColorEngine/include/ce/ce.h  API pública
  Sources/CColorEngine/include/module.modulemap
  Sources/ColorEngine/ColorEngine.swift wrapper Swift
  tests/test_math.c                   tests Unity (capa 1)
  tests/test_dict.c                   tests Unity (diccionario)
  tests/test_ctx.c                    tests Unity (contexto, errores)
  tests/test_palette.c                tests Unity (paleta, PNM, rendimiento)
  tests/test_match.c                  tests Unity (match: recall 348/348, empates, errores, hash, rendimiento)
  tests/test_mask.c                   tests Unity (regiones, simetría, invariancias, piel, hash de paridad)
  tests/test_debug.c                  tests Unity (label/weight map, fusión/descarte, explicación bit a bit)
  tests/cli_match_check.js            validador del contrato JSON de match/analyze/batch (node)
  tests/cli_mask_check.js             validador de batch con máscaras, regions, skin, cut-head, --debug-dir (node)
  tests/layers_parity.js              paridad nativo/WASM de capas y máscaras (make parity)
  tests/fuzz_palette.c                fuzz loop propio (make fuzz)
  tests/unity/                        Unity 2.7.2 (MIT), vendorizado
  tests/data/                         Sharma + golden TSV (generados por el oráculo)
  tests/ColorEngineTests/             XCTest del wrapper (en macOS APFS "Tests/" y
                                      "tests/" son el mismo directorio)
  tools/ce_cli.c                      CLI "ce" (version, lab, de2000, convert, dict, palette, match, analyze, batch, regions, skin, cut-head)
  tools/ce_pnm.c, ce_pnm.h            parser P6/P5 (entrada no confiable; fuera del SPM)
  BENCHLOG.md                         una línea por iteración de rendimiento
```
