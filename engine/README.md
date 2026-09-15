# Motor de color (capas 1 y 2: matemática de color y extracción de paleta)

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
- **Capa 3** (`ce_match`, `ce_analyze`): declarada en `ce.h`; stubs que devuelven
  `CE_ERR_NOT_IMPLEMENTED` hasta la fase 3.

API pública: `Sources/CColorEngine/include/ce/ce.h` (documentada en español).
Wrapper Swift: `Sources/ColorEngine/ColorEngine.swift` (`Lab`, `srgbToLab`,
`labToSrgb8`, `deltaE2000`, `deltaE76`, `Swatch`, `PaletteOptions`,
`extractPalette`, `nearestDictionaryColor`).

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
| `make fuzz [FUZZ_SECONDS=600] [FUZZ_SEED=1]` | Fuzz loop propio de la capa 2 bajo ASan/UBSan en `build-asan/` (`mk/engine.mk`) |
| `make bench-palette` | Imprime `PERF_1024_RGBA_MS` de `test_palette` (nativo -O2); anotar en `BENCHLOG.md` |
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
`CE_ERR_NOT_IMPLEMENTED` para `ce_match`/`ce_analyze`), sin escribir en la
salida y sin abortar nunca. `ce_dict_nearest_color` (sin contexto) da el
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
  stubs de la fase 3; `ce_reduced_dims`.
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

## Tests (`tests/test_math.c`, Unity)

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
redondeadas. Por eso los hashes difieren:

| Plataforma        | HASH_GOLDEN_BITS   | HASH_GOLDEN_TEXT   |
|-------------------|--------------------|--------------------|
| macOS arm64 (clang 21) | `2b22878a87a359cf` | `ea2f38eac978c4a1` |
| WASM (emcc 6.0.9, node 24) | `664d767f2bc729c6` | `7ef2cb24832fc966` |

Magnitud medida con el CLI en ambas plataformas (script de comparación sobre
los golden y sobre 200 000 colores / 50 000 pares aleatorios):

- Lab: ~30 % de las filas difieren en algún bit; |Δ| máx = 1.2e-13 (≈ 8 ULP
  para valores de magnitud 100; en componentes casi nulas, p. ej. a ≈ 1e-3,
  esa misma diferencia absoluta son miles de ULP).
- ΔE00: ~10 % de los pares difieren; |Δ| máx = 3.1e-13 (≤ 47 ULP).
- Bradford: 0 diferencias (solo +, ×, ÷).
- Ambas plataformas quedan a ≤ 2.6e-13 del oráculo Python (numpy usa otra libm
  más).

Tolerancia aplicada: **1e-9** absoluto en Lab, ΔE00 y XYZ frente a los golden
(cuatro órdenes de magnitud de margen sobre lo medido), y el round-trip 8 bits
es exacto en ambas plataformas. Las decisiones de las capas superiores
(argmin de ΔE00 sobre el diccionario) deben desempatar por índice para ser
robustas a diferencias de 1e-13. Si algún día hiciera falta bit-exactitud
nativo/WASM, la vía es incluir implementaciones portables de `cbrt/pow/atan2/
sin/cos/exp` (p. ej. las de musl) dentro del motor, compiladas con el pragma.

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
  Sources/CColorEngine/ce_palette.c   capa 2: histograma, MMCQ, Lloyd, fusión; stubs de la 3
  Sources/CColorEngine/ce_internal.h  layout del contexto (no es API pública)
  Sources/CColorEngine/include/ce/ce.h  API pública
  Sources/CColorEngine/include/module.modulemap
  Sources/ColorEngine/ColorEngine.swift wrapper Swift
  tests/test_math.c                   tests Unity (capa 1)
  tests/test_dict.c                   tests Unity (diccionario)
  tests/test_ctx.c                    tests Unity (contexto, errores)
  tests/test_palette.c                tests Unity (paleta, PNM, rendimiento)
  tests/fuzz_palette.c                fuzz loop propio (make fuzz)
  tests/unity/                        Unity 2.7.2 (MIT), vendorizado
  tests/data/                         Sharma + golden TSV (generados por el oráculo)
  tests/ColorEngineTests/             XCTest del wrapper (en macOS APFS "Tests/" y
                                      "tests/" son el mismo directorio)
  tools/ce_cli.c                      CLI "ce"
  tools/ce_pnm.c, ce_pnm.h            parser P6/P5 (entrada no confiable; fuera del SPM)
  BENCHLOG.md                         una línea por iteración de rendimiento
```
