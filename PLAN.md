# colorsApp — Plan de implementación

2026-09-14 (rev. 2, tras revisión) — Estado: **2 commits** (b176b7d "Capa 1 del motor…", b518938 "Makefile: incluir mk/*.mk…") **más trabajo sin commitear de F0/F1** (`git status`: 12 ficheros modificados, 15 sin seguimiento). Capa 1 del motor en verde (`make test` 2/2 ctest, `make test-wasm` 2/2), diccionario generado (159 colores / 348 combinaciones, `dict_version fd95ac692777`, `status provisional`), oráculo Python y harness L1 con scorecard; 0 identidades de firma en el Mac; un iPhone emparejado. Las cifras de tests cambian cada hora: la fuente es la salida de `make test` y `uv run --project oracle pytest -q`, no este documento.

**Aviso operativo**: varios agentes escriben en el repo en paralelo (ficheros con mtime de los últimos minutos). Antes de cada fase, re-verificar con `git status`, `make doctor` y `make check-protected`; nada de lo marcado HECHO aquí sustituye esa comprobación.

## 1. Resumen ejecutivo y decisiones clave

El MVP tiene un solo trabajo: demostrar que foto → combinación de Sanzo Wada es creíble en dos iPhones sin pagar el Apple Developer Program. Orden: cimientos y firma → datos → extracción → match → paridad WASM → app iOS → set dorado recogido con la propia app → capa 4 → cierre. La app de producto llega en la fase 6 de 11, con L1–L3 y paridad en verde; antes solo se instala un stub firmado (fase 0), porque la fricción de firma es el riesgo más barato de matar y depende de un teléfono que nadie ha visto.

**Inventario verificado hoy** (el §8 del contexto está desactualizado): `make doctor` OK con Xcode 27.0 (27A266a) y `xcode-select` correcto, clang 21, Swift 6.4, cmake 4.4.3, emcc 6.0.9, node v24.21.0 (vía nvm; brew tiene 26.8.2 pero el PATH resuelve el de nvm), uv 0.12.13, xcodegen 2.46.0, venv Python 3.12.14 en `oracle/.venv` (numpy 2.5.3, scikit-image 0.26.0, colour-science 0.4.7, scipy 1.18.1, Pillow 12.3.0, scikit-learn 1.9.1, opensimplex); `security find-identity -v -p codesigning` → **0 identidades**; `ios/Signing.xcconfig` sigue con `REEMPLAZAR`. Dispositivo 1: iPhone 13 mini, UDID `00008110-000E65AC1E69801E`, iOS 26.5, Developer Mode Enabled, emparejado por cable. Verificado en verde: `make test` (ctest: `test_math` + `test_dict`), `make test-wasm` (golden_wada_lab a 6,0e-14 en WASM), `make dict-check`, `make ios-build-device-nosign` exit 0, `make eval` con L1 pass y L2–L4 `not implemented` (exit 1, por diseño). **`make check-protected` falla hoy**: hay ficheros protegidos nuevos sin entrada en `PROTECTED.sha256` (`overrides.json`, `golden_wada_lab.tsv`, `names.html`, `thresholds.json`); ver la regla de bootstrap en §6. **Todo lo existente se adopta tal cual; nada se renombra** (árbol en §9).

Decisiones:
- **Un motor, tres binarios**: C11 con prefijo `ce_`, sin I/O, malloc ni RNG; SwiftPM (iOS), CMake (CLI `ce`, tests) y emcc (`ce.js` con `-sNODERAWFS=1 -sEXIT_RUNTIME=1`, enlace para node/paridad; la web necesita un enlace propio, ver §5 y §11.E).
- **Espacio único**: CIELAB D65 + ΔE2000 (kL=1; kL=2 como variante medida). OKLab fuera del MVP.
- **Determinismo**: `#pragma STDC FP_CONTRACT OFF` en cada TU (verificado: 0 `fmadd` en el objeto de SPM), `double`, nunca `-ffast-math`, sin `unsafeFlags`. La libm es la única divergencia nativo/WASM (medida ≤ 3,1e-13 en ΔE00 y 1,2e-13 en Lab, fuente: `engine/README.md`, sección "Determinismo nativo vs WASM") → tolerancia 1e-9 y desempate por id.
- **Contexto reservado por el llamante** (`ce_ctx_size`/`ce_ctx_init`): sin estáticos mutables, una instancia por tarea; presupuesto acotado por test (§5).
- **Diccionario**: solo sRGB8 embebido; el Lab lo calcula el motor con la misma función que la foto. Estado `provisional` hasta cotejar con el libro.
- **Harness**: 4 capas, `make eval` con scorecard; rutas protegidas; semilla de holdout y set dorado fuera del repo.
- **iOS**: SwiftUI, target iOS 17, xcodegen, GRDB 7.11, Personal Team, build semanal por Wi-Fi, con "sí, es eso / no" y "Exportar diagnóstico" desde la primera build (sin ellos el criterio de éxito no se puede medir).

Supuestos: el iPhone de la esposa tiene iOS ≥ 17 (no verificado); el usuario nombra las 348 combinaciones por lotes y acepta "Nº 012" mientras tanto; las fotos personales nunca entran en el repo; UI en español, nombres de color en inglés; bundle ID provisional `com.andreseloy.colorsapp`; reinstalar tras la caducidad conserva los datos (se prueba en F0).

## 2. Alcance del MVP

**Dentro** (los 7 puntos del §4 del contexto): diccionario embebido (348 con número, colección y nombre cuando exista); match on-device por ΔE2000 ponderado por área con peso al centro; pantalla de resultado; tarjeta compartible; rejilla de 348 con persistencia local; escaneo de las últimas ~200 fotos al instalar; explorar con picker y extracción manual. Añadido mínimo: "sí, es eso / no" y "Exportar diagnóstico".

**Fuera**: servidor, sync, cuentas, roles/panel admin, favoritos remotos, armario, AR, territorios, mapa, retos, fork, rareza real, Vol. 2 (sin dataset con licencia), balance de blancos en el motor, MediaPipe. La máscara de persona de Vision es un flag apagado que solo se enciende si la capa 4 muestra ≥ +5 puntos de recall@1.

**Tres desvíos explícitos respecto al corte del §4 del contexto** (lista única, para aprobación del usuario de una sola vez):
- (a) **Los nombres propios no bloquean la UI** (fallback "Nº 012"), porque nombrar 348 láminas es curación humana larga que no reduce el riesgo principal.
- (b) **Las 50–100 fotos reales se recogen con la app instalada** (fase 8), porque es la forma más barata de obtenerlas de los dos teléfonos con veredicto, y el motor ya habrá pasado L1–L3 y paridad antes de la primera pantalla.
- (c) **Los valores de color pueden quedar `provisional`** (sin cotejo con el libro Seigensha ni perfil SWOP) durante todo el MVP: el contexto pedía "348 registros con valores verificados" antes de la UI; el plan lo relaja porque la única verificación independiente es el libro físico (decisión del usuario, §4) y el scorecard lo hace visible con `book-verified: no`.

