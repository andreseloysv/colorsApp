# Capa 4 por variantes de recorte e informe visual de capas (sección 10 del contexto:
# fotos con varias personas; requisito del usuario «ver las capas de las que sale el color»).
# Incluido automáticamente por el Makefile raíz (usa ROOT, ORACLE, UV, ENGINE).
#
#   make l4-variants [GOLDEN_DIR=...]   capa 4 sobre el set dorado ($COLORSAPP_GOLDEN_DIR si no se
#                    pasa GOLDEN_DIR) con las variantes none, allPeople, largest, largest-clothing y
#                    largest-clothing-skin (oficial, la de la app). Máscaras por foto: campo "masks" del
#                    manifest (las de la app) > visionmask (build-subject/visionmask; si falta,
#                    make visionmask) > skipped con motivo. Métricas por variante y por tag (grupo
#                    incluido): recall@1/@3 y delta frente a none, cuota máxima, ambiguous, persona
#                    detectada y pasos de fallback; harness/out/l4_detail.json (variants) y la propuesta
#                    L4_variants en harness/out/thresholds.proposed.json. Sin set dorado: skipped, exit 0.
#   make l4-people-smoke             sin set dorado: harness/people/*.png + expected.json (informativo).
#                    ΔE00 del color dominante frente a la ropa anotada de la persona más grande por
#                    variante (mediana, p90) y tabla por foto: harness/out/l4_people_smoke.{json,md}.
#   make layers-report [IMAGES="harness/people/*.png"] [OUT=harness/out/layers]
#                    informe HTML autocontenido (PNG en base64, sin red): una fila por variante (none,
#                    largest, largest-clothing, largest-clothing-skin) y una columna por capa (foto, raster,
#                    reducida, personas, pose y región de ropa, piel quitada, máscara final, peso,
#                    clusters, label map, paleta, top-3 y por qué ganó). Con tus fotos:
#                    make layers-report IMAGES="~/Fotos/prueba/*.jpg" OUT=~/capas   (OUT fuera del repo)
#
# Variables:
#   SEG_BUILD       CMake propio para `ce` (defecto build-seg; no pisa build/ de otros agentes)
#   SEG_VISIONMASK  binario visionmask (defecto el de mk/subject.mk: build-subject/visionmask)
#   SEG_VARIANTS    variantes de l4-variants / l4-people-smoke (vacío = las cinco)
#   LAYERS_VARIANTS variantes de layers-report (defecto none,largest,largest-clothing,largest-clothing-skin)
#   LAYERS_MAX_SIDE lado máximo de cada imagen del HTML (defecto 256)
#   SMOKE_PEOPLE_DIR fotos del smoke test (defecto harness/people)

# IMAGES y OUT son nombres genéricos: una variable de entorno con ese nombre se ignora (solo cuenta la
# línea de make), igual que GOLDEN_DIR en mk/harness.mk.
ifneq ($(filter environment%,$(origin IMAGES)),)
IMAGES :=
endif
ifneq ($(filter environment%,$(origin OUT)),)
OUT :=
endif

SEG_BUILD        ?= $(ROOT)/build-seg
SEG_CE           := $(SEG_BUILD)/tools/ce
SEG_VISIONMASK   ?=
SEG_VARIANTS     ?=
SMOKE_PEOPLE_DIR ?= $(ROOT)/harness/people
IMAGES           := $(or $(strip $(IMAGES)),$(ROOT)/harness/people/*.png)
OUT              := $(or $(strip $(OUT)),$(ROOT)/harness/out/layers)
LAYERS_VARIANTS  ?= none,largest,largest-clothing,largest-clothing-skin
LAYERS_MAX_SIDE  ?= 256

# visionmask se resuelve al ejecutar la receta (mk/subject.mk se incluye después de este fichero).
seg_visionmask = $(or $(strip $(SEG_VISIONMASK)),$(VISIONMASK),$(ROOT)/build-subject/visionmask)
seg_golden_dir = $(or $(strip $(GOLDEN_DIR)),$(COLORSAPP_GOLDEN_DIR))

.PHONY: seg-ce l4-variants l4-people-smoke layers-report

seg-ce:
	cmake -S $(ENGINE) -B $(SEG_BUILD) -DCMAKE_BUILD_TYPE=Release > /dev/null
	cmake --build $(SEG_BUILD) --parallel --target ce

l4-variants: seg-ce
	@if [ -z "$(strip $(seg_golden_dir))" ]; then \
	  echo 'l4-variants: sin GOLDEN_DIR ni $$COLORSAPP_GOLDEN_DIR: la capa 4 queda skipped (el set dorado vive fuera del repo)'; fi
	$(UV) python -m l4.run --cli $(SEG_CE) --out $(ROOT)/harness/out \
	  $(if $(strip $(seg_golden_dir)),--golden-dir "$(seg_golden_dir)",) \
	  --visionmask "$(seg_visionmask)" --build-visionmask $(if $(strip $(SEG_VARIANTS)),--variants $(SEG_VARIANTS),)

l4-people-smoke: seg-ce
	$(UV) python -m l4.people_smoke --cli $(SEG_CE) --people-dir "$(SMOKE_PEOPLE_DIR)" --out $(ROOT)/harness/out \
	  --visionmask "$(seg_visionmask)" --build-visionmask $(if $(strip $(SEG_VARIANTS)),--variants $(SEG_VARIANTS),)

layers-report: seg-ce
	$(UV) python $(ORACLE)/tools/layers_report.py $(IMAGES) --out "$(OUT)" --ce $(SEG_CE) \
	  --visionmask "$(seg_visionmask)" --build-visionmask --variants $(LAYERS_VARIANTS) --max-side $(LAYERS_MAX_SIDE)
