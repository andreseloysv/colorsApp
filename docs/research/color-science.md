# Ciencia del color, oráculos de referencia y tooling C/WASM

Investigación para el plan de implementación de colorsApp (motor de color en C, iOS + WASM, oráculo Python). Fecha: 2026-09-14. Verificaciones locales hechas en la Mac del usuario (Apple clang 21.0.0, Swift 6.3.3, Xcode 27.0 instalado pero `xcode-select` apuntando a CommandLineTools).

## Resumen

### 1. CIEDE2000: test data, oráculos y trampas

- Test data oficial: Sharma, Wu & Dalal (2005), *Color Res. Appl.* 30(1):21-30, DOI 10.1002/col.20070. Fichero `ciede2000testdata.txt`: 34 filas TSV con 7 columnas (`L1 a1 b1 L2 a2 b2 ΔE00`, 4 decimales) en https://hajim.rochester.edu/ece/sites/gsharma/ciede2000/dataNprograms/ciede2000testdata.txt (descargado y contado). En el mismo directorio: `deltaE2000.m`, `deltaE2000test.m`, `CIEDE2000.xls`. La URL antigua `www2.ece.rochester.edu/~gsharma/ciede2000/` ya no resuelve. PDF del paper: https://hajim.rochester.edu/ece/sites/gsharma/papers/CIEDE2000CRNAFeb05.pdf.
- Trampas documentadas en el paper: (1) `h' = atan2(b*, a')` llevado a [0°, 360°) sumando 2π a los negativos; si `a' = b* = 0`, `h' = 0`; (2) `ΔC'` y `ΔH'` deben ser **con signo** (abs en uno ⇒ fórmula asimétrica; abs en ambos ⇒ simétrica pero incorrecta); (3) `Δh' = 0` si `C1'C2' = 0`, y ±360° cuando `|h2'-h1'| > 180°`; (4) `h̄' = h1'+h2'` si `C1'C2' = 0`; `(h1'+h2'+360)/2` si `|diff| > 180` y suma < 360; `(h1'+h2'-360)/2` si `|diff| > 180` y suma ≥ 360 ("la mayoría de implementaciones en Internet tenían error aquí"); (5) probar simetría intercambiando muestras; (6) discontinuidad real: `h̄'` salta ~180° cuando `|h1'-h2'|` cruza 180°, visible en los pares 13-15 (ΔE 4.8045 → 4.7461 al pasar `a2` de 0.0010 a 0.0011). Pares 1-3 prueban `ΔC'` con signo, 4-6 `ΔH'` con signo, 7-16 atan2 y `h̄'`; 25-34 parecen ser los ejemplos originales de la CIE.
- Oráculo 1: colour-science 0.4.7 (2025-12-06, BSD-3, Python ≥3.11,<3.15, numpy ≥2.1,<3). `colour.delta_E(a, b, method='CIE 2000')` → `colour.difference.delta_E_CIE2000(Lab_1, Lab_2, textiles=False)`; `textiles=True` ⇒ `kL=2`. Su propio test usa 33 de los 34 pares: excluye el 14 porque `np.arctan2` de NumPy 1.24.0 difiere entre Linux y macOS/Windows en ese par; tolerancia absoluta 1e-4.
- Oráculo 2: scikit-image 0.26.0 (2025-12-20): `skimage.color.deltaE_ciede2000(lab1, lab2, kL=1, kC=1, kH=1, *, channel_axis=-1)`, código real en `src/_skimage2/color/delta_e.py` (maneja `C1*C2==0` y el ±2π de `h̄'`), testeado contra el fichero de Sharma con `rtol=1e-2` (laxo). Historial: la búsqueda de issues no muestra bugs de valores incorrectos; el único abierto es #8326 (2026-09-09): crash cuando `lab1` y `lab2` tienen distinto `ndim` (imagen vs un color), fix PR #8327 sin mergear.
- Norma: ISO/CIE 11664-6:2014.

### 2. sRGB → XYZ → CIELAB

