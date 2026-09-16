# Motor C (fases 2 y 3): fuzz loop propio bajo ASan/UBSan y mediciones de la
# paleta y del match.
# Incluido automáticamente por el Makefile raíz (usa ROOT, ENGINE, BUILD,
# BUILD_ASAN). `make build` / `make test` ya viven en el Makefile raíz.
#
#   make fuzz [FUZZ_SECONDS=600] [FUZZ_SEED=1]
#       compila engine/tests/fuzz_palette.c con CE_SANITIZE=ON en build-asan/ y
#       lo ejecuta FUZZ_SECONDS segundos (entradas: ce_palette_extract con las
#       capas de depuración, el parser P6/P5 de tools/ce_pnm.c,
#       ce_mask_clothing_regions/ce_mask_cut_head, ce_skin_model_fit/
#       ce_mask_exclude_skin con modelos degenerados y la paleta por prenda:
#       ce_palette_extract_garments/ce_analyze_garments con mapas de regiones y
#       opciones absurdas, capas de prenda y ce_mask_garment_regions frente a
#       ce_mask_clothing_regions). Exit != 0 si ASan/UBSan
#       detecta algo o falla una invariante (semilla y caso para reproducir).
#   make bench-palette
#       ejecuta test_palette en nativo -O2 y muestra PERF_1024_RGBA_MS (la cota
#       de 150 ms la exige el propio test; anotar en engine/BENCHLOG.md).
#   make bench-match
#       ejecuta test_match en nativo -O2 y muestra MATCH_MS, ANALYZE_1024_MS y
#       RECALL_EXACT (cotas 2 ms / 10 ms en el propio test; anotar en BENCHLOG.md).
#   make parity [PARITY_TOL=1e-9] [PARITY_TOP=3]
#       fase 5: compila el CLI `ce` nativo (build/) y WASM (build-wasm/, emcmake,
#       mismo target `ce` que make test-wasm), genera harness/wasm/fixtures/ si
#       falta y ejecuta harness/wasm/run_parity.js (node): `ce match --json` en las
#       dos plataformas sobre las 20 fixtures; |ΔLab|, |Δweight| y |Δscore| del
#       top-3 <= PARITY_TOL, mismo orden de ids y mismo ambiguous; escribe
#       harness/out/parity.json. Después, engine/tests/layers_parity.js exige
#       las capas de depuración (`ce match --debug-dir`: reduced, weights,
#       labels, clusters, swatch_<k>, debug.json con la explicación del top-K)
#       y las máscaras (`ce regions`, `ce skin`, `ce cut-head`, match --mask) y la
#       paleta por prenda (`ce garments --debug-dir` con y sin regiones,
#       `ce garment-regions`, `ce batch --garments`) byte a byte idénticas en
#       nativo y WASM (salidas en build/parity-layers).
#       Exit != 0 si algo difiere.
#   make parity-fixtures
#       regenera harness/wasm/fixtures/ (20 PPM <= 128 px + manifest.json con sha256)
#       con uv y comprueba que la regeneración es idéntica byte a byte (--check).

FUZZ_SECONDS ?= 600
FUZZ_SEED ?= 1
HARNESS_WASM := $(ROOT)/harness/wasm
PARITY_FIXTURES := $(HARNESS_WASM)/fixtures
PARITY_TOL ?= 1e-9
PARITY_TOP ?= 3

.PHONY: fuzz bench-palette bench-match parity parity-build parity-fixtures

fuzz:
	cmake -S $(ENGINE) -B $(BUILD_ASAN) -DCMAKE_BUILD_TYPE=Release -DCE_SANITIZE=ON
	cmake --build $(BUILD_ASAN) --parallel --target fuzz_palette
	$(BUILD_ASAN)/fuzz_palette $(FUZZ_SEED) $(FUZZ_SECONDS)

bench-palette: build
	$(BUILD)/test_palette | grep -E 'PERF_1024_RGBA_MS|Tests .* Failures'

bench-match: build
	$(BUILD)/test_match | grep -E 'MATCH_MS|RECALL_EXACT|Tests .* Failures'

# Paridad nativo/WASM (fase 5). Solo el target `ce` en cada build dir: el mismo
# CMakeLists y las mismas flags que make test / make test-wasm (nunca -ffast-math).
parity-build:
	cmake -S $(ENGINE) -B $(BUILD) -DCMAKE_BUILD_TYPE=Release
	cmake --build $(BUILD) --parallel --target ce
	emcmake cmake -S $(ENGINE) -B $(BUILD_WASM) -DCMAKE_BUILD_TYPE=Release
	cmake --build $(BUILD_WASM) --parallel --target ce

# Las fixtures están versionadas; solo se generan si faltan (exige uv). Para
# regenerarlas a propósito: make parity-fixtures.
$(PARITY_FIXTURES)/manifest.json:
	$(UV) python $(HARNESS_WASM)/make_fixtures.py --out $(PARITY_FIXTURES)

parity-fixtures:
	$(UV) python $(HARNESS_WASM)/make_fixtures.py --out $(PARITY_FIXTURES)
	$(UV) python $(HARNESS_WASM)/make_fixtures.py --check --out $(PARITY_FIXTURES)

parity: parity-build $(PARITY_FIXTURES)/manifest.json
	node $(HARNESS_WASM)/run_parity.js --native $(BUILD)/tools/ce --wasm $(BUILD_WASM)/tools/ce.js \
	  --fixtures $(PARITY_FIXTURES) --tol $(PARITY_TOL) --top $(PARITY_TOP) --out $(ROOT)/harness/out/parity.json
	node $(ENGINE)/tests/layers_parity.js --native $(BUILD)/tools/ce --wasm $(BUILD_WASM)/tools/ce.js \
	  --fixtures $(PARITY_FIXTURES) --out $(BUILD)/parity-layers
