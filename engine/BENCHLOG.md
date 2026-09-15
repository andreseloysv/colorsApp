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

## Capa 3 en el harness (`make l3` / `oracle.l3`; sintéticos de `wada_gen`, 348 × 10 variantes dev, columna oficial kL=1)

Recall@1 / recall@3 en % por grupo de degradación (`thresholds.json` L3: clean ≥ 95/99, jpeg_q10 @1 ≥ 85,
illuminant @3 ≥ 80, exposure @1 ≥ 75, distractor @3 ≥ 75, cuota máxima ≤ 5 %); kL2 y skin1 son columnas
informativas. Tiempo L3 = generación (solo si cambia `generator_hash`) + 3 × `ce batch` + determinismo + golden-check.

| Fecha | Fase | Cambio | clean | shapes | texture | shading | illuminant | jpeg_q10 | jpeg_q30 | exposure | distractor | dev agregado | cuota máx. / entropía | ambiguous | kL2 agregado | skin1 agregado | Holdout | Tiempo L3 | Notas |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-15 | F3 | Línea base match v0 (score ajuste + λ·cobertura, λ = 1, gap 1,0; paleta por defecto, sigma 0,35) sobre `wada_gen` `generator_hash` a791d9aba4ea, dict fd95ac692777 | 100 / 100 | 100 / 100 | 100 / 100 | 100 / 100 | 57,8 / 68,1 (n = 1044) | 100 / 100 (n = 164) | 100 / 100 (n = 184) | 22,1 / 48,9 | 97,4 / 99,4 | 79,3 / 85,3 (n = 3480) | 1,7 % (combo 222) / 0,990 | 7,8 % | 81,2 / 86,5 (exposure 63,5 / 87,4) | 57,9 / 71,7 | skipped (sin `COLORSAPP_HOLDOUT_SEED`) | 39,2 s (generación 27,0 s; batch 3,9 / 3,8 / 3,9 s); `make eval` 54,8 s; `make eval-fast` 14,7 s; `make l3-fast` cacheado 1,4 s | **Fallan illuminant @3 (68,1 < 80) y exposure @1 (22,1 < 75)**: trabajo de F4 (escalera §6: peso al centro → máscara → kL=2 → piel). golden-check 20/20 + 50/50 a 1e-9. Confusiones más frecuentes: 8→206 (3), 4→53, 13→91, 30→71, 31→115 (2 cada una) |
| 2026-09-15 | F3/F5 (corrección) | Barrido de opciones existentes del match v0 sobre el mismo dev set (3480 imágenes; `ce batch`): kL 1.5 → exposure 49.1/79.0 e illuminant 53.7/62.6; kL 2 → 63.5/87.4 y 50.4/59.5; kL 3 → 73.6/90.8 y 45.7/55.2; kC 1.5/2, λ 0.5/2, σ 0, kL2+λ0.5: ninguna pasa los dos umbrales | 100 / 100 | 100 / 100 | 100 / 100 | 100 / 100 | ≤ 58.8 / 68.9 | 100 / 100 | 100 / 100 | ≤ 73.6 / 90.8 | 92.2–99.7 / 97.1–100 | 78.1–81.2 / 83.8–86.7 | ≤ 2.4 % | 5.2–11.7 % | — | — | — | ~4 s por configuración | Conclusión: exposición e iluminante necesitan modelo explícito (ADR-009), no un ajuste de kL/kC/λ |
| 2026-09-15 | F3/F5 (corrección, ADR-009) | Match v1 (hipótesis de exposición ±1 EV paso 0.5 + iluminante A/D50/D75/F2, penalizaciones 2.0/2.0) por defecto; `wada_gen` `generator_hash` aa604e4ecd99 (dev idéntico), dict fd95ac692777 | 100 / 100 | 100 / 100 | 100 / 100 | 100 / 100 | **94.4 / 98.3** | 100 / 100 | 100 / 100 | **87.6 / 96.6** | 97.4 / 99.1 | **96.8 / 99.1** | 0.9 % (combo 222) / 0.999 | 1.6 % | 96.0 / 98.2 | 66.2 / 79.4 (noadapt = v0: 79.3 / 85.3) | skipped sin semilla; con una semilla de prueba (una semilla de prueba (no anotada), no guardada): ver texto | 53.6 s (generación 29.2 s; batch 6.9 / 6.4 / 6.4 / 4.0 s) | **17/17 checks L3 en verde; todos los umbrales de `thresholds.json` pasan.** Prototipo numpy con rejillas que no contienen ±1 EV (±1.2/0.6, ±0.75, ±1.5/0.75) ni F2/D75 (solo A y D50): exposure 85.3–88.2 / 94.0–96.0, illuminant 93.4–95.1 / 98.0–98.9, todos los umbrales OK → no es un ajuste a los parámetros exactos del generador. Penalizaciones 1–5 probadas: 2.0/2.0 maximiza el agregado sin subir `ambiguous` |
