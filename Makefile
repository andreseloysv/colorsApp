# Makefile raíz de colorsApp. Todas las rutas son relativas a este fichero, así
# que funciona desde cualquier cwd (make -C ... o make -f ...).
#
#   make test         nativo: cmake + build + ctest en build/
#   make test-asan    ASan/UBSan (CE_SANITIZE=ON) en build-asan/
#   make test-wasm    Emscripten (emcmake) en build-wasm/, tests con node
#   make golden       regenera los golden TSV con el oráculo Python
#   make diff-oracle  100k colores sRGB8 por 'ce convert' vs oráculo estricto
#   make swift-test   swift test del paquete engine/
#   make dict         regenera dictionary.json, errata.json y ce_dict_data.h
#   make dict-check   verifica que los artefactos generados están al día
#   make clean
#
# Los targets de cada área viven en mk/*.mk (foundations, harness, ios...) y se
# incluyen automáticamente al final de este fichero.

ROOT   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ENGINE := $(ROOT)/engine
ORACLE := $(ROOT)/oracle
BUILD      := $(ROOT)/build
BUILD_ASAN := $(ROOT)/build-asan
BUILD_WASM := $(ROOT)/build-wasm

UV     := uv run --project $(ORACLE)
CTEST  := ctest --output-on-failure --verbose
DIFF_N ?= 100000
# Paso del round-trip exhaustivo en WASM (1 = los 16.7M colores; tarda ~2 s con
# node; se puede subir a 16 para muestrear 1/16 con paso determinista).
WASM_ROUNDTRIP_STEP ?= 1

.PHONY: all test test-asan test-wasm golden diff-oracle swift-test dict clean build

all: test

build:
	cmake -S $(ENGINE) -B $(BUILD) -DCMAKE_BUILD_TYPE=Release
	cmake --build $(BUILD) --parallel

test: build
	$(CTEST) --test-dir $(BUILD)

test-asan:
	cmake -S $(ENGINE) -B $(BUILD_ASAN) -DCMAKE_BUILD_TYPE=Release -DCE_SANITIZE=ON
	cmake --build $(BUILD_ASAN) --parallel
	$(CTEST) --test-dir $(BUILD_ASAN)

test-wasm:
	emcmake cmake -S $(ENGINE) -B $(BUILD_WASM) -DCMAKE_BUILD_TYPE=Release -DCE_ROUNDTRIP_STEP=$(WASM_ROUNDTRIP_STEP)
	cmake --build $(BUILD_WASM) --parallel
	$(CTEST) --test-dir $(BUILD_WASM)

golden:
	$(UV) python -m oracle.gen_golden

diff-oracle: build
	$(UV) python -m oracle.diff_oracle --cli $(BUILD)/tools/ce --n $(DIFF_N)

swift-test:
	cd $(ENGINE) && swift test

dict:
	$(UV) python -m oracle.build_dictionary --emit-c

dict-check:
	$(UV) python -m oracle.build_dictionary --check --emit-c

clean:
	rm -rf $(BUILD) $(BUILD_ASAN) $(BUILD_WASM) $(ENGINE)/.build

# Targets adicionales por área (cada agente/área mantiene su propio .mk).
-include $(ROOT)/mk/*.mk