## 3. Stack y distribución en los dos iPhones sin cuenta pagada

Stack: SwiftUI, deployment target iOS 17, Xcode 27, proyecto generado con `xcodegen generate` desde `ios/project.yml` (`.xcodeproj` fuera de git; ya existe con el stub), dependencias SPM `engine/` (local) y GRDB.swift 7.11 (MIT). `DEVELOPMENT_TEAM` en `ios/Signing.xcconfig` (gitignored; plantilla `Signing.example.xcconfig`).

Prerrequisito bloqueante: [USUARIO] iniciar sesión en Xcode > Settings > Apple Accounts; criterio: `security find-identity -v -p codesigning` lista "Apple Development: …" (hoy 0). Instalación: `CODE_SIGN_STYLE Automatic`, un bundle ID único y estable. Cada iPhone: cable la primera vez, "Trust This Computer", Developer Mode, primera apertura → confiar el desarrollador en Ajustes > General > VPN y gestión de dispositivos; después, Run por Wi-Fi. `make ios-install DEVICE=<udid>` (existe en `mk/ios.mk`) = comprobar identidad y Team ID → `xcodebuild -destination 'id=<udid>' -allowProvisioningUpdates -allowProvisioningDeviceRegistration build` → `xcrun devicectl device install app` → `process launch`. Nada de la ruta de firma se ha ejercitado todavía (0 identidades, `REEMPLAZAR`); si falla headless con Personal Team (no probado), fallback: abrir `ios/ColorsApp.xcodeproj` y Run (⌘R). Tampoco hay documento de Apple que confirme que el iPhone de la esposa se registra sin su Apple ID; se comprueba en F0.

Límites (Apple, verificado): 3 dispositivos (usamos 2), 10 App IDs, 3 apps por dispositivo, perfil de **7 días** tras el cual la app deja de abrirse; Xcode 27 solo depura iOS ≥ 17.

**Ritual semanal (`make release-week`), escalonado según lo que exista** (el mismo texto va en `docs/RELEASE.md`, que hoy aún dice "make eval (fase 1+; hoy make test)" y debe alinearse):
- F0–F2: `make test` + `make check-protected` + `make ios-lint` + `make ios-install` a los dos iPhones.
- Desde F3: `make eval-fast` (+ `check-protected`, `ios-lint`) + `ios-install` ×2.
- Desde F4: `make eval` completo + `ios-install` ×2.
Es la "release" del MVP; cada ≤ 7 días.

Prohibido (vetado al Personal Team o gasta App IDs): Push/APNs, iCloud/CloudKit, Sign in with Apple, Associated Domains, App Attest, TestFlight, App Store Connect, extensiones, cualquier capability. Plan B para la esposa: SideStore 0.6.4 + LocalDevVPN (IPA propio, Apple ID en app de terceros; iOS 27 no verificado). **SideStore ocupa 1 de los 3 slots de apps por dispositivo**: quedarían 2 para ColorsApp y otra. PWA descartada: sin API para enumerar el carrete.

## 4. Datos: diccionario Wada

**Fuente exacta**: `data/wada/source/colors.json`, copia sin modificar de mattdesl/dictionary-of-colour-combinations 1.0.2 (MIT; `LICENSE` y `PROVENANCE.md` en el repo), derivada de la transcripción de dblodorn: mismo linaje, no fuente independiente. Base legal: obra de Wada en dominio público en Japón (†1967; vida+50 expiró 2017-12-31; la extensión de 2018 no es retroactiva); riesgo residual: derecho de compilación de Seigensha (Art. 12) y estado fuera de Japón (URAA, no investigado). Mitigación: solo datos, nunca escaneos ni textos; atribución a Wada, Seigensha, dblodorn y mattdesl.

