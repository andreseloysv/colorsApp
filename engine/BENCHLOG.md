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
