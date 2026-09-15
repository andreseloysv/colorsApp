# Motor C (fase 2): fuzz loop propio bajo ASan/UBSan y medición de la paleta.
# Incluido automáticamente por el Makefile raíz (usa ROOT, ENGINE, BUILD,
# BUILD_ASAN). `make build` / `make test` ya viven en el Makefile raíz.
#
#   make fuzz [FUZZ_SECONDS=600] [FUZZ_SEED=1]
#       compila engine/tests/fuzz_palette.c con CE_SANITIZE=ON en build-asan/ y
#       lo ejecuta FUZZ_SECONDS segundos (dos entradas: ce_palette_extract y
#       el parser P6/P5 de tools/ce_pnm.c). Exit != 0 si ASan/UBSan detecta
#       algo o falla una invariante (imprime semilla y caso para reproducir).
#   make bench-palette
#       ejecuta test_palette en nativo -O2 y muestra PERF_1024_RGBA_MS (la cota
#       de 150 ms la exige el propio test; anotar en engine/BENCHLOG.md).

FUZZ_SECONDS ?= 600
FUZZ_SEED ?= 1

.PHONY: fuzz bench-palette

fuzz:
	cmake -S $(ENGINE) -B $(BUILD_ASAN) -DCMAKE_BUILD_TYPE=Release -DCE_SANITIZE=ON
	cmake --build $(BUILD_ASAN) --parallel --target fuzz_palette
	$(BUILD_ASAN)/fuzz_palette $(FUZZ_SEED) $(FUZZ_SECONDS)

bench-palette: build
	$(BUILD)/test_palette | grep -E 'PERF_1024_RGBA_MS|Tests .* Failures'
