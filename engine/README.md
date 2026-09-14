# Motor de color (capa 1: matemática de color pura)

Librería C11 sin I/O, sin `malloc` y sin dependencias (solo `<math.h>`), con
todo en `double`. La misma fuente compila a nativo (iOS/macOS vía Swift Package
o CMake) y a WebAssembly (Emscripten). Esta capa cubre:

- sRGB (IEC 61966-2-1) ⇄ XYZ (D65) ⇄ CIELAB, en 8 bits y en `double`.
- ΔE*ab (1976) y ΔE00 (CIEDE2000, Sharma/Wu/Dalal 2005) con `kL, kC, kH`.
- Adaptación cromática de Bradford entre A, D50, D65, D75 y F2.

API pública: `Sources/CColorEngine/include/ce/ce.h` (documentada en español).
Wrapper Swift: `Sources/ColorEngine/ColorEngine.swift` (`Lab`, `srgbToLab`,
`labToSrgb8`, `deltaE2000`, `deltaE76`).

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
```

Opciones CMake: `CE_BUILD_TESTS` (ON), `CE_BUILD_CLI` (ON), `CE_SANITIZE`
(OFF), `CE_ROUNDTRIP_STEP` (1; paso del round-trip exhaustivo).

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
  Sources/CColorEngine/ce_math.c      implementación
  Sources/CColorEngine/include/ce/ce.h  API pública
  Sources/CColorEngine/include/module.modulemap
  Sources/ColorEngine/ColorEngine.swift wrapper Swift
  tests/test_math.c                   tests Unity (capa 1)
  tests/unity/                        Unity 2.7.2 (MIT), vendorizado
  tests/data/                         Sharma + golden TSV (generados por el oráculo)
  tests/ColorEngineTests/             XCTest del wrapper (en macOS APFS "Tests/" y
                                      "tests/" son el mismo directorio)
  tools/ce_cli.c                      CLI "ce"
```