- IEC 61966-2-1: primarios R(0.64,0.33) G(0.30,0.60) B(0.15,0.06), blanco D65, curva por tramos `c ≤ 0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4`. Matriz IEC a 4 decimales `[[0.4124,0.3576,0.1805],[0.2126,0.7152,0.0722],[0.0193,0.1192,0.9505]]`. Matriz derivada de primarios + D65 xy(0.3127, 0.3290): `[[0.41239080,0.35758434,0.18048079],[0.21263901,0.71516868,0.07219232],[0.01933082,0.11919478,0.95053215]]`; sus filas suman exactamente el blanco `(0.95045593, 1, 1.08905775)`.
- colour por defecto: `sRGB_to_XYZ` usa la matriz IEC de 4 decimales (`use_derived_matrix_RGB_to_XYZ=False`), `XYZ_to_Lab` con D65 xy (0.3127, 0.3290) (CIE 015:2004). skimage: `rgb2lab(rgb, illuminant='D65', observer='2')` con matriz antigua de 6 decimales `[[0.412453,0.357580,0.180423],[0.212671,0.715160,0.072169],[0.019334,0.119193,0.950227]]`, blanco `(0.95047, 1.0, 1.08883)` y constantes redondeadas (umbral 0.008856, pendiente 7.787) en vez de `ε=216/24389`, `κ=24389/27`.
- Consecuencia medida (cálculo propio): el blanco no da (100,0,0) exacto en ninguno (skimage: a=-0.0025, b=0.0047; colour: a=0.0077, b=0.0035) y entre variantes hay hasta 0.03 ΔE76 (rojo puro). Una tolerancia 1e-6 contra oráculo solo es alcanzable si el motor replica las constantes exactas de ese oráculo.
- Recomendación: motor con matriz derivada + `ε`/`κ` exactos + D65 desde xy(0.3127, 0.3290) en double; oráculo estricto = colour con `use_derived_matrix_RGB_to_XYZ=True` (tolerancia 1e-9 en XYZ; confirmar que `XYZ_to_Lab` usa `ε`/`κ` exactos); oráculo laxo = skimage y colour por defecto con 0.05 ΔE76. D50 solo se usa para ICC/impresión: no aplica.

### 3. Adaptación cromática Bradford

- `CAT_BRADFORD = [[0.8951,0.2664,-0.1614],[-0.7502,1.7135,0.0367],[0.0389,-0.0685,1.0296]]`. API: `colour.adaptation.matrix_chromatic_adaptation_VonKries(XYZ_w, XYZ_wr, transform='Bradford')` (el default es `'CAT02'`, hay que pasarlo), `colour.chromatic_adaptation(...)`, blancos con `colour.xy_to_XYZ(colour.CCS_ILLUMINANTS['CIE 1931 2 Degree Standard Observer'][nombre])`.
- xy 2° (CIE 015:2004, fuente colour): A (0.44758, 0.40745), D50 (0.34570, 0.35850), D65 (0.31270, 0.32900), D75 (0.29903, 0.31488), F2 (0.37210, 0.37510). Wikipedia difiere en el 5º decimal (D65 0.31272/0.32903, F2 0.37208/0.37529): fijar una fuente.
- Matrices D65→X calculadas (D65→D50 coincide con el ejemplo de colour a 1e-7): D65→A `[[1.2165124,0.1110120,-0.1549622],[0.1533623,0.9152297,-0.0560060],[-0.0239515,0.0359053,0.3146370]]`; D65→F2 `[[1.0904241,0.0446190,-0.0817375],[0.0594201,0.9744519,-0.0283989],[-0.0142245,0.0226082,0.6104958]]`; D65→D75 `[[0.9799713,-0.0091597,0.0251626],[-0.0112412,1.0015718,0.0083673],[0.0049014,-0.0081647,1.1291007]]`.

### 4. OKLab vs CIELAB + ΔE2000

- OKLab (Ottosson 2020) se ajustó a datos derivados de CAM16-UCS (lightness/chroma/hue), no a experimentos de diferencia de color; el autor lo reconoce como limitación. Preprint arXiv 2606.05255 (Uchida, jun-2026, sin revisión por pares): STRESS en COMBVD (3.813 pares) Oklab 47.35 vs CIEDE2000 29.13, peor en cada subconjunto (BFD-P D65 51.45 vs 24.12; RIT-DuPont 31.76 vs 19.49).
- Recomendación: la métrica de match debe ser ΔE2000 (ISO/CIE 11664-6:2014). Evaluar en el harness `kL=2` (modo "textiles" de colour) porque el error dominante en ropa es de exposición (L*). OKLab queda para UI, gradientes y como prefiltro barato si hiciera falta (348×5 comparaciones no lo necesitan).