**Formato en el repo** (generado por `oracle.build_dictionary`, `make dict`): `dictionary.json` (`colors[{index, name, hex, rgb, cmyk, swatch}]`, `combinations[{id 1..348, size 2..7, colors[], collection}]`, `dict_version`, `status`); `errata.json` (6 discrepancias del issue #1/PR #2, `status: pending`); `overrides.json` (existe, vacío: correcciones explícitas que solo escribe el usuario al aceptar una errata); `names.es.json` (348 × `{id, name, lang, status, notes}`, solo curación); `ce_dict_data.h` (solo sRGB8, `CE_DICT_COMBO_MAX 7`). `dict_version` (sha256 corto) se cruza con `ce_dict_version()` (en `ce_dict.c`) y con la cabecera de `golden_wada_lab.tsv` (`make eval` ya lo comprueba). **Las colecciones no son los 6 capítulos del libro**: verificado que solo 27/348 combinaciones tienen todos sus colores en un capítulo; `swatch` es atributo del color. `collection` es null hasta curación; agrupación automática neutra por tamaño (2/3/4); las temáticas son curación del usuario.

**Pipeline sRGB/Lab**: los `rgb` de mattdesl vienen de LittleCMS (SWOP v2 → sRGB, relative colorimetric + BPC). Verificado: **no hay perfil SWOP en este Mac** y Generic CMYK reproduce solo 1/159 (`CONVERSION_CHECK.md`: desvío máx R23/G14/B28). Política: los 155 colores sin errata conservan el hex del fuente; las 4 erratas CMYK quedan `pending_icc` hasta que [USUARIO] aporte el perfil por `COLORSAPP_SWOP_PROFILE`; el gate existente `test_swop_reconversion_reproduces_source` (hoy skipped) debe reproducir los 155 hex con error ≤ 1/255 por canal antes de aceptar un `derived_rgb_candidate`, registrando la versión de LittleCMS **embebida en Pillow** (`PIL.features.version('littlecms2')`), que es la que usa la reconversión; la `little-cms2 2.19.1` de brew está instalada pero no interviene. Las 2 erratas de nombre se aceptan sin ICC. Lab D65 no se guarda: lo calcula el motor y el oráculo lo congela en `golden_wada_lab.tsv` (existe); el `lab` D50 del fuente no se usa.

**Validación de los 348** (`make dict-check`, en gran parte ya en `build_dictionary --check` y `test_dictionary.py`): ids 1..348 contiguos; 120/120/108 por tamaño, 1.032 slots; hex únicos; todo color en ≥ 1 combinación; CMYK ≤ 100 salvo la errata conocida (M=106). **Pendiente (F1)**: recuento explícito de 159 nombres distintos y 157 nombres base tras quitar los sufijos A/B, y de las 27/348 combinaciones mono-capítulo (ambas cifras verificadas a mano en esta sesión, aún no codificadas). El cotejo con dblodorn compara solo CMYK y pertenencia (consistencia de linaje). La única verificación independiente es el libro Seigensha Vol. 1 (ISBN 978-4-86152-247-5, 1.500 ¥): [USUARIO] decide; sin él el scorecard imprime `book-verified: no`.

**Curación de nombres** (solo [USUARIO]): `names.es.json` por lotes con `harness/label/names.html` (existe; generado por `make names-html`, estático y autocontenido, 20 combinaciones por lote, guarda borrador en `localStorage`, exporta `names.es.json`); `make names-todo` (existe) lista pendientes; el agente solo puede proponer `names.suggested.json`.

## 5. Motor en C

**Módulos** (`engine/Sources/CColorEngine/`): `ce_math.c` (existe: sRGB↔XYZ↔Lab con matriz derivada, ε/κ exactos, ΔE76/ΔE00 con kL,kC,kH, Bradford); `ce_dict.c` (existe: tablas `static const`, accesores sin contexto, `ce_dict_version()`); `ce_ctx.c` (contexto: buffers de trabajo + caché de la tabla Lab de los 159 colores construida con `ce_dict_color_lab`); `ce_image.c` (box-downscale entero a ≤256 px; pesos = gaussiana al centro × máscara opcional × regla de piel YCbCr opcional); `ce_palette.c` (histograma 5 bits/canal con conteos enteros → MMCQ k=6 → Lloyd ponderado en Lab ≤20 iteraciones → fusión ΔE00<5 → descarte <5 % → 3–5 swatches); `ce_match.c`; `ce_dict_data.h`. Opcional `ce_libm.c` (libm portable) solo si `make parity` lo exige.

**API pública** (`include/ce/ce.h`). **Decisión: se conserva íntegra la API de capa 1 existente**, incluidos los accesores del diccionario **sin contexto** ya publicados en `ce.h` (`ce_dict_version()`, `ce_dict_num_colors/combos()`, `ce_dict_color_rgb/name/lab(int)`, `ce_dict_combo(int id, uint8_t *size, uint8_t colors[CE_DICT_COMBO_MAX])`); `ce_ctx` solo cachea la tabla Lab para el match y los buffers de trabajo. Ninguna firma existente cambia (no hay migración en `ce_cli.c dict`, `test_dict.c` ni `ColorEngine.swift`). Lo nuevo:

```c
typedef struct ce_ctx ce_ctx;
typedef enum { CE_RGBA8 = 0, CE_RGBX8 = 1, CE_RGB8 = 2 } ce_pixel_format;
typedef struct { const uint8_t *pixels; int width, height, stride_bytes;
                 ce_pixel_format fmt; const uint8_t *mask; /* opcional, w*h */ } ce_image;
typedef struct { ce_lab lab; uint8_t rgb[3]; double weight; } ce_swatch;   /* Σ weight = 1 */
typedef struct { int k_init, max_iters, max_colors, max_side; double center_sigma,
                 merge_de, min_weight; int skin_rule; } ce_palette_opts;  /* center_sigma<=0: uniforme */
typedef struct { double kL, kC, kH, coverage_lambda, ambiguous_gap; } ce_match_opts;
typedef struct { uint16_t combo_id; double score; } ce_hit;
typedef struct { ce_swatch swatches[8]; int n_swatches; ce_hit hits[10]; int n_hits;
                 int ambiguous; } ce_result;

size_t      ce_ctx_size(void);
ce_ctx     *ce_ctx_init(void *mem, size_t size);
void ce_palette_opts_default(ce_palette_opts *o);
void ce_match_opts_default(ce_match_opts *o);
int  ce_palette_extract(ce_ctx *ctx, const ce_image *img, const ce_palette_opts *o,
                        ce_swatch *out, int cap);
int  ce_match(const ce_ctx *ctx, const ce_swatch *sw, int n, const ce_match_opts *o,
              ce_hit *out, int top_k, int *ambiguous);
int  ce_analyze(ce_ctx *ctx, const ce_image *img, const ce_palette_opts *po,
                const ce_match_opts *mo, ce_result *out);
int  ce_dict_nearest_color(ce_lab lab, double *de);   /* sin ctx: 159 llamadas a ce_dict_color_lab */
uint64_t ce_result_hash(const ce_result *r);   /* FNV-1a de bits; solo misma plataforma */
```

Los Lab de una combinación se obtienen con `ce_dict_combo` + `ce_dict_color_lab(index)`; no se añade una variante con `ce_lab labs[7]`.

**Presupuesto de `ce_ctx_size()`** (estimación de diseño, a confirmar en F2): imagen reducida 256×256×3 B ≈ 192 KiB; pesos en `double` 256×256×8 B = 512 KiB; histograma 32.768 bins × (peso `double` + ΣL,a,b `double` + conteo `uint32`) ≈ 1,1 MiB; caché Lab 159×24 B ≈ 4 KiB; cajas MMCQ y centros Lloyd < 16 KiB → **≈ 1,8 MiB; cota dura `ce_ctx_size() ≤ 2 MiB`**, acotada por un test Unity (`test_ctx_size_budget`) y comprobada también en WASM. Tres contextos simultáneos en el escaneo día 0 ≈ 6 MiB: dos órdenes de magnitud por debajo de una sola foto de 12 MP decodificada en RGBA8 (~48 MB), y en WASM cabe con `-sALLOW_MEMORY_GROWTH=1` (ya usado en `test_math`) sin tocar `INITIAL_MEMORY`. El buffer de entrada (≤ 1024 px) pertenece al llamante; el ctx solo guarda la versión reducida.

Score de C (colores c_j) frente a swatches s_i de peso w_i: `Σ_i w_i·min_j ΔE00(s_i,c_j) + λ·(1/|C|)·Σ_j min_i ΔE00(c_j,s_i)`; desempate por id; `ambiguous = 1` si `score[1] − score[0] < ambiguous_gap` (1,0 inicial; λ, gap y kL se calibran en L3). Errores negativos, nunca aborta.

**Entrada**: buffer sRGB de 8 bits no premultiplicado con stride, decodificado por la plataforma (iOS: `CGContext` con `CGColorSpace(name: .sRGB)` y `.noneSkipLast`; que esto convierta Display P3 → sRGB es el **comportamiento esperado de CoreGraphics, a verificar en F6**, no un hecho verificado en la investigación; web: `getImageData`). El downscale final lo hace el motor: iOS y web alimentan el clustering con la misma entrada.

**Determinismo y build**: pragma en cada `.c` (CI local: `grep -L "FP_CONTRACT OFF"` vacío); CMake añade `-ffp-contract=off -Wall -Wextra -Werror -Wpedantic`; **`CE_SANITIZE` es una opción con default OFF que solo `make test-asan` activa** (`-fsanitize=address,undefined`). `Package.swift` ya declara `.iOS(.v17), .macOS(.v14)` sin `unsafeFlags` (nada pendiente ahí). `make parity` ejecuta el mismo `ce` nativo y en node sobre 20 fixtures: |ΔLab|, |ΔE00| ≤ 1e-9, mismo top-3 y mismo `ambiguous`; `ce_result_hash` solo para determinismo run-a-run en la misma plataforma. **Enlace WASM**: el actual (`-sNODERAWFS=1 -sEXIT_RUNTIME=1`) sirve solo para node y paridad; la app web (§11.E) necesita un segundo enlace (`-sMODULARIZE=1`, `-sEXPORTED_FUNCTIONS=[...]`, `-sEXPORTED_RUNTIME_METHODS`, sin `NODERAWFS`), fuera del MVP. **CLI `ce`** (`engine/tools/ce_cli.c`; hoy `version|lab|de2000|convert|dict`, sin decodificador de imagen): en F2 se añade `ce palette img.ppm [--mask m.pgm] --json`, `ce match img.ppm --top 3 --json`, `ce analyze`, `ce batch`. Entrada P6/P5 o `.rgba` crudo producidos por `oracle/tools/to_ppm.py` (Pillow, único decodificador). El parser P6/P5 se factoriza en `engine/tools/ce_pnm.c` (fuera del target SPM) para poder compilarlo también en el fuzz loop (§6, capa 2): es entrada no confiable con dimensiones y stride tomados del fichero.

## 6. Harness de validación

`oracle/` (uv, Python 3.12) + `harness/`. `make eval` (existe: `oracle.eval`) = `check-protected` → `make test` → L1 → L2 → L3 (dev, y holdout si hay semilla) → L4 (si hay fotos) → `make ios-lint` (desde F6) → `harness/out/scorecard.{json,md}` con `ce_version`, `dict_version`, `np.__version__`; exit 1 si falla un umbral de `harness/thresholds.json`. `make eval-fast` = L1 + L2 + 10 % de L3 (< 2 min); **L4 queda fuera de su alcance por definición** (no cuenta como `not implemented`).

**Semántica de salida de `make eval` por capa** (a implementar en `eval.py` en F3; hoy solo distingue `pass`/`fail`/`not implemented`):

| Situación | Estado en scorecard | Exit |
|---|---|---|
| Capa no implementada | `not implemented` | 1 |
| Capa implementada y en umbral | `pass` | 0 |
| Capa implementada fuera de umbral o con error | `fail` | 1 |
| Capa implementada sin datos: L4 sin `$COLORSAPP_GOLDEN_DIR`; holdout de L3 sin `COLORSAPP_HOLDOUT_SEED` | `skipped` + motivo + aviso destacado | 0 |

`skipped` solo admite esos dos motivos (nunca "sin tiempo" ni "sin CLI"); el gate de F10 exige un scorecard sin ningún `skipped`. Para que L4 pueda ser `skipped` desde F3, el runner mínimo de L4 (`oracle/l4/run.py`: lectura del `manifest.json`, recall@k contra consenso, cuota máxima) se crea en F3; SAM, `visionmask` y las variantes llegan en F9.

- **Capa 1** (existe): `test_math` (blanco/negro, goldens ≤1e-9, Bradford, round-trip 16,7 M exacto, simetría) y `diff-oracle` (100.000 colores contra colour con `use_derived_matrix_RGB_to_XYZ=True`, 1e-9; con `--fast` 10.000). **Nota**: no se inspeccionó en el código fuente de colour 0.4.7 que use ε=216/24389 y κ=24389/27 exactos (`colour.constants` no expone CIE_E/CIE_K); la evidencia del gate estricto es el acuerdo medido a ~1e-13 (goldens: `engine/README.md`; diff-oracle de hoy: max |Δa| = 1,17e-13 en 10.000 colores). **Sharma**: `test_math.c` (existe) gatea los **34** pares a 1e-4 en ambos órdenes y pasa en nativo y WASM (par 14 = 4,8045 en ambos); el gate de **33** pares + par 14 informativo (aceptando 4,8045 o 4,7461, discontinuidad |Δh'|=180° que colour excluye) vive en `eval.py`, sin tocar `test_math.c`. Ya en `eval.py`: laxo contra `skimage.rgb2lab` ≤ 0,05 ΔE76 (2.000 colores; hoy 0,0148); kL=2 contra `textiles=True` (200 pares); C=0 y hue ≈ 180° sin NaN; cruce de `dict_version` y `make dict-check`.
- **Capa 2** (`oracle/synth/compose.py`, `test_l2_palette.py`): 200 composiciones (bloques 50/30/20 y 40/35/25, colores con ΔE00 mutuo > 15): cada color ΔE00 < 2, peso ± 3 puntos. Invariancias: barajar píxeles → **bit-idéntico solo con `center_sigma ≤ 0` y conteos enteros por bin**; con peso al centro → mismo conjunto ΔE < 1 y mismo top-3; escala 0,5×/2× → ΔE < 1; espejo/rotación → ΔE < 0,5; ruido σ=2 → ΔE < 1,5; dos ejecuciones → mismo hash. Fuzz loop propio (Apple clang 21 no trae libFuzzer): PRNG con semilla, 10 min, bajo ASan/UBSan, 0 crashes, con **dos entradas**: (1) `ce_palette_extract` con dimensiones/stride/máscara aleatorios; (2) el parser P6/P5 de `ce_pnm.c` con cabeceras y cuerpos aleatorios o truncados (dimensiones absurdas, `maxval` ≠ 255, tamaño de fichero menor que w×h×3), que debe devolver error sin leer fuera del buffer.
- **Capa 3** (`oracle/synth/wada_gen.py`, `test_l3_match.py`): 10 variantes deterministas por combinación (semilla = id·1000 + v): proporciones, textura opensimplex, sombreado, iluminante A/D75/F2 (matrices de `golden_bradford.tsv`), JPEG q ∈ {10,30,60,95}, exposición ±1 EV, saturación ×0,7–1,3, fondo distractor 40 %. Métricas por degradación: recall@1/@3, entropía, cuota de clase máxima, tasa de `ambiguous`; columnas kL=1|2, skin on|off. Umbrales iniciales (ya en `thresholds.json`, `promoted_by: null`): limpio @1 ≥ 0,95 / @3 ≥ 0,99; JPEG q10 @1 ≥ 0,85; iluminante @3 ≥ 0,80; exposición @1 ≥ 0,75; distractor @3 ≥ 0,75; **cuota máxima ≤ 5 %** (el 30 % del contexto es para fotos reales; sobre 348 clases balanceadas sería vacío). **Holdout ciego**: variantes 10–11 generadas con `COLORSAPP_HOLDOUT_SEED`, que solo [USUARIO] exporta al ejecutar `make eval`; scorecard con dev y holdout lado a lado; gate: holdout ≥ dev − 3 puntos; sin semilla → `skipped`.
- **Capa 4** (`oracle/l4/`): fotos en `$COLORSAPP_GOLDEN_DIR` (fuera del repo) con `manifest.json` (sha256, tags `negro|denim|gris|interior|fondo-sucio|blanco`, etiquetas de 3 jueces, consenso por mayoría, Fleiss κ). **Formato admitido: solo PNG o JPEG q95 en sRGB de 256 px** (las copias que escribe "Exportar diagnóstico", §7.8); `make golden-check` rechaza HEIC y cualquier fichero sin perfil sRGB, y `to_ppm.py` falla con mensaje claro ante HEIC (Pillow no lo abre sin `pillow-heif`). Si en F8 el usuario quiere originales a resolución completa, se añade `pillow-heif` al `pyproject` y a `to_ppm.py` como decisión explícita. Oráculos offline: SAM 2.1 tiny (Apache-2.0) para máscara de prenda (`make_masks.py`) y `tools/visionmask` (CLI Swift macOS con `VNGeneratePersonSegmentationRequest`). Métricas **por tag y agregadas**: recall@1/@3 contra consenso; ΔE00 del color dominante vs máscara SAM ≤ 5 en ≥ 70 %; cuota máxima ≤ 30 %; variantes máscara Vision, kL=2, regla de piel, gray-world.

**Anti-Goodhart** (`CLAUDE.md` + `harness/PROTECTED.txt`, ambos existen): `make check-protected` falla si el árbol (diff contra HEAD, staged o untracked) toca una ruta protegida sin `COLORSAPP_ALLOW_PROTECTED=1` o si el sha256 no cuadra con `PROTECTED.sha256`; el hook pre-commit (instalado) lo ejecuta; es detección, no prevención. Protegidas: `harness/thresholds.json`, `harness/golden/**`, `engine/tests/data/**`, `oracle/oracle/reference.py`, `oracle/synth/**` mientras se itera el motor (cambios al generador en fase propia con re-baseline), `harness/label/**`, `data/wada/{names.es.json, overrides.json, source/**}`, `$COLORSAPP_GOLDEN_DIR`.

**Regla de bootstrap de rutas protegidas** (nueva; es exactamente el estado actual del árbol): los ficheros que el agente crea **por primera vez** dentro de un glob protegido (`compose.py`, `wada_gen.py`, goldens de `harness/golden/`, `names.html`, `index.html`, `thresholds.json`, `golden_*.tsv`) se entregan como parte de la fase que los crea; **al cierre de esa fase [USUARIO] los revisa y ejecuta `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash` (+ commit)**. Hasta entonces `make check-protected` falla por diseño, y con él el hook y `make eval`: el agente lo reporta, no lo esquiva (nunca `--no-verify`, nunca exportar la variable por su cuenta). A partir de la promoción, cualquier cambio posterior en esos ficheros vuelve a ser una propuesta (`harness/out/thresholds.proposed.json`, `golden-update` con motivo). Alternativa descartada: meter `oracle/synth/**`, `harness/golden/**` y `harness/label/**` en `PROTECTED.txt` solo en el commit de baseline de F3; se prefiere la promoción por fase porque deja rastro en `PROTECTED.sha256` desde el primer día.

Umbrales: el agente escribe `harness/out/thresholds.proposed.json`; solo el usuario promueve con `make thresholds-promote` (rellena `promoted_by`). Golden files (`harness/golden/{palettes_20,match_50}.json` + fixtures PPM) solo cambian con `make golden-update GOLDEN_REASON="…"`, anotado en `harness/CHANGELOG.md` (existe). `engine/BENCHLOG.md` (a crear en F1): una línea por iteración. Presupuesto por fase de iteración (20 iteraciones o 5 días) con escalera fija: peso al centro → máscara Vision → kL=2 → regla de piel → parar y reportar.

## 7. App iOS MVP

Pestañas **Hoy**, **Rejilla**, **Explorar**, **Ajustes**. Sin red: no hay CI en el repo, así que la regla se ejecuta como target **`make ios-lint`** (`grep -rE "URLSession|NWConnection|CFNetwork" ios/` debe dar 0 líneas; falla si no), incluido en `make eval` (desde F6) y en `make release-week` (desde F0).

1. **Diccionario**: `dictionary.json` + `names.es.json` del bundle → structs Swift; `dict_version` comprobado contra `ce_dict_version()`.
2. **Captura y match**: `PhotosPicker` (iOS 16) o `UIImagePickerController(.camera)` → `CGImageSource` → `CGContext` sRGB `.noneSkipLast` ≤ 1024 px (conversión Display P3 → sRGB por CoreGraphics: esperada, se verifica en F6 con `EngineParityTests`) → `ce_analyze` en `Task.detached` con un `ce_ctx` por tarea. Toggle "máscara de persona" (`VNGeneratePersonSegmentationRequest(.balanced)`), apagado por defecto.
3. **Resultado**: foto, swatches con peso, top-1 grande y top-2/3 pequeños, "entre A y B" si `ambiguous`; nombre o "Nº 012", número, colección; "sí, es eso / no" → tabla `feedback`; "Desbloquear".
4. **Tarjeta**: `ImageRenderer(scale: 3)` → `ShareLink(item:preview:)`, 1080×1350.
5. **Rejilla**: `LazyVGrid` de 348 casillas, gris o coloreada, contador "41/348", tap → detalle.
6. **Escaneo día 0**: `PHPhotoLibrary.requestAuthorization(for: .readWrite)`; con `.authorized`: `PHFetchOptions(fetchLimit: 200, creationDate desc)`, `PHImageManager.requestImage(targetSize: 256×256, .aspectFill)` con `deliveryMode = .fastFormat`, `resizeMode = .fast`, `isNetworkAccessAllowed = false` (contador de omitidas), `TaskGroup` de 3 con un `ce_ctx` cada uno; resumen tipo Wrapped; registra `scan.done n ms`. **El umbral "200 fotos < 120 s en el 13 mini" es provisional** (la investigación no mide el coste de PHImageManager): se mide en la primera build de F7 en el 13 mini, ya emparejado, y se fija antes de F8. Con `.limited`: `PhotosPicker(maxSelectionCount: 200)` y `PHPhotoLibraryPreventAutomaticLimitedAccessAlert` en Info.plist.
7. **Explorar**: colecciones (curadas o por tamaño) → detalle; `ColorPicker` → `ce_dict_nearest_color` y combinaciones que lo contienen; "Extraer de una foto" muestra la paleta sin match.
8. **Ajustes**: toggle máscara, versiones, "Rehacer escaneo", "Exportar diagnóstico" (zip con `feedback.csv`, tiempos y **copias de 256 px en PNG sRGB** (mismos píxeles que vio el motor, ya convertidas por el `CGContext` sRGB; nunca HEIC) de las fotos marcadas, solo por acción explícita, vía `ShareLink`/AirDrop) y "Acerca de" con atribuciones.

**Contenido de "Hoy" por build**: en la build de F6 (sin escaneo día 0) muestra el botón de captura/picker, la lista de los últimos `scans` con su veredicto y un aviso "El escaneo del carrete llega en la próxima build"; en F7 pasa a mostrar el resumen Wrapped del escaneo y el progreso "41/348".

Persistencia GRDB (`ios/ColorsApp/DB/Schema.swift`, migración v1, WAL), sync-ready: `scans(id UUIDv7, asset_local_id, top1..top3, scores, palette_json, ambiguous, engine_version, dict_version, scanned_at)`, `unlocks(combo_id PK, first_seen_at, source)`, `feedback(id, scan_id, verdict, created_at)`, `settings`; todas con `updated_at, deleted_at, rev, dirty`. Info.plist: `NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription`.

## 8. Fases

**Antes de cualquier fase: reproducir el entorno** (`docs/SETUP.md` + `make bootstrap`, a crear en F0; `make doctor` los referencia):
1. Xcode 27 instalado y seleccionado: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` (**solo el usuario**: `CLAUDE.md` prohíbe al agente `sudo` y `xcode-select -s`; alternativa sin sudo: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`), `xcodebuild -license accept` si lo pide.
2. `brew install cmake emscripten uv xcodegen` (versiones verificadas: cmake 4.4.3, emcc 6.0.9, uv 0.12.13, xcodegen 2.46.0).
3. node ≥ 20 (hoy v24.21.0 vía nvm; `make doctor` solo comprueba que `node` exista y muestra su versión; brew tiene 26.8.2 pero el PATH resuelve el de nvm: no cambiarlo sin re-verificar `make test-wasm`).
4. `uv sync --project oracle` (Python 3.12 fijado en `oracle/.python-version`; `requires-python >=3.12,<3.15`; el 3.9.6 del sistema no sirve).
5. `make hooks` (instala el pre-commit) y `make doctor` (exit 0).

Regla general de fases: antes de empezar una, `git status` limpio o conocido, `make doctor` exit 0 y `make check-protected` en el estado esperado; al cerrar una que haya creado ficheros protegidos, [USUARIO] ejecuta `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash` y `make check-protected` debe salir 0.

| F | Objetivo | Entregables | Criterio de salida verificable | Quién | Tam. |
|---|---|---|---|---|---|
| 0 | Cimientos, firma y stub en los dos iPhones | **HECHO** (verificado 2026-09-14): 2 commits base; `CLAUDE.md`; `harness/PROTECTED.txt` + `PROTECTED.sha256` + `check_protected.py` + hook pre-commit instalado (`make hooks`); `make doctor` (`mk/foundations.mk`); `ios/project.yml` + stub que escribe `Documents/launches.txt`; `Signing.example.xcconfig`; `mk/ios.mk` (`ios-generate`, `ios-build-sim`, `ios-build-device-nosign`, `ios-test-sim`, `ios-run-sim`, `ios-install`); `docs/DECISIONS.md`, `docs/RELEASE.md`; `harness/out/stub.png` de `ios-run-sim`. **PENDIENTE agente**: commit de lo untracked (cuando lo pida el usuario); `docs/SETUP.md` + `make bootstrap`; `make ios-lint`; `make release-week` con la escalera de §3; alinear `docs/RELEASE.md` con §3. **PENDIENTE [USUARIO]**: `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash` (+ commit); Apple ID en Xcode; Team ID en `Signing.xcconfig` (hoy `REEMPLAZAR`); primer `make ios-install DEVICE=00008110-000E65AC1E69801E` real (fallback ⌘R); emparejar el iPhone de la esposa; prueba de conservación de datos a los 7 días | `make doctor` exit 0 (hecho); `make test`, `make test-wasm` y `pytest` verdes; `make ios-build-device-nosign` exit 0 (hecho); test negativo de `check-protected` (tocar un golden → exit 1); **`make check-protected` exit 0 tras la promoción del usuario**; `make ios-lint` exit 0; `find-identity` lista Apple Development; `devicectl list devices` muestra 2 iPhones; **salida real del primer `make ios-install` pegada en `docs/RELEASE.md`**; stub abre en ambos y a los 7 días, tras reinstalar, `launches.txt` no vuelve a 1 | agente + [USUARIO] (Apple ID; iPhone de la esposa) | M |
| 1 | Diccionario final y harness base | **HECHO**: `overrides.json` (vacío), `collection` null por combinación, `dict_version` + `status` en `dictionary.json`, `ce_dict_version()` en `ce_dict.c`, `golden_wada_lab.tsv`, `test_dict.c`, `thresholds.json` (`proposed_by: agent`, `promoted_by: null`), `metrics.py`, `eval.py` con L1 + scorecard, `names.py` + `make names-todo`/`names-html` + `harness/label/names.html`, `harness/CHANGELOG.md`. **PENDIENTE agente**: `dict-check` con recuento explícito 159/157 nombres y 27/348 mono-capítulo; `engine/BENCHLOG.md` (cabecera); `test_metrics` en verde (1 fallo hoy, fichero en edición). **PENDIENTE [USUARIO]**: aceptar las 2 erratas de nombre en `overrides.json`; promover `thresholds.json`; decidir libro/ICC; `protected-hash` | `make dict-check` verde e imprimiendo 348, 120/120/108, 1.032, 159/157, 27/348; `make eval` imprime L1 `pass` y L2–L4 `not implemented` con exit 1 (hecho: scorecard de hoy); `ce dict --version` == `dict_version` == cabecera del golden (hecho); `pytest` sin fallos; **`make check-protected` exit 0 tras la promoción del usuario** | agente; [USUARIO] acepta erratas de nombre, promueve umbrales, decide libro | M |
| 2 | Capa 2 verde | `ce_ctx.c`, `ce_image.c`, `ce_palette.c`, `ce_pnm.c` + `ce palette`, `to_ppm.py`, `compose.py`, `test_l2_palette.py`, `fuzz_palette.c` (paleta + parser PNM), `test_ctx_size_budget`, `eval-fast` | L2 verde con umbrales de §6; `ce_ctx_size() ≤ 2 MiB` en nativo y WASM; `make fuzz` 10 min bajo ASan/UBSan sin crash en las dos entradas; `make eval-fast` < 2 min; **`make check-protected` exit 0 tras la promoción** (`compose.py` es ruta protegida) | agente; [USUARIO] promueve | M |
| 3 | Match v0 y línea base L3 | `ce_match.c`, `ce match|analyze|batch`, `wada_gen.py`, `test_l3_match.py`, runner mínimo de L4 (`oracle/l4/run.py`), semántica `skipped` en `eval.py`, primera entrada en `BENCHLOG.md`, `thresholds.proposed.json`, goldens `palettes_20`/`match_50` | L3 dev completo con scorecard por degradación; `make eval` exit 0 en dev con holdout `skipped` (sin semilla) y L4 `skipped` (sin `$COLORSAPP_GOLDEN_DIR`), ambos con aviso en el scorecard; `make eval-fast` exit 0; **`make check-protected` exit 0 tras la promoción** (`wada_gen.py`, goldens) | agente; [USUARIO] promueve | M |
| 4 | L3 en umbral con holdout | Iteraciones del motor dentro del presupuesto y la escalera de §6; una línea por iteración en `BENCHLOG.md` | `COLORSAPP_HOLDOUT_SEED=… make eval` exit 0: umbrales de §6, holdout ≥ dev − 3, cuota ≤ 5 %; L4 puede seguir `skipped` | agente; [USUARIO] exporta la semilla y ejecuta | L |
| 5 | Paridad WASM | `harness/wasm/run_parity.js`, `make parity` | `make parity` exit 0: Lab/ΔE ≤ 1e-9, mismo top-3 y `ambiguous` en 20 fixtures; si falla, `ce_libm.c` | agente | S |
| 6 | App: motor, diccionario, resultado, feedback, export | `project.yml` completo, GRDB v1, pantallas 1–4, 7, 8, "Hoy" en su versión F6 (§7), `EngineParityTests`, `ios-lint` dentro de `eval` | `xcodebuild … CODE_SIGNING_ALLOWED=NO build` OK; XCTest: `ce_analyze` sobre 5 PPM del bundle == `match_50.json`; **PNG Display P3 con tolerancia** (≤ 1/255 por canal frente al PPM de `to_ppm.py`, mismo top-3, ΔE00 de cada swatch ≤ 0,5) y la diferencia real CoreGraphics vs LittleCMS medida y anotada en `BENCHLOG.md`; `make ios-lint` = 0 líneas | agente | M |
| 7 | App: escaneo día 0, rejilla, tarjeta | PhotoKit batch, `unlocks`, `ShareCardView`, `scan.done`; `make ios-test-sim` ejecuta **`xcrun simctl privacy $(SIM_UDID) grant photos com.andreseloy.colorsapp`** antes del test (comando verificado en `xcrun simctl help privacy`) | XCTest en simulador con `xcrun simctl addmedia` (20 sintéticos) tras el `grant photos`: `unlocks` > 0 y top-1 igual al CLI; `.limited` cae al picker sin crash; **medición de `scan.done` para 200 fotos en el 13 mini registrada en `BENCHLOG.md`** y umbral fijado a partir de ella (120 s es la cifra provisional) | agente | M |
| 8 | Uso real y set dorado | `make release-week` en uso, `make feedback-report`, `harness/label/index.html` (foto + top-10 + "ninguna"), `manifest.json`, `make golden-check` | `feedback-report` lee zips de ambos teléfonos con `scan.done` bajo el umbral fijado en F7; `golden-check`: ≥ 50 fotos (objetivo 100) **solo PNG/JPEG sRGB de 256 px, sin HEIC**, con todos los tags, sha256 correctos, 3 etiquetas por foto, κ reportado; **`make check-protected` exit 0 tras la promoción** (`index.html`) | [USUARIO] + esposa + tercer juez; agente (tooling) | M |
| 9 | Capa 4 | `make_masks.py` (SAM 2.1), `tools/visionmask`, `test_l4_real.py`, variantes en el runner de L4 | Scorecard L4 por tag: recall@3 ≥ 0,70, cuota ≤ 30 %, ΔE vs SAM; variantes tabuladas; flag de máscara decidido con datos | agente | M |
| 10 | Cierre del MVP | `docs/feel-right.md` | `feedback-report` sobre ≥ 50 valoraciones de ambos teléfonos: "sí" ≥ 70 % y cuota de la combinación más frecuente ≤ 30 %; `make eval` exit 0 **sin ningún `skipped`**; si no, volver a F4/F9 | [USUARIO] decide pagar el ADP | S |

F6–F7 arrancan tras F5, en paralelo con la curación de nombres; F8 solo necesita F7.

## 9. Estructura del repositorio

```
colorsApp/
├── CLAUDE.md                    # existe: reglas del agente, rutas protegidas
├── Makefile                     # existe: test, test-asan, test-wasm, golden, diff-oracle, swift-test, dict, dict-check; incluye mk/*.mk
├── mk/                          # existe: foundations.mk (doctor, check-protected, protected-hash, hooks), harness.mk (eval, eval-fast, names-todo, names-html), ios.mk
│                                #   a crear: bootstrap, ios-lint, release-week (F0); fuzz, parity (F2/F5); golden-update, thresholds-promote (F3); feedback-report, golden-check (F8)
├── engine/                      # existe: Swift Package + CMake
│   ├── Package.swift            # CColorEngine (C) + ColorEngine (Swift) + ColorEngineTests; iOS 17 / macOS 14
│   ├── CMakeLists.txt           # lib, CLI ce, tests, CE_SANITIZE (OFF), emcmake
│   ├── README.md                # decisiones numéricas y medición libm nativo/WASM
│   ├── Sources/CColorEngine/    # ce_math.c, ce_dict.c, ce_dict_data.h, include/ce/ce.h (existen); ce_ctx.c, ce_image.c, ce_palette.c (F2); ce_match.c (F3)
│   ├── Sources/ColorEngine/     # ColorEngine.swift (existe); CGImage → ce_image (F6)
│   ├── tools/                   # ce_cli.c (existe); ce_pnm.c (F2)
│   ├── tests/                   # test_math.c, test_dict.c, unity/, data/ (protegido), ColorEngineTests/ (XCTest Swift) — existen; test_palette.c, fuzz_palette.c (F2)
│   └── BENCHLOG.md              # a crear en F1
├── data/wada/                   # existe: source/, dictionary.json, errata.json, overrides.json, names.es.json, CONVERSION_CHECK.md, README.md; names.suggested.json (cuando el agente proponga)
├── oracle/                      # existe: uv, Python 3.12
│   ├── oracle/                  # reference.py (protegido), gen_golden.py, diff_oracle.py, build_dictionary.py, eval.py, metrics.py, names.py — existen
│   ├── synth/                   # a crear: compose.py (F2), wada_gen.py (F3)
│   ├── l4/                      # a crear: run.py (F3), make_masks.py, kappa.py (F9)
│   ├── tools/                   # a crear: to_ppm.py (F2)
│   └── tests/                   # test_reference, test_dictionary, test_metrics, test_names — existen; test_l2..l4 (F2/F3/F9)
├── harness/                     # existe: thresholds.json, PROTECTED.txt, PROTECTED.sha256, check_protected.py, hooks/pre-commit, CHANGELOG.md, label/names.html, out/ (ignorado)
│   ├── golden/                  # a crear en F3 (protegido)
│   ├── wasm/                    # a crear en F5
│   └── label/index.html         # a crear en F8 (protegido)
├── tools/visionmask/            # a crear en F9: CLI Swift macOS (Vision)
├── ios/                         # existe: project.yml, Signing.example.xcconfig, Signing.xcconfig (ignorado), ColorsApp/{ColorsAppApp, ContentView, EngineFacts, LaunchCounter, Info.plist}, ColorsAppTests/
│                                #   F6+: ColorsApp/{App,Views,DB,Engine,Resources}
└── docs/                        # existe: DECISIONS.md, RELEASE.md; a crear: SETUP.md (F0), SHOTLIST.md (F8), feel-right.md (F10)
```

## 10. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Match no creíble con negro, denim, gris, interior, fondo sucio | Métricas por tag en L4; SHOTLIST con esos casos; variantes medidas antes de encender; escalera con presupuesto; gate F10 |
| Pares Wada a ΔE00 < 5 (Isabella–Maple 2,9) hacen ambiguo el top-1 | Match sobre combinaciones completas; flag `ambiguous`; recall@3 como métrica principal |
| 0 identidades de firma; ruta de firma nunca ejercitada; iPhone de la esposa desconocido; perfil de 7 días | Prerrequisito bloqueante y stub en F0 con salida real pegada en RELEASE.md; fallback ⌘R; `make release-week`; F0 verifica que reinstalar conserva Documents; SideStore plan B (ocupa 1 slot) |
| Ficheros protegidos creados por el agente dejan `check-protected` (y `eval`, y el hook) en rojo | Regla de bootstrap de §6: promoción por [USUARIO] al cierre de cada fase; el agente reporta el rojo, no lo esquiva |
| 4 CMYK sin cotejar y sin perfil SWOP | `errata.json` + `overrides.json`; `pending_icc`; gate ≤ 1/255 con la LittleCMS de Pillow; `book-verified: no` |
| Paridad nativo/WASM por libm | Pragma + `make parity` a 1e-9 + desempate por id; `ce_libm.c` si diverge |
| Goodhart del agente | `check-protected` + hash + hook; holdout con semilla fuera del repo; `synth/` protegido; umbrales solo por promoción del usuario; golden con motivo; `skipped` solo por dos motivos y prohibido en F10; set dorado humano |
| Carrera de datos en el escaneo batch; memoria de 3 contextos | `ce_ctx` por tarea, sin estáticos; `ce_ctx_size() ≤ 2 MiB` con test; test con `TaskGroup` bajo Thread Sanitizer |
| PhotoKit `.limited` o fotos en iCloud; Display P3 tratado como sRGB; coste de 200 fotos desconocido | Picker de 200 como fallback; `isNetworkAccessAllowed=false` con contador; `CGContext` sRGB explícito y `EngineParityTests` con PNG P3 y tolerancia; `scan.done` medido en F7 antes de fijar el umbral |
| Privacidad de fotos; riesgo legal residual (Art. 12, URAA) | Sin red (`make ios-lint` = 0); fotos fuera del repo con sha256 y solo en PNG/JPEG sRGB 256 px; export solo por acción explícita; solo datos, nunca escaneos; revisar antes de App Store |

## 11. Post-MVP

**A — Favoritos y colecciones locales (sin pagar)**: las tablas GRDB ya llevan `id UUIDv7, updated_at, deleted_at, rev, dirty`; se añaden `favorites`, `palettes`, `collections` de usuario y `outbox(mutation_id, op, payload)`. La UI sigue leyendo solo SQLite.

**B — Servidor propio (sin pagar)**: Hummingbird 2.26 (Apache-2.0) o Vapor 4.122 (MIT) enlazando `CColorEngine` como target SPM; si el usuario insiste en C puro, Kore 4.3.0 (ISC) o civetweb (MIT), nunca Mongoose (GPLv2) ni facil.io. Postgres, migraciones, `dictionary.json` + `names.es.json` como seed curado.

**C — Cuentas y roles (sin pagar)**: magic link/OTP con SMTP propio (Supabase exige SMTP propio por su límite de 2 emails/hora; Firebase no sirve: 5 emails/día), JWT con claim `role` validado en cada `/admin/*` (allowlist de algoritmo, `iss`, `aud`, `exp`). La guideline 4.8 no exige Sign in with Apple con cuentas propias. Panel admin web que edita nombres y colecciones y publica un nuevo `dict_version`.

**D — Sync offline-first (sin pagar)**: push/pull tipo Replicache con `lastMutationId` y cursor; LWW por `updated_at` en datos de usuario, el servidor manda en curado; probado en los dos iPhones re-firmando cada 7 días. PowerSync como plan B (SDK Swift Apache-2.0, servicio FSL, exige MongoDB/Postgres).

**E — App web**: `ce.wasm` + `dictionary.json`, `<input type=file>` y `getImageData`; sin escaneo de carrete (no hay API); la paridad de F5 garantiza los mismos resultados. **El artefacto de F5 no sirve tal cual**: `ce.js` está enlazado con `-sNODERAWFS=1 -sEXIT_RUNTIME=1` para node; la web necesita un segundo target de enlace (`-sMODULARIZE=1`, `-sEXPORTED_FUNCTIONS=[_ce_ctx_size,_ce_ctx_init,_ce_analyze,…]`, `-sEXPORTED_RUNTIME_METHODS`, sin `NODERAWFS`), con la misma fuente C y el mismo `make parity` sobre él. Android por la misma vía.

**F — Pagar el Developer Program** cuando la app "se sienta bien" (gate F10): TestFlight, APNs (silent push para disparar pull), Sign in with Apple solo si se añaden logins sociales. CloudKit no (no casa con roles admin).

## 12. Lo que se necesita del usuario ahora

1. [USUARIO] Iniciar sesión con el Apple ID en Xcode > Settings > Apple Accounts hasta que `security find-identity -v -p codesigning` liste "Apple Development"; copiar el Team ID a `ios/Signing.xcconfig` (hoy `REEMPLAZAR`); ejecutar el primer `make ios-install DEVICE=00008110-000E65AC1E69801E` (o ⌘R) y pegar la salida en `docs/RELEASE.md`.
2. [USUARIO] Modelo y versión de iOS del iPhone de su esposa (≥ 17) y traerlo una vez con cable para emparejar, activar Developer Mode y confiar el Mac. El 13 mini ya está verificado.
3. [USUARIO] Aprobar de una vez los **tres desvíos** de §2 (nombres no bloqueantes; fotos reales tras la app; valores `provisional` sin libro/ICC) y la semántica `skipped` de `make eval` (§6).
4. [USUARIO] Cerrar el bootstrap de rutas protegidas: revisar `overrides.json`, `golden_wada_lab.tsv`, `names.html`, `thresholds.json` y ejecutar `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash` (+ commit) para que `make check-protected` salga 0; repetir al cierre de F2, F3 y F8.
5. [USUARIO] Confirmar bundle ID (`com.andreseloy.colorsapp`), nombre de la app e idioma de la UI.
6. [USUARIO] Decidir si compra el libro Seigensha Vol. 1 (1.500 ¥) y si descarga los perfiles ICC de Adobe (`COLORSAPP_SWOP_PROFILE`); sin ambos, el MVP sale `provisional`.
7. [USUARIO] Aceptar las 2 erratas de nombre (`overrides.json`) y promover los umbrales iniciales de `harness/thresholds.json` (`promoted_by`).
8. [USUARIO] Guardar fuera del repo `COLORSAPP_HOLDOUT_SEED` y `COLORSAPP_GOLDEN_DIR`; confirmar si el repo será privado; autorizar el commit de lo que hoy está sin seguimiento.
9. [USUARIO] Empezar a nombrar combinaciones con `harness/label/names.html` (ya existe; `make names-todo` lista pendientes); decidir si quiere colecciones temáticas desde el MVP.
10. [USUARIO] Reclutar al tercer juez del set dorado (F8) y confirmar que las fotos de su esposa, reducidas a 256 px en PNG sRGB, pueden usarse fuera del repo.
11. Sin bloquear: ¿servidor post-MVP en Swift (Hummingbird/Vapor) o en C puro (Kore/civetweb)?
