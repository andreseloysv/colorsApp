# BENCHLOG del motor

Una línea por iteración de rendimiento o de calidad del motor (PLAN.md §6:
"una línea por iteración"). `make bench-palette` imprime `PERF_1024_RGBA_MS`
(1024×1024 RGBA con gradiente + ruido, opciones por defecto, mejor de 5, nativo
-O2, sin sanitizers; la cota de 150 ms la exige el propio `test_palette`).
Máquina de referencia: Apple M4 Pro, Apple clang 21, cmake 4.4.3, emcc 6.0.9,
node 24.

| Fecha | Fase | Cambio | PERF_1024_RGBA_MS nativo | ASan/UBSan | WASM (node) | k_init=64 nativo | ce_ctx_size | Fuzz | Notas |
|---|---|---|---|---|---|---|---|---|---|
| 2026-09-15 | F2 | Capa 2 inicial: box-downscale + histograma 5 bits + MMCQ + Lloyd + fusión ΔE00 | 2.27 ms | 6.08 ms | 2.61 ms | 6.21 ms | 2 044 176 B (1.949 MiB) | 120 s ASan/UBSan: 43 040 it/entrada (359 it/s), 0 fallos | `make test`, `test-asan`, `test-wasm`, `swift-test` 7/7, 7/7, 7/7, 11/11 en verde |
| 2026-09-15 | F5 | `ce_libm.c`: cbrt/pow/exp/atan2/sin/cos de musl 1.2.6 sin FMA (mismos bits nativo/WASM; `make parity` 20/20 byte a byte) | 2.70 ms | 5.99 ms | 2.72 ms | 7.48 ms | 2 044 176 B (sin cambio) | — | pow/cbrt de musl algo más lentos que los de Apple (+0.4 ms en 1024²); `test_math` +3 tests (golden de bits `HASH_LIBM` e2a522f84cbcb366, ≤ 2 ulp vs libm del sistema: medido 1 ulp, 16 838/18 000 idénticos en nativo, 18 000/18 000 en WASM) |

## Capa 3 (match)

`make bench-match` imprime `MATCH_MS` (ce_match con 5 swatches sobre las 348
combinaciones, mejor de 200), `ANALYZE_1024_MS` (ce_analyze de 1024×1024 RGBA
con gradiente + ruido, mejor de 5) y `RECALL_EXACT` (348 imágenes de bloques
exactos). Cotas de `test_match` en nativo -O2: `MATCH_MS` < 2, `ANALYZE_1024_MS`
< 10; en ASan y WASM solo se miden.