### 5. Tooling C: tests, sanitizers, fuzzing, SPM, Emscripten

- Frameworks: Unity (MIT, activo 2026-09, 1 .c + 2 .h, `TEST_ASSERT_DOUBLE_WITHIN`), greatest (ISC, single-header, C89, último push 2023-06), µnit (MIT, PRNG con semilla reproducible, último push 2024-04), cmocka 2.0.1 (Apache-2.0, CMake/Meson, mocks). Recomendación: Unity o greatest (sin dependencia de build).
- Apple clang 21 (CLT): `-fsanitize=address,undefined` funciona (probado). `-fsanitize=fuzzer` NO: falta `libclang_rt.fuzzer_osx.a` en CLT y en Xcode 27. Alternativas: `brew install llvm` (23.1.0; incluye libFuzzer, no verificado), AFL++ 5.03c, o fuzz loop propio con PRNG + ASan/UBSan.
- SPM verificado localmente: `.target(name:"CColorEngine", path:"Sources/CColorEngine", publicHeadersPath:"include", cSettings:[.define(...), .unsafeFlags(["-ffp-contract=off","-std=c11"])])` + target Swift que hace `import CColorEngine` + XCTest. `swift build` OK con CLT; `swift test` falla con CLT ("no such module 'XCTest'") pero funciona con `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (sin sudo); `xcodebuild -scheme ColorEngine -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED (Xcode 27.0, SDK iOS 27.0), objeto con `fmul`+`fadd`. `unsafeFlags` hace el producto inelegible como dependencia de otros paquetes (paquete raíz/local sí compila). Mejor: `#pragma STDC FP_CONTRACT OFF` en cada `.c` y sin `unsafeFlags`.
- Homebrew (nada instalado): cmake 4.4.3, ninja 1.13.2, emscripten 6.0.9, uv 0.12.11. Emscripten solo soporta oficialmente emsdk (`./emsdk install latest && ./emsdk activate latest && source ./emsdk_env.sh`, macOS ≥10.14); `emcmake cmake -B build-wasm && cmake --build build-wasm`; usar `emar`.

### 6. Determinismo arm64 iOS / arm64 macOS / WASM

- Apple clang: default `-ffp-contract=on` ⇒ `a*b+c` en la misma sentencia se compila a `fmadd` en arm64 (macOS e iOS, verificado); entre sentencias no fusiona. En WASM el backend LLVM marca `ISD::FMA` como `Expand` y Wasm base no tiene FMA (solo relaxed-simd `f64x2.relaxed_madd`, explícitamente no determinista) ⇒ `mul`+`add`. Misma fuente ⇒ bits distintos. Solución: `#pragma STDC FP_CONTRACT OFF` en todos los TU del motor (verificado) y prohibir `-ffast-math`/`-Ofast`/`-ffp-contract=fast` (ignoran el pragma, verificado).
- Ops IEEE básicas (+,-,×,÷,sqrt) son deterministas en Wasm salvo bits de NaN. libm: Emscripten usa musl; Apple su propia libm; `sin/cos/atan2/exp/pow/cbrt` no están correctamente redondeados ⇒ pueden diferir en ULPs. Opciones: (a) tolerancia 1e-9 en Lab/ΔE con decisión (argmin) robusta y desempate por índice; (b) bit-exactitud: implementaciones portables propias de `cbrt/atan2/sin/cos/exp` dentro del motor (p. ej. de musl) compiladas con el pragma. Usar `double` en todo el motor.

### 7. Entorno Python para el oráculo

