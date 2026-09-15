# SubjectKit (apple/SubjectKit): Vision detecta personas, pose y caras; el motor C
# recorta la ropa y excluye la piel (docs/DECISIONS.md, ADR-010). CLI visionmask.
# Incluido automáticamente por el Makefile raíz (usa ROOT, ENGINE).
#
#   make subject-test        swift test de apple/SubjectKit en macOS: cadena de máscaras con
#                            personas sintéticas (sin Vision) y Vision real sobre harness/people
#                            (personas, bbox, ropa sin cabeza, piel y brazos desnudos, tabla de ΔE00
#                            del dominante y reparto del peso de la paleta en prenda / piel / fondo / otro,
#                            con gates de piel) y el cochecito de CONTEXT §12 (sin el color del objeto)
#   make visionmask          swift build -c release del ejecutable y copia a build-subject/visionmask
#   make visionmask-people   visionmask --layers sobre harness/people/*.png hacia
#                            harness/out/people-masks/, `ce batch --json` con cada variante,
#                            reproducción byte a byte de cada capa con `ce regions|cut-head|skin`
#                            (repro.sh de cada <foto>.<variante>.layers/) e informe
#                            harness/out/people-masks/report.md; imprime por foto variante ->
#                            pasos, top-3, color dominante y reparto del peso. Exit != 0 si algo
#                            falla o no se reproduce.
#
# Variables:
#   PEOPLE_DIR           fotos y expected.json (defecto harness/people)
#   PEOPLE_OUT           salida (defecto harness/out/people-masks; se borra al empezar)
#   PEOPLE_VARIANTS      defecto none,allPeople,largest,largest-clothing,largest-clothing-skin
#                        (también allPeople-clothing, allPeople-clothing-skin, largest-skin, selected<N>...)
#   PEOPLE_LAYERS        1 (defecto) escribe las capas; 0 solo máscaras
#   PEOPLE_MIN_COVERAGE  vacío = 0,0005 (SubjectOptions.default: suelo absoluto del raster)
#   (umbral de brazos desnudos y Mahalanobis de la piel: visionmask --bare-arms-fraction / --max-mahalanobis)
#   PEOPLE_MIN_REGION_FRACTION  vacío = 0,15 (regiones mínimas relativas a la silueta de la pose)
#   PEOPLE_REFERENCES    parches de piel y fondo para el reparto del peso (defecto
#                        apple/SubjectKit/Fixtures/people_references.json si PEOPLE_DIR es el de
#                        defecto; vacío = sin reparto)
#   SUBJECT_BUILD        defecto build-subject: visionmask y un `ce` propio en build-subject/engine
#                        (no pisa build/ de otros agentes)

SUBJECT_DIR   := $(ROOT)/apple/SubjectKit
SUBJECT_BUILD ?= $(ROOT)/build-subject
VISIONMASK    := $(SUBJECT_BUILD)/visionmask
SUBJECT_CE    := $(SUBJECT_BUILD)/engine/tools/ce
PEOPLE_DIR    ?= $(ROOT)/harness/people
PEOPLE_OUT    ?= $(ROOT)/harness/out/people-masks
PEOPLE_VARIANTS ?= none,allPeople,largest,largest-clothing,largest-clothing-skin
PEOPLE_LAYERS ?= 1
PEOPLE_MIN_COVERAGE ?=
PEOPLE_MIN_REGION_FRACTION ?=
ifeq ($(PEOPLE_DIR),$(ROOT)/harness/people)
PEOPLE_REFERENCES ?= $(SUBJECT_DIR)/Fixtures/people_references.json
else
PEOPLE_REFERENCES ?=
endif

.PHONY: subject-test visionmask subject-ce visionmask-people

subject-test:
	cd $(SUBJECT_DIR) && swift test

visionmask:
	cd $(SUBJECT_DIR) && swift build -c release --product visionmask
	mkdir -p $(SUBJECT_BUILD)
	cp "$$(cd $(SUBJECT_DIR) && swift build -c release --show-bin-path)/visionmask" $(VISIONMASK)
	@echo "visionmask: $(VISIONMASK)"

subject-ce:
	cmake -S $(ENGINE) -B $(SUBJECT_BUILD)/engine -DCMAKE_BUILD_TYPE=Release > /dev/null
	cmake --build $(SUBJECT_BUILD)/engine --parallel --target ce

visionmask-people: visionmask subject-ce
	sh $(SUBJECT_DIR)/Scripts/people_masks.sh $(VISIONMASK) $(SUBJECT_CE) $(PEOPLE_DIR) $(PEOPLE_OUT) \
	  "$(PEOPLE_VARIANTS)" "$(PEOPLE_LAYERS)" "$(PEOPLE_MIN_COVERAGE)" "$(PEOPLE_MIN_REGION_FRACTION)" \
	  "$(PEOPLE_REFERENCES)"