| Fecha | Fase | Cambio | MATCH_MS nativo | ASan/UBSan | WASM (node) | ANALYZE_1024_MS nativo | ASan/UBSan | WASM (node) | Recall exacto (bloques / paletas) | Ambiguas (gap 1.0) | Notas |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-15 | F3 | Match v0: score ajuste + λ·cobertura (ΔE00), 348 sin poda, top-k por inserción con desempate por id; `ce match` / `analyze` / `batch` | 0.034 ms | 0.046 ms | 0.060 ms | 2.24 ms | 6.23 ms | 2.78 ms | 348/348 · 348/348 | 0 (gap 0.5: 0, 2.0: 0, 5.0: 2; gap mínimo 4.38) | score 0 exacto en 206/348 bloques (WASM 195/348), resto ≤ 1.6e-14 (media de Lloyd); paridad nativo/WASM en 3 fixtures: mismo top-3 y `ambiguous`, Δ máx 5.6e-14; `make test`, `test-asan`, `test-wasm` 13/13 cada uno, `swift-test` 15/15 |
| 2026-09-15 | F5 | Match v0 + `ce_libm.c` (sin cambio de algoritmo) | 0.047 ms | 0.085 ms | 0.058 ms | 2.63 ms | 6.16 ms | 2.81 ms | 348/348 · 348/348 | 0 | score 0 exacto en 195/348 bloques en nativo y WASM (idénticos); `make parity` 20/20 bit-exactas, hash igual 20/20 |
| 2026-09-15 | F3/F5 (corrección, ADR-009) | Match v1: mínimo sobre 25 hipótesis (identidad; exposición ±1 EV en pasos de 0.5, penalización 2.0 ΔE/EV; iluminante A/D50/D75/F2 → D65, penalización 2.0) del score v0; `exposure_ev_max=0` + `illuminant_search=0` = v0 bit a bit | 1.23 ms (cota 5) | 2.09 ms | 1.49 ms | 3.84 ms | 8.58 ms | 4.39 ms | 348/348 · 348/348; paletas exactas degradadas (−1 EV, +1 EV, A, F2, D75, A−0.5 EV): 348/348 en los seis casos (v0: 102, 150, 27, 234, 348, 26) | 0 | `test_match` +2 tests (10); cli_match_contract 409 comprobaciones; `make parity` 20/20 bit-exactas; goldens regenerados (top-1 39/50 → 47/50, top-3 42/50 → 49/50) |
| 2026-09-15 | ADR-009 actualizado (caso real rosa + negro) | `ce_match_opts_default`: `illuminant_search` 1 → 0 (5 hipótesis de exposición por defecto; la de iluminante sigue como opción) | 0.407 ms | 0.688 ms | 0.493 ms | 4.34 ms | 10.84 ms | 4.89 ms | 348/348 · 348/348; paletas degradadas con `illuminant_search` = 1 explícito: 348/348 en los seis casos (v0: 102, 150, 27, 234, 348, 26) | 0 | `test_match` +1 test (11): `test_false_adaptation_pink_black` (paleta real #222524 39,4 % / #b49aa2 22,7 % / #917a7e 16,2 % / #d5b8c0 13,4 % / #6b5a57 8,3 %: por defecto 337 (19,5557), 27 (21,5555), 69; Δh del color más cercano al mauve 4,1°; con `illuminant_search` = 1 → 67 (17,1697), Δh 86,8°); `cli_match_contract` 438 comprobaciones (nuevo `ce match-palette`); `DEBUG_LAYERS_HASH` 60b15a4bf131c4bf sin cambio; `make parity` 20/20 bit-exactas; máquina compartida con otros agentes |

## Capa 3 en el harness (`make l3` / `oracle.l3`; sintéticos de `wada_gen`, 348 × 10 variantes dev, columna oficial kL=1)

Recall@1 / recall@3 en % por grupo de degradación (`thresholds.json` L3: clean ≥ 95/99, jpeg_q10 @1 ≥ 85,
illuminant @3 ≥ 80, exposure @1 ≥ 75, distractor @3 ≥ 75, cuota máxima ≤ 5 %); kL2 y skin1 son columnas
informativas. Tiempo L3 = generación (solo si cambia `generator_hash`) + 3 × `ce batch` + determinismo + golden-check.

| Fecha | Fase | Cambio | clean | shapes | texture | shading | illuminant | jpeg_q10 | jpeg_q30 | exposure | distractor | dev agregado | cuota máx. / entropía | ambiguous | kL2 agregado | skin1 agregado | Holdout | Tiempo L3 | Notas |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-15 | F3 | Línea base match v0 (score ajuste + λ·cobertura, λ = 1, gap 1,0; paleta por defecto, sigma 0,35) sobre `wada_gen` `generator_hash` a791d9aba4ea, dict fd95ac692777 | 100 / 100 | 100 / 100 | 100 / 100 | 100 / 100 | 57,8 / 68,1 (n = 1044) | 100 / 100 (n = 164) | 100 / 100 (n = 184) | 22,1 / 48,9 | 97,4 / 99,4 | 79,3 / 85,3 (n = 3480) | 1,7 % (combo 222) / 0,990 | 7,8 % | 81,2 / 86,5 (exposure 63,5 / 87,4) | 57,9 / 71,7 | skipped (sin `COLORSAPP_HOLDOUT_SEED`) | 39,2 s (generación 27,0 s; batch 3,9 / 3,8 / 3,9 s); `make eval` 54,8 s; `make eval-fast` 14,7 s; `make l3-fast` cacheado 1,4 s | **Fallan illuminant @3 (68,1 < 80) y exposure @1 (22,1 < 75)**: trabajo de F4 (escalera §6: peso al centro → máscara → kL=2 → piel). golden-check 20/20 + 50/50 a 1e-9. Confusiones más frecuentes: 8→206 (3), 4→53, 13→91, 30→71, 31→115 (2 cada una) |
| 2026-09-15 | F3/F5 (corrección) | Barrido de opciones existentes del match v0 sobre el mismo dev set (3480 imágenes; `ce batch`): kL 1.5 → exposure 49.1/79.0 e illuminant 53.7/62.6; kL 2 → 63.5/87.4 y 50.4/59.5; kL 3 → 73.6/90.8 y 45.7/55.2; kC 1.5/2, λ 0.5/2, σ 0, kL2+λ0.5: ninguna pasa los dos umbrales | 100 / 100 | 100 / 100 | 100 / 100 | 100 / 100 | ≤ 58.8 / 68.9 | 100 / 100 | 100 / 100 | ≤ 73.6 / 90.8 | 92.2–99.7 / 97.1–100 | 78.1–81.2 / 83.8–86.7 | ≤ 2.4 % | 5.2–11.7 % | — | — | — | ~4 s por configuración | Conclusión: exposición e iluminante necesitan modelo explícito (ADR-009), no un ajuste de kL/kC/λ |
| 2026-09-15 | F3/F5 (corrección, ADR-009) | Match v1 (hipótesis de exposición ±1 EV paso 0.5 + iluminante A/D50/D75/F2, penalizaciones 2.0/2.0) por defecto; `wada_gen` `generator_hash` aa604e4ecd99 (dev idéntico), dict fd95ac692777 | 100 / 100 | 100 / 100 | 100 / 100 | 100 / 100 | **94.4 / 98.3** | 100 / 100 | 100 / 100 | **87.6 / 96.6** | 97.4 / 99.1 | **96.8 / 99.1** | 0.9 % (combo 222) / 0.999 | 1.6 % | 96.0 / 98.2 | 66.2 / 79.4 (noadapt = v0: 79.3 / 85.3) | skipped sin semilla; con una semilla de prueba (una semilla de prueba (no anotada), no guardada): ver texto | 53.6 s (generación 29.2 s; batch 6.9 / 6.4 / 6.4 / 4.0 s) | **17/17 checks L3 en verde; todos los umbrales de `thresholds.json` pasan.** Prototipo numpy con rejillas que no contienen ±1 EV (±1.2/0.6, ±0.75, ±1.5/0.75) ni F2/D75 (solo A y D50): exposure 85.3–88.2 / 94.0–96.0, illuminant 93.4–95.1 / 98.0–98.9, todos los umbrales OK → no es un ajuste a los parámetros exactos del generador. Penalizaciones 1–5 probadas: 2.0/2.0 maximiza el agregado sin subir `ambiguous` |
| 2026-09-15 | F4 (orquestador) | `COLORSAPP_HOLDOUT_SEED=<semilla del orquestador, fuera del repo> make eval` → exit 0: holdout kL=1 recall@1/@3 dentro de 3 puntos del dev (illuminant 94,0/97,7 n=218; exposure 91,3/95,7 n=69; distractor 96,1/100 n=51; resto 100/100), ambiguous 1,6 %, cuota máxima 1,0 %, 53,8 s. Pendiente: el usuario repite con su propia semilla. |
| 2026-09-15 | F6 (app iOS) | `EngineParityTests` en el simulador iPhone 18 Pro (iOS 27.0, Xcode 27.0, Apple M4 Pro): 5 PPM de `harness/golden/fixtures` (f01, f13, f24, f37, f50) por `EngineBridge.analyze` (CGImage → CGContext sRGB `noneSkipLast` → `ce_analyze`) == `match_50.json` (top-3, scores, Lab y pesos a 1e-9, rgb, `ambiguous`, `hash`; los píxeles llegan al motor byte a byte, también desde el PNG con perfil sRGB embebido). **PNG Display P3** (`sips --matchTo 'Display P3.icc'` desde el PNG sRGB, decodificado por ImageIO y convertido a sRGB por CoreGraphics/ColorSync al dibujar): Δ por canal frente al PPM sRGB (LittleCMS/Pillow no interviene: el PPM es la fuente) **máx 1/255** en 4/5 fixtures y 0 en f13 (media 0,00–0,51 niveles); **top-1 idéntico 5/5**; top-3 idéntico 4/5 (f24, fixture `ambiguous`, intercambia los hits 2 y 3: 124/148 a 17,56 vs 17,40); ΔE00 entre swatches homólogos máx 0,38 en 4/5 y **1,19 en un swatch (peso 0,11) de f37** (distractor, 5 swatches: el 1/255 mueve píxeles de frontera entre clusters de Lloyd). El criterio de PLAN §8 F6 «ΔE00 de cada swatch ≤ 0,5» se cumple en 4/5 fixtures; el test exige top-1, Δcanal ≤ 1/255 y ΔE00 ≤ 1,5 y adjunta el detalle al xcresult | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | tests 2,0 s (28 XCTest) | Sin cambios en el motor: solo el wrapper Swift gana `mask:` opcional (`extractPalette`/`analyze`) |
| 2026-09-15 | Post-F7 (máscaras + capas de depuración) | Motor: `ce_mask.c` (regiones de ropa por pose, recorte de cabeza, piel adaptativa con salvaguarda) y `ce_debug.c` (reduced/weight/label/cluster map, destino de clusters, `ce_match_explain_combo`); contabilidad paralela en `ce_palette.c` sin tocar coma flotante; `ce_ctx_size()` 2 044 176 → 2 047 936 B | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | l3-fast 17/17 (dev agregado 97,7 / 99,4, n = 350) | Sin cambio de resultados: golden-check 20/20 + 50/50, 280 salidas `ce match/palette` byte a byte iguales a HEAD, `layers_parity.js` 237 salidas nativo = WASM. Apple M4 Pro -O2 (máquina cargada por otros agentes): `PERF_1024_RGBA_MS` 3,85 (HEAD 3,96), `MATCH_MS` 2,12 (HEAD 2,12), `ANALYZE_1024_MS` 6,1 (HEAD 6,7); `MASK_REGIONS_MS` 28 (1024×2048), `MASK_SKIN_FIT_MS` 1,8, `MASK_SKIN_MS` 42 (1024×1024 llena, dos pasadas; 158 con `ce_srgb8_to_lab` por píxel) |
| 2026-09-15 | F9 (L4 por variantes + informe de capas) | Sin cambios en el motor: `oracle/l4/variants.py`, `l4.people_smoke`, `tools/layers_report.py`, `mk/segmentation.mk` (`ce` propio en `build-seg/`) | — | — | — | — | — | — | — | — | — | 97.7 / 99.4 (l3-fast dentro de eval-fast) | — | 0.3 % | 96.0 / 98.3 | 77.4 / 83.7 | skipped sin semilla | eval-fast 19.0 s; l4-people-smoke 4.7 s (8 fotos, visionmask real); layers-report 7.0 s (8 fotos × 4 variantes, HTML 5,4 MB, 325 PNG) | `make l4-people-smoke` (ΔE00 dominante→ropa anotada, mediana / p90): none 35,4 / 84,1; allPeople 2,2 / 27,1; largest 2,2 / 4,0; largest-clothing 2,5 / 3,2; **largest-clothing-skin 2,5 / 3,2**; peso de la paleta en la ropa (mediana) 15 % → 52 %. `COLORSAPP_GOLDEN_DIR=<50 sintéticos partidos> make l4-variants`: oficial vs none recall@3 90,0 vs 68,0 (mitad distractora) y 96,0 vs 96,0 (cuarto distractor, exit 0). Informativo: no hay set dorado real |
| 2026-09-15 | ADR-009 actualizado | Defaults sin hipótesis de iluminante + `wada_gen` con tinte residual tras el balance de blancos (`s` ~ U[0,25, 0,35]; `generator_hash` 37151dcc01ae) | 100 / 100 | 100 / 100 | 100 / 100 | 100 / 100 | **98,0 / 100** | 100 / 100 | 100 / 100 | **88,8 / 97,1** | 97,4 / 99,1 | **98,0 / 99,6** | 0,4 % (combo 109) / 1,000 | 1,0 % | 97,2 / 99,3 | 68,2 / 82,6 (noadapt 91,5 / 94,8; illum1 98,4 / 99,6) | skipped sin semilla | `make l3` 104 s (generación 61 s por el cambio de `generator_hash`) | Antes (HEAD, hipótesis por defecto + iluminante completo): illuminant 94,4 / 98,3, exposure 87,6 / 96,6, agregado 96,8 / 99,1. Defaults nuevos sobre el generador viejo: illuminant 54,5 / 65,1 (fallaría @3 ≥ 80), agregado 85,0 / 89,2. Giro de tono (2040 paletas fuera del diccionario): defaults 0,70 %, +iluminante 15,6 % |
| 2026-09-16 | Post-F9 (separación de instancias) | Motor: `ce_mask_split_instance` en `ce_mask.c` (argmin de distancia al eje / semiancho, sin malloc ni estáticos) + `ce split` en el CLI; SubjectKit separa con semillas de caras y poses (`PersonSplitter`) | — | — | — | — | — | 60 s ASan/UBSan: 11 392 it de la entrada 6 (separación), 0 fallos | — | — | — | — | — | — | — | — | — | — | Sin cambio en paleta ni match (función nueva): `MASK_HASH` 36160cbd7630fb2b, `LIGHT_MERGE`, `DEBUG_LAYERS`, `RESULT_HASH_COMBO42` y `GARMENT_HASH` sin tocar; golden-check no afectado. **`SPLIT_HASH` = 79a280420498ca5b** igual en nativo, ASan y WASM; `make parity` 541 ficheros byte a byte (539 antes: +`ce split` con semillas no diádicas). Apple M4 Pro -O2, máquina compartida: `MASK_SPLIT_MS` 15,1 (1024×1024 llena, 8 semillas); en `visionmask` (release) las semillas + el paso `split` son 0,5 ms de 585 ms de detección en 01 (sin separar) y 9,2 ms de 513 ms en 07 (dos instancias separadas en 6 personas); la petición de rectángulos de persona que pide la evidencia corporal de las semillas de cara son 36 ms más, solo en las fotos con una cara sin pose (05 y la selfie sintética) |

## Experimento: fusión de sombras (`ce_palette_opts.merge_light_de`, desactivado por defecto)

Fusión iterativa, tras la de `merge_de`, de los centros con ΔE00(kL = 3, kC = kH = 1) <
`merge_light_de` (CONTEXT §11.4: «las sombras del mismo pantalón cuentan como colores distintos»).
Con `merge_light_de` = 0 la salida es bit a bit la de antes (goldens, paridad y `test_merge_light_shades`).
Máquina compartida (Apple M4 Pro), 2026-09-15.

| Medida | 0 (defecto) | 3 | 4 | 6 | 8 |
|---|---|---|---|---|---|
| L2 (200 composiciones + 30 invariancias, `oracle.l2` con el CLI envuelto) | 11/11 | — | 11/11, 0 paletas distintas | 11/11, 0 paletas distintas | — |
| L3 dev 3480, agregado r@1 / r@3 (defaults de match) | 98,0 / 99,6 | 98,0 / 99,6 | 98,0 / 99,6 | 98,0 / 99,6 | 97,9 / 99,5 |
| L3 illuminant / exposure / distractor | 98,0/100 · 88,8/97,1 · 97,4/99,1 | igual | 98,0/100 · 88,8/96,8 · 97,4/99,1 | 97,9/100 · 88,8/96,8 · 97,4/99,1 | 97,9/100 · 88,5/96,6 · 96,8/98,9 |
| Combinaciones de Wada con algún par a ΔE00(kL=3) < umbral | 0 | 0 | 0 | 3 (283, 326, 337) | 13 |
| Pantalón rosa, prenda sombreada sintética (400×600, pliegues L* 38-80, ruido σ 2), sigma 0 | 5 swatches, top-1 337 | 4, 337 | 3, 337 | **2** (#a68e96 61 % + #222424 39 %), top-1 **027** | 2, 027 |
| Ídem con sigma por defecto 0,35 | 5, 337 | 4, 027 | 3, 337 | **2**, 027 | 2, 027 |
| Pantalón rosa, franjas con la paleta de la app (5 colores), sigma 0 | 5, 337 | 4, 337 | 4, 337 | 3 (#b1979e 52 % + negro + #6b5a58 8 %), 337 | 3, 337 |
| `harness/people` (máscara oficial `largest-clothing-skin`, 8 fotos): swatches | 1,5,5,1,5,5,5,5 | — | 1,5,5,1,5,5,5,**3** | 1,5,**4**,1,5,**4**,5,**2** | — |

Lectura: no hay regresión medible en L2 (sus composiciones separan los colores ≥ 15 ΔE00, así que
apenas lo ejercitan) ni en L3 hasta 6 (−0,3 puntos en exposure @3); en 8 empieza a fusionar pares de
combinaciones tonales de Wada. En el caso del pantalón la prenda sombreada pasa de 5 a 3 swatches
con 4-5 y a 2 con 6, y el top-1 pasa a Nº 027 (la pareja rosa + gris oscuro más cercana a lo que
describió el usuario). Al liberar huecos entran clusters pequeños que antes se recortaban (02: un
gris del 8 %). Candidato a activar: 4-6, pendiente de L4 con fotos reales; **no se activa**.

## Paleta por prenda (`ce_garment.c`, ADR-011)

Un color por prenda lisa con su tono iluminado (CONTEXT §13). Máquina compartida (Apple M4 Pro),
2026-09-16. `GARMENTS_1024_MS`: `test_garment`, 1024×1024 RGBA con 2 regiones, mejor de 5.

| Fecha | Cambio | GARMENTS_1024_MS nativo | ASan/UBSan | WASM (node) | `ce_palette_extract` en la misma imagen (nativo / ASan / WASM) | ce_ctx_size | Fuzz | Notas |
|---|---|---|---|---|---|---|---|---|
| 2026-09-16 | `ce_palette_extract_garments` (mezclas, enlace simple con límite de luminancia, tono iluminado del núcleo) + `ce_mask_garment_regions`; centro de Lloyd por bin en `int8_t` aparte (bin 40 → 32 B) | 1.52 ms | 5.15 ms | 1.82 ms | 1.12 / 2.88 / 1.07 ms | 2 047 936 → 1 994 576 B (1.902 MiB) | 60 s ASan/UBSan (`make fuzz FUZZ_SECONDS=60 FUZZ_SEED=20260916`): 11 520 it por entrada (garments incluida), 0 fallos | hashes previos sin cambio (LIGHT_MERGE 701eaabfb2c0beba, MASK 36160cbd7630fb2b, DEBUG_LAYERS 60b15a4bf131c4bf, RESULT_HASH_COMBO42 84121a0c86d6ea7e); `GARMENT_HASH` 3f5e33cb77978a44 en nativo, ASan y WASM; `PERF_1024_RGBA_MS` 2.76 ms nativo |

### Calibración de `ce_garment_opts` (`make garments-sweep`, `harness/out/garments_sweep.{json,md}`)

Conjuntos (medición original de 2026-09-16, con 100 composiciones y percentiles 0,60-0,90; la
corrección posterior está en la sección siguiente): 100 composiciones sombreadas de `oracle.garments` (semilla 20260916: liso 25; rayas 20,
la mitad estampado de motivos de 6-12 px, todas desenfocadas en luz lineal; vestido 15; tono cercano
25 con ΔE00 real 8-18; sombras duras 15), las 200 composiciones planas de L2 por el camino de prendas
sin mapa (`--center-sigma 0`; "principales" = los 2 colores más grandes con área >= 25 %; fusión = dos
principales con el mismo swatch más cercano), las imágenes de `test_garment` (pantalón, rayas,
vestido y vestido con estampado desenfocado) y 7 fotos de `harness/people` con pose (máscara
`largest-clothing-skin`, regiones de `ce garment-regions` con la silueta corporal; ΔE00 mediano de la
ropa anotada al swatch de su región). Cruce de regiones con la regla estricta (ΔE00 kL = 1 entre
tonos iluminados) y las constantes finales del motor. Extracto (tabla completa de 110 + 9 filas en el
`.md`):

| shade_kL | shade_merge_de | colores exactos | liso | rayas | vestido | tono cercano | sombras duras | fusiones erróneas | rayas fundidas | ΔE00 tono iluminado p50 / p90 | L2 principales | L2 fusiones | Unity a/b/c/estampado | people swatches / ΔE00 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 6,5 | 89/100 | 24/25 | 15/20 | 15/15 | 25/25 | 10/15 | 0 | 5 | 0,45 / 0,98 | 400/400 | 0 | ✓✓✓✗ | 2,29 / 3,41 |
| 2 | 6,5 | 97/100 | 25/25 | 20/20 | 15/15 | 25/25 | 12/15 | 0 | 0 | 0,47 / 1,56 | 400/400 | 0 | ✓✓✓✓ | 2,29 / 4,99 |
| 2 | 8 | 99/100 | 25/25 | 20/20 | 15/15 | 24/25 | 15/15 | 1 | 0 | 0,49 / 2,61 | 400/400 | 0 | ✓✓✓✓ | 2,00 / 5,56 |
| 2,5 | 6,5 | 99/100 | 25/25 | 20/20 | 15/15 | 25/25 | 14/15 | 0 | 0 | 0,48 / 2,48 | 400/400 | 0 | ✓✓✓✓ | 2,29 / 4,99 |
| 3 | 4 | 92/100 | 24/25 | 16/20 | 15/15 | 25/25 | 12/15 | 0 | 4 | 0,46 / 1,01 | 400/400 | 0 | ✓✓✓✓ | 2,43 / 3,41 |
| 3 | 5 | 98/100 | 24/25 | 20/20 | 15/15 | 25/25 | 14/15 | 0 | 0 | 0,47 / 1,54 | 400/400 | 0 | ✓✓✓✓ | 2,29 / 4,99 |
| 3 | 6 | 99/100 | 25/25 | 20/20 | 15/15 | 25/25 | 14/15 | 0 | 0 | 0,47 / 1,75 | 400/400 | 0 | ✓✓✓✓ | 2,29 / 4,99 |
| **3** | **6,5** | **99/100** | **25/25** | **20/20** | **15/15** | **25/25** | **14/15** | **0** | **0** | **0,48 / 2,61** | **400/400** | **0** | **✓✓✓✓** | **2,43 / 4,99** |
| 3 | 7 | 99/100 | 25/25 | 20/20 | 15/15 | 25/25 | 14/15 | 0 | 0 | 0,48 / 2,61 | 398/400 | 1 | ✓✓✓✓ | 2,43 / 4,99 |
| 3 | 8 | 99/100 | 25/25 | 20/20 | 15/15 | 24/25 | 15/15 | 1 | 0 | 0,49 / 2,61 | 396/400 | 2 | ✓✓✓✓ | 2,14 / 5,56 |
| 3 | 10 | 95/100 | 25/25 | 20/20 | 15/15 | 20/25 | 15/15 | 5 | 0 | 0,49 / 3,02 | 387/400 | 5 | ✓✓✓✓ | 2,14 / 5,56 |
| 4 | 5 | 99/100 | 25/25 | 20/20 | 15/15 | 25/25 | 14/15 | 0 | 0 | 0,47 / 1,75 | 400/400 | 0 | ✓✓✓✓ | 2,29 / 4,99 |
| 4 | 6,5 | 99/100 | 25/25 | 20/20 | 15/15 | 25/25 | 14/15 | 0 | 0 | 0,48 / 2,61 | 396/400 | 2 | ✓✓✓✓ | 2,43 / 4,99 |
| 6 | 6,5 | 99/100 | 25/25 | 20/20 | 15/15 | 25/25 | 14/15 | 0 | 0 | 0,48 / 2,61 | 394/400 | 2 | ✓✓✓✓ | 2,43 / 4,99 |

Percentiles del tono iluminado con kL 3 / 6,5 (colores exactos 99/100 y L2 400/400 en todos salvo 0-1):

| percentiles | ΔE00 al color base p50 / p90 | people ΔE00 mediana |
|---|---|---|
| 0,4-0,9 | 0,77 / 3,02 | 4,07 |
| 0,5-0,8 | 0,64 / 2,96 | 4,18 |
| **0,6-0,9** | **0,48 / 2,61** | **4,99** |
| 0,6-0,95 | 0,46 / 2,50 | 5,11 |
| 0,7-0,95 | 0,37 / 1,26 | 5,25 |
| 0,8-0,98 | 0,27 / 0,74 | 6,09 |
| 0-1 (media) | 1,55 / 5,25 | 2,92 |

### Constantes del algoritmo (compilaciones del scratchpad con macros temporales, retiradas del motor)

Mismos conjuntos (rayas desenfocadas), kL 3 / 6,5. Límite de luminancia `CE_GARMENT_SHADE_MIN_RATIO`,
núcleo del tono iluminado `CE_GARMENT_LIT_CORE_FRACTION` y umbral de mezcla `CE_GARMENT_MIXTURE_DE`:

| límite | núcleo | mezcla | colores exactos | rayas | p50 / p90 | L2 | Unity a/b/c/estampado | people swatches / ΔE00 | harness/people/02 (vestido azul marino con estampado) |
|---|---|---|---|---|---|---|---|---|---|
| 0 (sin límite, primer diseño) | 0 | 0 | 89/100 | 10/20 | — | 400/400 | — | 1,86 / 4,93 | **1 gris #838f9a en región 3** |
| 0,16 | 0 | 0 | 98/100 | 19/20 | 0,66 / 3,63 | 400/400 | ✓✓✓✗ | 2,14 / 4,47 | #0b0d17 + #b0c2cd (región 3) |
| 0,2 | 0 | 0 | 98/100 | 19/20 | 0,66 / 3,63 | 400/400 | ✓✓✓✗ | 2,14 / 4,47 | igual |
| 0,2 | 0,35 | 0 | 98/100 | 19/20 | 0,49 / 3,38 | 400/400 | ✓✓✓✗ | 2,14 / 4,47 | igual |
| 0,2 | 0 | 3 | 99/100 | 20/20 | 0,64 / 2,52 | 400/400 | ✓✓✓✓ | 2,43 / 5,00 | igual |
| 0,2 | 0,35 | 2 | 99/100 | 20/20 | 0,48 / 2,12 | 400/400 | ✓✓✓✓ | 2,29 / 5,51 | igual |
| **0,2** | **0,35** | **3** | **99/100** | **20/20** | **0,48 / 2,61** | **400/400** | **✓✓✓✓** | **2,43 / 4,99** | **igual** |
| 0,2 | 0,35 | 5 | 97/100 | 19/20 | 0,48 / 2,51 | 400/400 | ✓✓✓✓ | 2,29 / 4,99 | #0b0d17 + #acbec8 |
| 0,25 | 0,35 | 3 | 99/100 | 20/20 | 0,48 / 2,61 | 400/400 | ✓✓✓✓ | 2,43 / 4,99 | igual |

(La fila «sin límite» es el barrido con las rayas desenfocadas de 3-6 px antes de fijar tamaños
realistas; las demás, con motivos de 6-12 px.) Sin mezclas, el vestido con estampado desenfocado de
`test_garment` salía con el azul marino a ΔE00 19 (#52555d: los píxeles de borde formaban un grupo
propio del 31 % más pesado que el azul). Con mezcla 5 se rompe un liso (una sombra tomada por mezcla).

Cruce de regiones con la tolerancia de la agrupación (variante descartada, ΔE00 kL = `shade_kL` entre
tonos iluminados, compilada aparte en el scratchpad con `-DCE_GARMENT_EXPERIMENT_FUSION_SHADE` sobre
el primer conjunto de 100 composiciones, antes del límite de luminancia): kL 4 / 7 → 73/100 con
**24 de 25 pares de tono cercano fusionados**; kL 3 / 6 → 76/100 (23 fusionados); kL 2 / 5 → 93/100
(3). Con la regla estricta, 0 fusiones en toda la rejilla hasta umbral 7.

### Corrección 2026-09-16: sombra proyectada contigua y percentiles del tono iluminado

La verificación midió el hueco mayor: una **sombra proyectada contigua** (sol contra sombra abierta)
sobre una prenda lisa sacaba un **segundo color falso**. Con el generador independiente del
verificador (cilindros con luz lateral a 40°, degradado vertical, pliegues, ruido; pantalón
#ddc0c8 con sombra sobre el 50 % de la pierna) fallaban 14 de 24 configuraciones de (luz ×
profundidad) y 2 de 5 semillas de un beige liso con sombra propia dura. Regla nueva
`ce_garment_same_material` (modelo físico de sombra: `c ≈ s·a` en XYZ lineal, s de mínimos cuadrados
en [`CE_GARMENT_SHADE_S_MIN` 0,02, 50], ΔE00 al modelo < `CE_GARMENT_SHADE_LIT_DE` 3), aplicada al
agrupar clusters (par `CE_GARMENT_PAIR_SHADE`, salta el límite de luminancia) y al seleccionar
colores. Mismas escenas del verificador, antes → después:

| escena (24 config. de luz × profundidad salvo donde se indique) | antes | después |
|---|---|---|
| sombra proyectada sobre media pierna, pantalón liso #ddc0c8 | 14/24 con 2º color falso | **0/24** |
| sombra propia (sin proyectada), 3 luces × 5 semillas | 1/15 | **0/15** |
| beige liso #d8c3a5 con luz dura, 5 semillas | 2/5 | **0/5** |
| control rayas marino/blanco (9 config.) | 2 colores 9/9 | 2 colores 9/9 |
| control tie-dye magenta→amarillo→cian (9 config.) | 2 colores 6/9 | 2 colores 6/9 |
| control pares de tono cercano (vaquero+camiseta, beige+rosa, negro+antracita) | 0 fusiones | 0 fusiones |
| control marino + marino claro (ΔE00 real 5,69) | fusiona con luz media y dura (4/6) | **0/6** (efecto de los percentiles) |
| rayas blanco + gris medio (ΔE00 real 27,9) | 2 colores | **1 color** (contrapartida deliberada) |

Separación del estadístico elegido (ΔE00 del tono iluminado del segundo grupo al modelo escalado del
primero): sombras **0,42-1,34**; prendas de verdad bicolores **10,5-28,1** (rayas marino/blanco 13,8;
rojo + rosa palo 17,7; azul + celeste 10,5; degradado de color 12,4). Con el umbral en 3 hay casi un
orden de magnitud de margen. La regla que propuso el verificador (ΔE00 con kL = `CE_GARMENT_HUE_KL`,
solo tono y croma) se midió y se descartó: da 3,36-8,01 en las sombras y 4,23-4,31 en unas rayas
azul + celeste de verdad, así que ningún umbral las separa.

Estadísticos espaciales probados y descartados (los tres confunden los pliegues de un cilindro con
unas rayas; el valor de la izquierda debería ser pequeño y el de la derecha grande):

| estadístico | sombras (debe ser bajo) | rayas de verdad (debe ser alto) | veredicto |
|---|---|---|---|
| alternancias A\|B por barrido / √mín. área | 0,92 (sombra dura) … 9,57 (beige, luz dura) | 4,64-10,16 | se solapan |
| salto de color mediano en la frontera / separación | 0,09 … 1,55 | 0,21-0,99 | se solapan |
| valle del histograma de L* entre las dos modas | 0,000 … 1,500 | 0,000-1,547 | se solapan |

Bloque «prendas» de L2 con la familia nueva `sombra_proyectada` (15 de 115 composiciones: sombra
contigua de 2-4,5 pasos sobre el 40-60 % de una pieza, borde recto con penumbra de 0-3 px, ambiente
0,6-0,8):

| versión | colores exactos | sombra_proyectada | prendas lisas partidas | ΔE00 tono iluminado p50 / p90 |
|---|---|---|---|---|
| sin la regla (`CE_GARMENT_SHADE_LIT_DE` 0) | 108/115 | 9/15 | 6 (2,15 a 4,38 pasos) | 0,49 / 2,61 |
| **con la regla** | **114/115** | **15/15** | **0** | **0,31 / 1,51** |

Barrido de la tolerancia `CE_GARMENT_SHADE_LIT_DE` (bloque de 115 + tests Unity; el hash de paridad
cambia en todas las filas porque está fijado al valor elegido, no se cuenta como fallo):

| tolerancia | colores exactos | rayas | rayas fundidas | sombras duras | sombra proyectada | p90 | tests Unity de comportamiento |
|---|---|---|---|---|---|---|---|
| **3 (elegida)** | **114/115** | **20/20** | **0** | **14/15** | **15/15** | **1,51** | **todos en verde** |
| 4 | 114/115 | 20/20 | 0 | 14/15 | 15/15 | 1,51 | todos en verde |
| 5 | 113/115 | 19/20 | 1 | 14/15 | 15/15 | 1,40 | todos en verde |
| 6,5 | 112/115 | 18/20 | 2 | 14/15 | 15/15 | 1,41 | todos en verde |
| 7 | 113/115 | 18/20 | 2 | 15/15 | 15/15 | 1,49 | todos en verde |
| 10 | 111/115 | 16/20 | 4 | 15/15 | 15/15 | 1,56 | fallan (b) rayas y (c) vestido con estampado |

Se elige **3** (el valor de `CE_GARMENT_MIXTURE_DE`, el más conservador de los dos sin regresión).
Lo que NO alcanza: el vaquero real de `harness/people/06` al sol y a la sombra necesita **5,75**
(la luz de relleno del cielo azulea la sombra: Δh 12,8°, ΔC*ab −3,7, así que la sombra ya no es una
escala pura), y a partir de 5 se funde una camisa de rayas del bloque. Con el margen medido
(sombras ≤ 1,34 / bicolores ≥ 10,5 en los sintéticos, pero 5,75 / 10,85 con la foto real) **06 sigue
siendo un límite conocido del motor**, anotado en `knownEngineLimits` de `GarmentRegionsTests` y en
ADR-011: una sombra con giro de tono no la arregla el modelo de sombra pura.

Percentiles del tono iluminado **0,60-0,90 → 0,75-0,95** (barrido completo abajo, con la regla nueva
y las 115 composiciones). Al agrupar la sombra con la luz la banda de percentiles de la unión baja y
el tono se oscurecía (pantalón rosa con luz dura del generador del verificador: ΔE00 5,5 → 8,0).
Recalibrados con la métrica **válida** (composiciones sintéticas cuyo color base sin sombra se
conoce), no con `harness/people` (parches medidos a mano en tonos medios, que empujan los
percentiles hacia abajo):

| percentiles | ΔE00 al color base p50 / p90 | L2 principales | L2 fusiones | Unity a/b/c/estampado | people ΔE00 mediana |
|---|---|---|---|---|---|
| 0,6-0,9 (anterior) | 0,49 / 3,27 | 394/400 | 1 | ✓✓✓✓ | 4,56 |
| 0,7-0,95 | 0,37 / 1,95 | 394/400 | 2 | ✓✓✓✓ | 5,25 |
| **0,75-0,95 (elegido)** | **0,31 / 1,51** | **394/400** | **2** | **✓✓✓✓** | **5,82** |
| 0,8-0,98 | 0,28 / 0,98 | 394/400 | 2 | ✓✓✓✓ | 6,09 |
| 0,9-1 | 0,24 / 0,84 | 394/400 | 2 | ✓✓✓✓ | 6,73 |

Se deja `lit_high` en 0,95 y no en 0,98 para conservar margen contra los brillos especulares (las
composiciones llevan hasta un 3 % del ancho con especular; 0,98 deja solo 2 puntos de margen).
`test_garment` (a): el pantalón pasa de ΔE00 1,4 a **0,41** de #ddc0c8.
Reserva sin regiones con peso: con máscara válida devolvía la media de TODA la reducida (el fondo);
ahora es la media ponderada de los píxeles de la máscara (`EMPTY_MAP_WITH_MASK`, ΔE00 0,000).
`GARMENTS_1024_MS` 1,50 ms (antes 1,54), contexto 1 994 576 B sin cambio, `GARMENT_HASH`
`c9168139c0efbc51` igual en nativo, ASan y WASM.

Lectura y elección: **kL 3, umbral 6,5, percentiles 0,75-0,95, límite 0,2, núcleo 0,35, mezcla 3,
sombra pura s >= 0,02 a ΔE00 < 3**.
Con kL 3 la meseta de 114/115 va de 5,5 a 7 en las composiciones, 6,5 es el mayor umbral que no funde
ningún par de colores distintos de L2 (el primero aparece con 7) y encadena los tonos reales del
pantalón del tranvía (ΔE00 kL 3 entre vecinos 2,94, 4,14 y 6,16; luminancia mínima/máxima 0,23 >
0,2). El fallo que queda (sombras duras, 1/15) es un azul saturado con una sombra que gira 15° de tono
y ocupa ~50 % de la pierna: sale como segundo color. Los percentiles altos acercan el color al base
sin sombra (lo que dice percibir el usuario: #ddc0c8 frente al #d5b8c0 de la paleta clásica); se
quedan en 0,90 para dejar fuera los especulares (0,8-0,98 es el mejor en sintéticos pero dispara
el error en people); las anotaciones de `harness/people` son parches medidos a mano en tonos medios
(por eso la media gana ahí) y no el tono iluminado: se decide con la capa 4.

Camino de prendas **sin mapa** en L3 (columna informativa `garments`): dev 3480 imágenes recall@1
57,3 %, @3 74,4 % (distractor 25,0 / 31,3) frente a 98,0 / 99,6 de la columna oficial kL1, que no
cambia; eval-fast 350: 55,4 / 69,7 frente a 98,9 / 100. Con una sola región y 2 colores por región
las combinaciones de 3-4 colores pierden cobertura: sin pose la app sigue con el camino clásico
(ADR-011).

## 2026-09-16 (2) — Paleta por prenda, segunda vuelta: enlace completo, sombra cromática y degradados

Corrección de los dos MAYORES y los menores de la verificación (ADR-011, "Corrección 2026-09-16
(segunda vuelta)"). Motor: enlace COMPLETO en la agrupación, veto de mezcla, ancla en la selección,
sombra cromática de exterior (dos iluminantes) y regla del degradado; `CE_GARMENT_SHADE_S_MIN`
0,02 → 0,04. `GARMENT_HASH` `c9168139c0efbc51` → **`15db5b325e98c7ac`**, idéntico en nativo, ASan y
WASM. `GARMENTS_1024_MS` **1,50 ms** y `ce_ctx_size()` **1 994 576 B**, sin cambio.

### 1. Foto real: las dos fotos que fallaban (`ce garments` con la máscara y las regiones de visionmask)

| foto | antes | después |
|---|---|---|
| 02 vestido marino con estampado blanco | `up #0f0f19` 73 % + `low #0f1221` 15 % + `low #b8c6d0` 12 % (el estampado desaparece de arriba y el marino sale en dos tarjetas) | **`whole #0e0f1b` 66 % + `whole #b7cad4` 34 %** (prenda entera, marino + estampado) |
| 06 vaquero liso al sol y a la sombra azul | `up #e2e9f0` 49 % + `up #586a90` 19 % + `low #729ac6` 19 % + `low #223d62` 12 % (**dos colores** en el pantalón liso) | `up #e2e9f0` + `up #586a90` (la chaqueta ES «azul claro con estampado blanco») + **`low #6b94c1` (UN color)** |
| gate «pantalón liso ≤ 1 color abajo» (`make subject-test`) | 01 OK, 03 OK, 04 OK, **06 FALLA** (límite conocido) | **01, 03, 04 y 06 OK** |
| `make visionmask-people`, medias de las 7 fotos con pose | swatches 3,86 → 2,43 por prenda | swatches 3,86 → **2,14** por prenda |

### 2. Tests Unity nuevos (nativo, ASan y WASM dan los mismos bits)

| caso | antes (ablación: enlace simple, sin sombra cromática, S_MIN 0,02) | después |
|---|---|---|
| `SKY_SHADOW` pantalón liso #ddc0c8, media pierna en sombra abierta (2,5 pasos y azuleo) | **2 colores**, el segundo #525576 (ΔE00 41,3 del real) | **1 color** #d9bdc5, ΔE00 **0,81** de #ddc0c8 |
| `SKY_SHADOW_STRIPES` (control) rayas marino/blanco con la misma sombra | 2 colores | 2 colores |
| `PRINT_SHADOW` estampado marino + motivo blanco con esa sombra, una región | **1 swatch**: el motivo blanco DESAPARECE (ΔE00 79 al blanco) | **2 swatches**, ΔE00 2,31 al marino y 3,55 al blanco, 0 intermedios |
| `PRINT_SHADOW` con mapa de 2 regiones | — | 2 colores en cada región (ΔE00 entre ellos 80,1 arriba y 29,6 abajo) |
| `TIE_DYE` magenta → amarillo → cian | 2 colores | 2 colores, #e8cd42 y #71c9c5, ΔE00 35,9 |
| `TIE_DYE_STRICT` el mismo con `secondary_min_share` 0,35 | **1 color** (la cuota del extremo no llega) | **2 colores** (regla del degradado) |
| `TIE_DYE_CONTROL` pantalón liso con sombra y `secondary_min_share` 0,35 | 1 color | 1 color (la regla del degradado no se dispara con una sombra) |
| `PINK_PANTS` / `CAST_SHADOW` / `PRINT_DRESS` / rayas / vestido (existentes) | verde | verde, mismos números (pantalón ΔE00 0,412; sombra proyectada 1 color a −1/−2/−3/−4 pasos) |

### 3. Bloque «prendas» de L2: 115 → 170 composiciones (`make garments-block`)

Las 115 anteriores conservan índice, semilla y bytes. «Antes» = ablación del motor (el mismo binario
con enlace simple, sin sombra cromática, sin veto de mezcla, sin ancla, S_MIN 0,02), verificada
byte a byte contra la salida del motor anterior en las 8 fotos de `harness/people`.

| métrica | antes | después |
|---|---|---|
| colores por prenda exactos (familias gateadas) | 144/150 (0,960) | **147/150 (0,980)** |
| ΔE00 al tono iluminado verdadero p50 / p90 (6 familias de calibración) | 0,31 / 1,51 | 0,31 / 1,51 |
| fusiones erróneas a región 3 · rayas fundidas · vestidos sin fusionar | 0 · 0 · 0 | 0 · 0 · 0 |
| `sombra_proyectada` partidas (gate ≤ 0) | 0/15 | 0/15 |
| **`sombra_cielo`** partidas (gate ≤ 0, 2-3,3 pasos) | **2/15** | **0/15** |
| **`estampado_sombra`** con el motivo perdido (gate ≤ 1) | **2/10** | **1/10** |
| **`degradado_color`** colapsados (gate ≤ 0) | 0/10 | 0/10 |
| `bicolor_tonal` conservadas (informativa, límite conocido) | 0/10 | 0/10 |
| `banda_fusion` fusiones (informativa) | 5/10 | 5/10 |
| ΔE00 de las familias nuevas p90 (informativo) | 32,3 | **16,6** |

**Banda de fusión a región 3** (familia `banda_fusion`, un par por ΔE00 REAL; la promesa de `ce.h`
es sobre TONOS ILUMINADOS ESTIMADOS): fusionan 4,8 · 5,2 · 5,8 · 6,2 · 6,3 y **no** fusionan
6,6 · 7,0 · 7,2 · 7,9 · 8,0, con `shade_merge_de` = 6,5. La banda de incertidumbre es de ~±0,3
alrededor del umbral en estas composiciones; la cabecera ya no promete un corte exacto.

### 4. Separación del modelo de sombra (ΔE00 al modelo, y `w` del modelo de dos iluminantes)

| par | ΔE00 real | escala pura (s, residuo) | cielo (s, w, residuo) | ¿mismo material? |
|---|---|---|---|---|
| 06 vaquero sol/sombra | 34,7 | 0,19 · **5,75** | 0,15 · 0,62 · **0,08** | sí (cielo) |
| sombra abierta FÍSICA (ganancias de los iluminantes CIE, fuera del motor) a 1,5-3 pasos sobre #ddc0c8, #466f9c, #d8c3a5 y #2b2c2c | 9,5-49,1 | 3,4-17,9 | w **0,885-1,040** · 0,16-2,03 | sí (cielo) |
| 02 marino vs estampado blanco | 67,7 | **0,012** (< S_MIN 0,04) | **0,010** (< S_MIN) | **no** |
| rayas marino/blanco | 74,1 | 0,04 · 14,5 | 0,028 (< S_MIN) · w 1,71 | **no** |
| azul + celeste | 34,2 | 0,33 · 11,4 | 0,21 · **w 1,31 > 1,15** · 0,14 | **no** |
| rojo + rosa palo · beige + rosa · oliva + caqui | 18-53 | 18-24 | w < 0 | **no** |
| tie-dye magenta/amarillo y amarillo/cian | 45-74 | 43-63 | w 3,2-13,6 | **no** |
| blanco + gris medio · beige + marrón · rosa palo + malva | 18-28 | **0,00-0,59** | — | **sí (límite conocido)** |

La sombra abierta completa cae en w 0,885-1,040 según el color (el modelo del motor es una diagonal
en conos de Bradford y la escena se genera con una diagonal en sRGB lineal: el desajuste entre los
dos espacios es lo que separa 1,04 de 1,00), así que `CE_GARMENT_SKY_W_MAX` 1,15 deja entre un 10 y
un 25 % de margen. El único discriminante del par «azul + celeste» es esa cota (w 1,31 frente a
1,15): el residuo del modelo es 0,14, es decir la ambigüedad es real y está
documentada. Sin el **veto de mezcla**, 1 de las 20 composiciones de rayas del bloque (gris claro +
pizarra azulada, s 0,11 · w 0,42 · residuo 0,11) sale con un solo color y la chaqueta estampada de
06 se funde; con él, las dos se conservan.

### 5. Regla del degradado: qué la dispara

| escena | masa de tonos de mezcla del candidato | ΔE00 solo de croma y tono | ¿se conserva el extremo? |
|---|---|---|---|
| tie-dye magenta → amarillo → cian | 0,41-0,48 | 35,9-46,4 | sí (umbrales 0,25 y 12) |
| borde de la persona de al lado (`harness/people/03`) | 0,16 | 8,7 | no (por los dos umbrales) |

### 6. Barrido de calibración (`make garments-sweep`, 110 configuraciones + 12 de percentiles)

`shade_kL` × `shade_merge_de` con las 170 composiciones, las 200 de L2 y las 4 imágenes Unity:
kL 3 × 6,5 sigue en la meseta (147/150, 0 fusiones erróneas, 0 rayas fundidas, 0 sombras azules
partidas, L2 393/400 con 2 fusiones) y **se conservan los valores por defecto**. kL 4 × 7 da
148/150 pero pierde en L2 (392/400, 3 fusiones). Percentiles: 0,75-0,95 mantiene p50 0,31 / p90 1,51
(0,8-0,98 baja a 0,28/0,98 pero deja solo 2 puntos de margen contra los especulares). Tablas
completas en `harness/out/garments_sweep.md`.

### 7. Suites

`make test` 24/24, `test-asan` 24/24, `test-wasm` 24/24 (mismo `GARMENT_HASH`), `swift-test` 33,
`parity` 20 fixtures + 539 ficheros de capas byte a byte, `golden-check` 20/20 y 50/50,
`pytest` 433 passed / 1 skipped, `eval` y `eval-fast` con L1/L2/L3 OK (L4 skipped; `check-protected`
falla por 14 rutas protegidas preexistentes de otro equipo), `fuzz` 60 s con 12 288 iteraciones de
prendas y 0 fallos, `l4-people-smoke` 7/8 fotos con regiones (5 colores de paleta → 2 de prenda).

## 2026-09-16 (3) — Paleta por prenda, tercera vuelta: la penumbra de una sombra cromática

### 1. El fallo, reproducido con el generador INDEPENDIENTE del verificador

48 escenas (pantalón liso #ddc0c8 + camiseta #2b2c2c, silueta propia, lambertiano de cilindro,
pliegues fbm, ruido de disparo, exposición global normalizada al tono al sol). Criterio: UN color
abajo y ΔE00 < 5 del tono al sol.

| familia | antes (motor de la 2ª vuelta) | después |
|---|---|---|
| sombra AZUL de exterior (4 profundidades × 2 durezas de borde × 2 temperaturas × 2 semillas) | **0/32** (siempre 2 colores) | **32/32** |
| sombra NEUTRA proyectada (4 profundidades × 2 durezas × 2 semillas) | 16/16 con un color, **10/16** con ΔE00 < 5 | **16/16** |
| penumbra suave (26 px) | 4/24 | **24/24** |
| borde duro (4 px) | 6/24 | **24/24** |

Segundo color falso típico antes del arreglo: `#6e6a88` a ΔE00 31,1 del pantalón (2,50 pasos) y
`#5b576f` a 39,0 (2,96 pasos).

### 2. Causa y arreglos (los tres del veto de mezcla, uno del tono iluminado)

| # | arreglo | efecto medido |
|---|---|---|
| 1 | un par que es el MISMO MATERIAL (los dos modelos) no puede ser extremo de una mezcla | sombra azul 0/32 → 14/32 |
| 2 | ESTRELLA DE SOMBRA como segundo control de cadena (todos los miembros son sombra del más luminoso) | 14/32 → 15/32 con UN color en 31/32 |
| 3 | los extremos de una mezcla tienen que pesar ≥ `min_weight` de la región | UN color en 32/32 (48/48 escenas) |
| 4 | núcleo del tono iluminado con filtro de NIVEL DE LUZ (`CE_GARMENT_LIT_Y_RATIO`) | ΔE00 < 5 en 48/48; sombra neutra de 3 pasos 5,24-6,30 → **0,43** |

Por qué hace falta (2): el modelo cromático se define desde la LUZ. Para el par penumbra-sombra de
una misma rampa, el ajuste da `w` 0,679 con `wmax` 0,621 (la cota `0,54·(1−s)/s` supone que la
referencia es el tono al sol), así que el enlace COMPLETO bloqueaba la unión aunque los dos tonos
ajustan al tono al sol con residuo 0,35 y 0,40.

### 3. Calibración de `CE_GARMENT_LIT_Y_RATIO` (meseta)

| valor | 48 escenas con UN color y ΔE00 < 5 | bloque «prendas» (`colors_ok`) | `lit_de00_p90` |
|---|---|---|---|
| 0,0 (sin filtro) | 25/48 | 148/150 | 1,395 |
| 0,20 | 31/48 | 148/150 | — |
| 0,30 | 40/48 | 148/150 | 1,199 |
| **0,40** | **48/48** | 148/150 | 1,003 |
| **0,50 (elegido)** | **48/48** | **148/150** | **1,003** |
| 0,60 | 48/48 | 148/150 | 0,872 |
| 0,70 | 48/48 | 148/150 | 0,705 |
| 0,80-0,90 | 48/48 | 148/150 | 0,682-0,675 |

Se elige 0,5 («un paso de luz») por estar dentro de la meseta y no en el extremo que maximiza la
métrica: con 0,8-0,9 el tono lo decide prácticamente un solo cluster y el margen contra el ruido y
los especulares desaparece.

### 4. Límite medido: cobertura de la sombra (test Unity `SKY_SHADOW_80`)

| cobertura de la sombra azul sobre la pierna | colores | ΔE00 al tono al sol |
|---|---|---|
| 40 % (penumbra 6 px) | 1 | 0,42 |
| 55 % (12 px) | 1 | 0,43 |
| 65 % (18 px) | 1 | 0,43 |
| 70 % (24 px) | 1 | 0,44 |
| **75 % (18 px)** | 1 | **41,27 (devuelve el tono EN SOMBRA)** |
| 80-90 % | 1 | 41,31 |

El filtro de peso del núcleo va antes que el de nivel de luz: por encima del ~70 % el nivel
iluminado ya no pesa ≥ 0,35 del cluster más pesado. Sigue siendo UN color.

### 5. Bloque «prendas» de L2 con la familia REFORZADA (el gate deja de ser ciego)

`sombra_cielo` pasa de penumbra 0-3 px y cobertura 40-60 % a penumbra **6-18 px**, cobertura
**55-70 %** y, en un tercio de los casos, transición **continua** de arriba abajo;
`estampado_sombra` lleva penumbra de 8-16 px.

| métrica | motor anterior (`build-fv/tools/ce`) | motor nuevo |
|---|---|---|
| `colors_ok` (150 gateadas de 170) | 143 | **148** |
| `sky_shadow_split` | **4/15** | **0/15** |
| familia `sombra_cielo` | 11/15 | **15/15** |
| familia `degradado_color` | 9/10 | **10/10** |
| familia `estampado_sombra` | 9/10 | 9/10 (umbral 1) |
| `lit_de00_p90` | 1,227 | **0,924** |
| checks del bloque | 7/8 (falla la sombra azul) | **8/8** |

Límite conocido que el modelo (2) añade, medido en la familia informativa `bicolor_tonal` (mitad
escala pura, mitad sombra de cielo): conservados **1 de 10** (antes 4 de 10). Un gris #c6c6c6 bajo
cielo abierto es exactamente #414652 (residuo del modelo 0,41): las familias de gate rechazan esos
pares con `same_material_residual < 5` para no medir el límite conocido en vez de lo que dicen medir.

### 6. Fotos reales (`make l4-people-smoke`, Vision real, variante oficial `largest-clothing-skin`)

| métrica | antes | después |
|---|---|---|
| fotos con máscara | 9/9 | 9/9 |
| ΔE00 dominante mediana / p90 | 1,8 / 3,5 | 1,8 / 3,5 |
| peso de ropa mediano | 83 % | 83 % |
| colores de prenda (mediana) | 2 | 2 |
| **ΔE00 prenda anotada → su región (mediana)** | **5,2** | **4,5** |

Único cambio estructural: `06_group_courier_street`, la parte de arriba pasa de dos colores
(#e2e9f0 a ΔE00 9,7 de la anotación y #586a90 a 30,7) a uno (#dde4ed, 8,4). La anotación de esa
chaqueta es UN color (#b9c8dd, «azul claro con estampado blanco»), así que el par blanco/azul claro
es el par ambiguo del modelo (2). Las piernas siguen con un color (#6b94c1 → #739dc9: el tono
iluminado sube, la anotación es un parche en tono medio).

### 7. Suites (todas con mis propios directorios de build)

`make test` 25/25, `test-asan` 25/25, `test-wasm` 25/25 con los seis hashes idénticos
(`GARMENT_HASH` `15db5b325e98c7ac` → **`2f33620fa4322acb`**, a propósito; LIGHT_MERGE
`701eaabfb2c0beba`, MASK `36160cbd7630fb2b`, SPLIT `79a280420498ca5b`, DEBUG_LAYERS
`60b15a4bf131c4bf`, RESULT_HASH_COMBO42 `84121a0c86d6ea7e` sin mover), `swift-test` 35,
`parity` 20/20 fixtures + 541 ficheros de capas byte a byte, `golden-check` 20/20 y 50/50,
`pytest` 433 passed / 1 skipped, `fuzz` 60 s sin fallos.