- El Python 3.9.6 del sistema no sirve (colour ≥3.11,<3.15; numpy 2.5.3 y scipy 1.18.1 ≥3.12). Plan: `brew install uv` (0.12.11) → `uv python install 3.13` → proyecto `oracle/` con pyproject fijado a numpy 2.5.3, scipy 1.18.1, scikit-image 0.26.0, colour-science 0.4.7, pillow 12.3.0 (todos con wheels cp313 macosx arm64; colour es pure-Python) → `uv sync` / `uv run`. Registrar `np.__version__` en los golden files (caso arctan2 del par 14).

## Findings (claim | confidence | URL)

1. El fichero de test de Sharma tiene 34 pares en TSV de 7 columnas (L1 a1 b1 L2 a2 b2 ΔE00) con 4 decimales | verified | https://hajim.rochester.edu/ece/sites/gsharma/ciede2000/dataNprograms/ciede2000testdata.txt
2. La página de Sharma ofrece además deltaE2000.m, deltaE2000test.m y CIEDE2000.xls (HTTP 200) | verified | https://hajim.rochester.edu/ece/sites/gsharma/ciede2000/
3. La URL antigua www2.ece.rochester.edu/~gsharma/ciede2000/ no resuelve (DNS) | verified | http://www2.ece.rochester.edu/~gsharma/ciede2000/
4. Paper: Sharma, Wu, Dalal, Color Res. Appl. 30(1):21-30, 2005, DOI 10.1002/col.20070 | verified | https://onlinelibrary.wiley.com/doi/10.1002/col.20070
5. h' se calcula con atan2 de cuatro cuadrantes, se lleva a [0°,360°) y vale 0 si a'=b*=0 | verified | https://hajim.rochester.edu/ece/sites/gsharma/papers/CIEDE2000CRNAFeb05.pdf
6. ΔC' y ΔH' deben ser con signo; usar abs en uno da fórmula asimétrica, en ambos simétrica pero incorrecta | verified | https://hajim.rochester.edu/ece/sites/gsharma/papers/CIEDE2000CRNAFeb05.pdf
7. Regla de h̄' (h1'+h2' si C1'C2'=0; ±360 según |diff|>180 y suma <360 o ≥360); "la mayoría de implementaciones en Internet" tenían error ahí | verified | https://hajim.rochester.edu/ece/sites/gsharma/papers/CIEDE2000CRNAFeb05.pdf
8. La fórmula es discontinua: h̄' salta ~180° cuando |h1'-h2'| cruza 180°; pares 13-15 pasan de 4.8045 a 4.7461 con a2 0.0010→0.0011 | verified | https://hajim.rochester.edu/ece/sites/gsharma/ciede2000/dataNprograms/ciede2000testdata.txt
9. Pares 1-3 prueban ΔC' con signo, 4-6 ΔH' con signo, 7-16 atan2 y h̄'; 25-34 corresponden a los ejemplos CIE originales | likely | https://hajim.rochester.edu/ece/sites/gsharma/papers/CIEDE2000CRNAFeb05.pdf
10. colour-science 0.4.7, 2025-12-06, BSD-3-Clause, Python >=3.11,<3.15, numpy >=2.1,<3 | verified | https://pypi.org/project/colour-science/
11. API: colour.delta_E(a,b,method='CIE 2000') → colour.difference.delta_E_CIE2000(Lab_1, Lab_2, textiles=False, additional_data=False); textiles=True ⇒ kL=2 | verified | https://colour.readthedocs.io/en/latest/generated/colour.delta_E.html
12. El test de colour usa 33/34 pares de Sharma: excluye el 14 por diferencias de np.arctan2 (NumPy 1.24.0) entre Linux y macOS/Windows; tolerancia 1e-7·1000 = 1e-4 | verified | https://raw.githubusercontent.com/colour-science/colour/develop/colour/difference/tests/test_delta_e.py
13. scikit-image 0.26.0, 2025-12-20, BSD, Requires-Python >=3.11; pyproject de main exige >=3.12, numpy>=2.1, scipy>=1.15, pillow>=10.1 | verified | https://pypi.org/project/scikit-image/
14. skimage.color.deltaE_ciede2000(lab1, lab2, kL=1, kC=1, kH=1, *, channel_axis=-1); implementación real en src/_skimage2/color/delta_e.py con manejo de C1*C2==0 y ±2π en h̄' | verified | https://raw.githubusercontent.com/scikit-image/scikit-image/main/src/_skimage2/color/delta_e.py
15. El test de skimage compara con el fichero de Sharma (tests/skimage/color/ciede2000_test_data.txt) con rtol=1e-2 | verified | https://raw.githubusercontent.com/scikit-image/scikit-image/main/tests/skimage/color/test_delta_e.py
16. Bug abierto #8326: deltaE_ciede2000 crashea con ndim distinto (imagen vs color único); fix PR #8327 sin mergear al 2026-09-14 | verified | https://github.com/scikit-image/scikit-image/issues/8326
17. La búsqueda de issues "ciede2000" en skimage (7 resultados) no muestra bugs históricos de valores incorrectos | verified | https://github.com/scikit-image/scikit-image/pull/665
18. CIEDE2000 está normalizado como ISO/CIE 11664-6:2014 | verified | https://cie.co.at/publications/colorimetry-part-6-ciede2000-colour-difference-formula
19. sRGB (IEC 61966-2-1): primarios (0.64,0.33)(0.30,0.60)(0.15,0.06), blanco D65, matriz IEC 4 decimales, decoding eotf_sRGB | verified | https://colour.readthedocs.io/en/latest/generated/colour.models.RGB_COLOURSPACE_sRGB.html
20. Matriz derivada de primarios + D65 xy(0.3127,0.3290) = [[0.41239080,0.35758434,0.18048079],[0.21263901,0.71516868,0.07219232],[0.01933082,0.11919478,0.95053215]], blanco (0.95045593,1,1.08905775) | likely | https://colour.readthedocs.io/en/latest/generated/colour.models.RGB_COLOURSPACE_sRGB.html
21. colour.sRGB_to_XYZ(RGB, illuminant=D65, chromatic_adaptation_transform='CAT02', apply_cctf_decoding=True); RGB_Colourspace.use_derived_matrix_RGB_to_XYZ default False | verified | https://colour.readthedocs.io/en/latest/generated/colour.sRGB_to_XYZ.html
22. colour.XYZ_to_Lab(XYZ, illuminant=CCS_ILLUMINANTS['CIE 1931 2 Degree Standard Observer']['D65']), ref. CIE 015:2004 | verified | https://colour.readthedocs.io/en/latest/generated/colour.XYZ_to_Lab.html
23. xy en colour (CIE 015:2004): A (0.44758,0.40745), D50 (0.34570,0.35850), D65 (0.31270,0.32900), D75 (0.29903,0.31488), F2 (0.37210,0.37510) | verified | https://raw.githubusercontent.com/colour-science/colour/develop/colour/colorimetry/datasets/illuminants/chromaticity_coordinates.py
24. skimage rgb2lab(rgb, illuminant='D65', observer='2'): matriz 6 decimales [[0.412453,0.357580,0.180423],...], blanco D65 (0.95047,1.0,1.08883), umbral 0.008856 y pendiente 7.787 | verified | https://raw.githubusercontent.com/scikit-image/scikit-image/main/src/_skimage2/color/colorconv.py
25. Ninguna variante mapea el blanco a (100,0,0) exacto; entre matriz derivada, IEC y skimage hay hasta 0.03 ΔE76 (rojo puro) | likely | https://raw.githubusercontent.com/scikit-image/scikit-image/main/src/_skimage2/color/colorconv.py
26. CAT_BRADFORD = [[0.8951,0.2664,-0.1614],[-0.7502,1.7135,0.0367],[0.0389,-0.0685,1.0296]] | verified | https://colour.readthedocs.io/en/latest/generated/colour.adaptation.CAT_BRADFORD.html
27. matrix_chromatic_adaptation_VonKries(XYZ_w, XYZ_wr, transform='CAT02'): default CAT02; ejemplo Bradford D65→D50 = [[1.0479297,0.0229468,-0.0501922],...] | verified | https://colour.readthedocs.io/en/latest/generated/colour.adaptation.matrix_chromatic_adaptation_VonKries.html
28. Matrices Bradford D65→A, D65→F2, D65→D75 calculadas; D65→D50 coincide con colour a 1e-7 | likely | https://colour.readthedocs.io/en/latest/generated/colour.adaptation.matrix_chromatic_adaptation_VonKries.html
29. OKLab se optimizó contra datos derivados de CAM16, no contra experimentos de diferencia de color; el autor lo señala como caveat | verified | https://bottosson.github.io/posts/oklab/
30. Preprint arXiv 2606.05255 (jun-2026): STRESS COMBVD Oklab 47.35 vs CIEDE2000 29.13; por dataset Oklab peor en todos | verified | https://arxiv.org/html/2606.05255v1
31. Unity: MIT, activo (push 2026-09-10), 1 .c + 2 .h, TEST_ASSERT_DOUBLE_WITHIN | verified | https://github.com/ThrowTheSwitch/Unity
32. greatest: ISC, single header, C89, sin dependencias, último push 2023-06 | verified | https://github.com/silentbicycle/greatest
33. µnit: MIT, munit.c + munit.h, PRNG reproducible con semilla, último push 2024-04 | verified | https://github.com/nemequ/munit
34. cmocka 2.0.1 (2025-12-19), Apache-2.0, CMake/Meson, C99 | verified | https://cmocka.org/
35. Apple clang 21 (CLT) soporta -fsanitize=address,undefined; -fsanitize=fuzzer falla por falta de libclang_rt.fuzzer_osx.a (CLT y Xcode 27) | verified | https://llvm.org/docs/LibFuzzer.html
36. Homebrew: cmake 4.4.3, ninja 1.13.2, emscripten 6.0.9, uv 0.12.11, llvm 23.1.0, afl++ 5.03c; ninguno instalado | verified | https://formulae.brew.sh/formula/emscripten
37. Emscripten: solo emsdk está soportado oficialmente; macOS ≥10.14; emcmake cmake -B build && cmake --build build; usar emar | verified | https://emscripten.org/docs/getting_started/downloads.html
38. SPM local: target C con publicHeadersPath "include" + unsafeFlags compila (swift build) y pasa XCTest con DEVELOPER_DIR=Xcode; con CLT falla "no such module 'XCTest'"; build iOS con xcodebuild CODE_SIGNING_ALLOWED=NO OK | verified | https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html
39. unsafeFlags hace los productos inelegibles como dependencia de otros paquetes | verified | https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html
40. Apple clang default -ffp-contract=on: a*b+c → fmadd en arm64 (macOS e iOS); #pragma STDC FP_CONTRACT OFF lo evita; -ffast-math/-ffp-contract=fast ignoran el pragma | verified | https://clang.llvm.org/docs/UsersManual.html
41. Backend WebAssembly de LLVM: setOperationAction(ISD::FMA, T, Expand) para flotantes escalares | verified | https://raw.githubusercontent.com/llvm/llvm-project/main/llvm/lib/Target/WebAssembly/WebAssemblyISelLowering.cpp
42. Wasm base no tiene FMA; relaxed-simd f32x4/f64x2.relaxed_madd puede redondear 1 o 2 veces según hardware | verified | https://github.com/WebAssembly/relaxed-simd/blob/main/proposals/relaxed-simd/Overview.md
43. El no determinismo FP de Wasm se limita a bits de NaN | verified | https://github.com/WebAssembly/design/blob/main/Nondeterminism.md
44. Emscripten usa libm de musl (system/lib/libc/musl/src/math) | verified | https://github.com/emscripten-core/emscripten/blob/main/system/lib/libc/musl/src/math/sin.c
45. Las funciones trascendentes no están definidas por IEEE con redondeo correcto y difieren entre libms; solo +,-,×,÷,sqrt son reproducibles | likely | https://randomascii.wordpress.com/2013/07/16/floating-point-determinism/
46. Wheels cp313 macosx arm64: scikit-image 0.26.0, numpy 2.5.3 (≥3.12), scipy 1.18.1 (≥3.12), pillow 12.3.0; colour-science 0.4.7 pure-Python | verified | https://pypi.org/pypi/scikit-image/0.26.0/json
47. uv: uv python install 3.13, uv venv, uv python list | verified | https://docs.astral.sh/uv/guides/install-python/
48. Mac del usuario: no hay cmake, emcc, uv, ninja ni Python 3.12/3.13; python3 = 3.9.6 sin numpy | verified | (verificación local)
