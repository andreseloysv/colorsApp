# SubjectKit (apple/SubjectKit): Vision detecta personas, pose y caras; el motor C
# recorta la ropa y excluye la piel (docs/DECISIONS.md, ADR-010). CLI visionmask.
# Incluido automáticamente por el Makefile raíz (usa ROOT, ENGINE).
#
#   make subject-test        swift test de apple/SubjectKit en macOS: cadena de máscaras con
#                            personas sintéticas (sin Vision) y Vision real sobre harness/people
#                            (personas, bbox, ropa sin cabeza, piel y brazos desnudos, piel del cuerpo
#                            aprendida, crecimiento de la piel en sombra, halo, mangas sin modelo, tabla
#                            de ΔE00 del dominante y reparto del peso de la paleta en prenda / piel /
#                            fondo / otro, con gates de piel por foto con cara visible: <= 5 % de la
#                            paleta por píxel reducido y <= 5 % de la máscara, piel en sombra incluida),
#                            la SEPARACIÓN de las instancias que Vision fusiona (semillas de pose y
#                            cara + ce_mask_split_instance: tabla por foto Vision -> personas, 07 >= 5,
#                            05 tres, 03 y 04 dos, 01/02/08 una, synthetic_tight_selfie tres) y las
#                            caras que no son personas de harness/out/faces (retrato y pantalla,
#                            solos y pegados a una persona: genera antes con subject-faces),
#                            las regiones de prenda de la pose y la paleta por prenda (un color por
#                            prenda lisa con su tono iluminado; pantalón liso <= 1 color abajo,
#                            CONTEXT §13 y ADR-011),
#                            el cochecito de CONTEXT §12 y las personas fantasma (evidencia corporal:
#                            pose, cara o rectángulo de persona): 0 personas en los 20 PNG de
#                            ios/ColorsAppTests/Fixtures/sim_media y en >= 98 % de las 148 sintéticas sin
#                            personas y de sus 48 prendas (genera antes harness/out/nopeople con subject-nopeople)
#   make subject-faces       harness/people/faces/build_faces.py build: 8 PNG con caras que NO son
#                            personas (retrato enmarcado y pantalla, solos, pegados a una persona
#                            real, detrás de ella y sobre su torso) en harness/out/faces,
#                            comprobadas contra faces.json (sha256 de píxeles)
#   make visionmask-faces    visionmask sobre harness/out/faces con la separación y sin la regla de
#                            evidencia corporal de las semillas de cara (--no-face-seed-body) para
#                            medir el fallo y el arreglo; imprime personas por fixture
#   make subject-nopeople    harness/people/nopeople/build_nopeople.py build: 148 PNG sin personas
#                            (bloques, degradados, texturas y prendas en percha, perchero, planas y en
#                            puerta, con colores de Wada) en harness/out/nopeople,
#                            comprobadas contra nopeople.json (sha256 de píxeles)
#   make visionmask-nopeople visionmask sobre harness/out/nopeople y sim_media hacia
#                            harness/out/people-masks-nopeople/: tabla antes (instancias de Vision) /
#                            después (personas aceptadas); exit != 0 si alguna de sim_media conserva una
#                            persona o menos del 98 % de las 148 sintéticas (o de sus prendas) quedan sin personas
#   make visionmask          swift build -c release del ejecutable y copia a build-subject/visionmask
#   make visionmask-people   visionmask --layers sobre harness/people/*.png hacia
#                            harness/out/people-masks/, `ce batch --json` con cada variante
#                            (y `ce batch --garments --n-regions 2` con la variante
#                            largest-clothing-skin-garments: mapa de regiones de prenda de la pose +
#                            máscara -> un color por prenda, ADR-011; el informe añade «Colores por
#                            prenda» por foto y la tabla antes/después con el gate informativo del
#                            pantalón liso),
#                            reproducción byte a byte de cada capa con `ce regions|cut-head|skin`
#                            y, en las variantes -garments, `ce garment-regions` y `ce garments
#                            --debug-dir` (mapa, capa «Prendas» y hash de ce_garment_hash)
#                            (repro.sh de cada <foto>.<variante>.layers/), de cada instancia
#                            fusionada separada con `ce split` (<foto>.split_repro.sh) e informe
#                            harness/out/people-masks/report.md; imprime por foto variante ->
#                            pasos, top-3, color dominante y reparto del peso. Exit != 0 si algo
#                            falla, no se reproduce o la variante por defecto deja > 5 % de piel en la
#                            paleta o en la máscara de una foto con cara visible.
#
# Variables:
#   PEOPLE_DIR           fotos y expected.json (defecto harness/people)
#   PEOPLE_OUT           salida (defecto harness/out/people-masks; se borra al empezar)
#   PEOPLE_VARIANTS      defecto none,allPeople,largest,largest-clothing,largest-clothing-skin,
#                        largest-clothing-skin-garments (también allPeople-clothing,
#                        allPeople-clothing-skin, largest-skin, selected<N>..., y el sufijo -garments
#                        en cualquiera: paleta por prenda con el mapa de regiones de la pose)
#   PEOPLE_LAYERS        1 (defecto) escribe las capas; 0 solo máscaras
#   PEOPLE_MIN_COVERAGE  vacío = 0,0005 (SubjectOptions.default: suelo absoluto del raster)
#   (umbral de brazos desnudos y Mahalanobis de la piel: visionmask --bare-arms-fraction / --max-mahalanobis)
#   PEOPLE_MIN_REGION_FRACTION  vacío = 0,15 (regiones mínimas relativas a la silueta de la pose)
#   NOPEOPLE_OUT         defecto harness/out/nopeople (subject-nopeople, subject-test, visionmask-nopeople)
#   NOPEOPLE_MASKS       defecto harness/out/people-masks-nopeople (visionmask-nopeople)
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
PEOPLE_VARIANTS ?= none,allPeople,largest,largest-clothing,largest-clothing-skin,largest-clothing-skin-garments
PEOPLE_LAYERS ?= 1
PEOPLE_MIN_COVERAGE ?=
PEOPLE_MIN_REGION_FRACTION ?=
FACES_OUT     ?= $(ROOT)/harness/out/faces
FACES_MASKS   ?= $(ROOT)/harness/out/people-masks-faces
NOPEOPLE_OUT  ?= $(ROOT)/harness/out/nopeople
NOPEOPLE_MASKS ?= $(ROOT)/harness/out/people-masks-nopeople
SIM_MEDIA_DIR := $(ROOT)/ios/ColorsAppTests/Fixtures/sim_media
ifeq ($(PEOPLE_DIR),$(ROOT)/harness/people)
PEOPLE_REFERENCES ?= $(SUBJECT_DIR)/Fixtures/people_references.json
else
PEOPLE_REFERENCES ?=
endif

.PHONY: subject-test subject-nopeople subject-faces visionmask subject-ce visionmask-people \
        visionmask-nopeople visionmask-faces

subject-nopeople:
	$(UV) python $(ROOT)/harness/people/nopeople/build_nopeople.py build --out $(NOPEOPLE_OUT)

subject-faces:
	$(UV) python $(ROOT)/harness/people/faces/build_faces.py build --out $(FACES_OUT)

subject-test: subject-nopeople subject-faces
	cd $(SUBJECT_DIR) && COLORSAPP_NOPEOPLE_REQUIRED=1 COLORSAPP_FACES_REQUIRED=1 swift test

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

# Caras que no son personas: con la regla de evidencia corporal (por defecto) y sin ella.
visionmask-faces: visionmask subject-faces
	@mkdir -p $(FACES_MASKS)
	@echo "== con la regla de evidencia corporal de las semillas de cara (por defecto)"
	@for f in $(FACES_OUT)/*.png; do $(VISIONMASK) "$$f" --out-dir $(FACES_MASKS)/con --variants largest || exit 1; done
	@echo "== sin la regla (--no-face-seed-body): el fallo que arregla ADR-010"
	@for f in $(FACES_OUT)/*.png; do $(VISIONMASK) "$$f" --out-dir $(FACES_MASKS)/sin --variants largest --no-face-seed-body || exit 1; done
	@echo "== sin separar instancias (--no-split), referencia"
	@for f in $(FACES_OUT)/*.png; do $(VISIONMASK) "$$f" --out-dir $(FACES_MASKS)/nosplit --variants largest --no-split || exit 1; done

visionmask-nopeople: visionmask subject-nopeople
	sh $(SUBJECT_DIR)/Scripts/nopeople_masks.sh $(VISIONMASK) $(NOPEOPLE_OUT) $(SIM_MEDIA_DIR) $(NOPEOPLE_MASKS) "$(UV) python"
