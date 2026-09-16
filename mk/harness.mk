# Harness de validación (sección 6 del plan) y curación de nombres (fase 1).
# Incluido automáticamente por el Makefile raíz (usa ROOT, ORACLE, UV, BUILD).
#
#   make eval        check-protected + capa 1 completa + capa 2 (200 composiciones,
#                    30 invariancias) + capa 3 (3480 sintéticos dev, holdout con
#                    COLORSAPP_HOLDOUT_SEED, golden-check) + capa 4 (con
#                    COLORSAPP_GOLDEN_DIR); escribe harness/out/scorecard.{json,md};
#                    exit 0 con pass/skipped, 1 si falla o falta alguna capa
#   make eval-fast   igual pero diff-oracle con 10k colores, L2 con 40 composiciones
#                    y 8 invariancias y L3 con 35 combinaciones (< 2 min en total)
#   make l2 / l2-fast  solo la capa 2 (oracle.l2) sobre build/tools/ce; escribe
#                    harness/out/l2_detail.json y harness/out/l2/fail/ con los casos
#                    que fallan; exit 1 si 'ce palette' no existe o falla un umbral
#   make l3 / l3-fast  solo la capa 3 (oracle.l3): 348 x 10 sintéticos de wada_gen en
#                    harness/out/synth (cacheados por generator_hash) / 35 combinaciones;
#                    ce batch en tres columnas (kL1 oficial, kL2, skin1), umbrales L3,
#                    holdout si hay COLORSAPP_HOLDOUT_SEED, golden-check; escribe
#                    harness/out/l3_detail.json, l3_table.md y l3_batch_<col>.jsonl
#   make golden-check  compara ce palette/match con harness/golden/{palettes_20,match_50}.json
#                    a 1e-9 y mismo top-3 (también dentro de make eval, parte de L3)
#   make golden-update GOLDEN_REASON="..."  regenera fixtures y goldens (ruta protegida) y
#                    anota el motivo en harness/CHANGELOG.md; exige GOLDEN_REASON
#   make l4          runner mínimo de la capa 4 sobre $COLORSAPP_GOLDEN_DIR (skipped sin ella)
#   make garments-block  solo el bloque «prendas» de L2 (oracle.garments: 170 composiciones sombreadas con
#                    mapa de regiones, incluidas las familias de sombra abierta de exterior que azulea,
#                    estampado con sombra, degradado de color y las informativas bicolor tonal y banda de
#                    fusión; harness/out/garments_detail.json)
#   make garments-sweep  barrido de calibración de la paleta por prenda (shade_kL x shade_merge_de y
#                    percentiles del tono iluminado) sobre las composiciones sombreadas, las de L2, las
#                    imágenes de test_garment y harness/people; harness/out/garments_sweep.{json,md}
#   make names-todo  cuántas combinaciones siguen sin nombre (pending) y sus ids
#   make names-html  genera harness/label/names.html (curación por lotes de 20,
#                    HTML autocontenido; exporta names.es.json)
#   make feedback-report ZIPS="<dir o zips>"  fase 8: informe de uso real a partir de los
#                    zips de Ajustes > Exportar diagnóstico (por teléfono y global: scans,
#                    valoraciones, % sí, cuota del top-1, fuentes, scan.done, fotos con "no";
#                    por modo de recorte y nº de personas si el zip trae esas columnas);
#                    gate F10 (>= 50 valoraciones, sí >= 0,70, cuota <= 0,30; thresholds.json
#                    sección F10 o defaults anotados); harness/out/feedback-report.{json,md};
#                    FEEDBACK_EXTRACT=<dir fuera del repo> copia los PNG valorados y sus máscaras PGM
#   make label-html GOLDEN_DIR=$COLORSAPP_GOLDEN_DIR  genera harness/label/index.html (LABEL_HTML):
#                    página estática con cada foto en base64 + top-10 de ce batch + "ninguna",
#                    juez, tags (negro, denim, gris, interior, fondo-sucio, blanco, grupo) y nota;
#                    vistas con las máscaras <foto>.<variante>.pgm si existen; descarga
#                    labels-<juez>.json. Incrusta las fotos: con fotos personales usa
#                    LABEL_HTML=$COLORSAPP_GOLDEN_DIR/index.html. LABEL_CE=<ruta a ce> usa otro CLI
#                    (sin make build); HEIC y fotos > 256 px se rechazan con mensaje
#   make labels-merge GOLDEN_DIR=... LABELS=<dir con labels-*.json>  fusiona los jueces en
#                    GOLDEN_DIR/manifest.json (consenso por mayoría, Fleiss kappa, sin consenso,
#                    máscaras "masks" descubiertas junto a cada foto)
#   make golden-check GOLDEN_DIR=...  valida el set dorado (>= 50 fotos, los 7 tags, sha256,
#                    3 jueces, PNG/JPEG sRGB <= 256 px, sin HEIC, máscaras con las dimensiones de
#                    la foto, kappa; no compila ce); sin GOLDEN_DIR compara los goldens del motor
#                    (harness/golden/), como siempre
#
# El scorecard lleva ce_version, dict_version y las versiones de python/numpy/colour.

HARNESS ?= $(ROOT)/harness
HARNESS_OUT ?= $(HARNESS)/out
NAMES_HTML ?= $(HARNESS)/label/names.html

GOLDEN_REASON ?=
# Fase 8 (set dorado y uso real). GOLDEN_DIR se pasa explícito en la línea de make: una variable
# de entorno GOLDEN_DIR se ignora para que `make golden-check` a secas siga comprobando los
# goldens del motor (el set dorado del usuario vive en $COLORSAPP_GOLDEN_DIR).
ifneq ($(filter environment%,$(origin GOLDEN_DIR)),)
GOLDEN_DIR :=
endif
ZIPS ?=
GOLDEN_DIR ?=
LABELS ?=
LABEL_HTML ?= $(HARNESS)/label/index.html
LABEL_TOP ?= 10
FEEDBACK_EXTRACT ?=
# CLI para label-html (--ce de label_page.py): por defecto el de build/ (y entonces depende de `build`);
# con otra ruta (p. ej. LABEL_CE=build-f8/tools/ce, compilado con cmake --build build-f8 --target ce)
# no se toca build/.
LABEL_CE ?= $(BUILD)/tools/ce

.PHONY: eval eval-fast l2 l2-fast l3 l3-fast golden-check golden-update l4 names-todo names-html garments-block garments-sweep \
        feedback-report label-html labels-merge

# Códigos de salida: oracle.eval sale con 1 si falta una capa o falla un umbral;
# el wrapper de GNU make devuelve entonces 2 (semántica de make). Criterio: != 0.
eval:
	$(UV) python -m oracle.eval --out $(HARNESS_OUT)

eval-fast:
	$(UV) python -m oracle.eval --fast --out $(HARNESS_OUT)

l2: build
	$(UV) python -m oracle.l2 --cli $(BUILD)/tools/ce --out $(HARNESS_OUT)

l2-fast: build
	$(UV) python -m oracle.l2 --fast --cli $(BUILD)/tools/ce --out $(HARNESS_OUT)

l3: build
	$(UV) python -m oracle.l3 --cli $(BUILD)/tools/ce --out $(HARNESS_OUT)

l3-fast: build
	$(UV) python -m oracle.l3 --fast --cli $(BUILD)/tools/ce --out $(HARNESS_OUT)

golden-check: $(if $(strip $(GOLDEN_DIR)),,build)
ifeq ($(strip $(GOLDEN_DIR)),)
	$(UV) python -m oracle.golden check --cli $(BUILD)/tools/ce
else
	$(UV) python $(ORACLE)/tools/merge_labels.py check --golden-dir "$(GOLDEN_DIR)"
endif

# Los goldens son ruta protegida: solo se regeneran con motivo (va al CHANGELOG) y
# después el usuario revisa y promueve con COLORSAPP_ALLOW_PROTECTED=1 make protected-hash.
golden-update: build
	@if [ -z "$(strip $(GOLDEN_REASON))" ]; then \
	  echo 'golden-update: exige GOLDEN_REASON="motivo" (se anota en harness/CHANGELOG.md; un golden nuevo sin subida de recall es una regresión)'; exit 1; fi
	$(UV) python -m oracle.golden update --cli $(BUILD)/tools/ce --reason "$(GOLDEN_REASON)"

l4: build
	$(UV) python -m l4.run --cli $(BUILD)/tools/ce --out $(HARNESS_OUT)

garments-block: build
	$(UV) python -m oracle.garments block --cli $(BUILD)/tools/ce --out $(HARNESS_OUT)

garments-sweep: build
	$(UV) python -m oracle.garments sweep --cli $(BUILD)/tools/ce --out $(HARNESS_OUT)

names-todo:
	$(UV) python -m oracle.names todo

names-html:
	$(UV) python -m oracle.names html --out $(NAMES_HTML)

# Fase 8: uso real y set dorado. Códigos de salida de las herramientas: 0 ok, 1 gate/validación
# fallida, 2 uso (sin zips, sin fotos, HEIC); make los reporta como "Error 1"/"Error 2".
feedback-report:
	@if [ -z "$(strip $(ZIPS))" ]; then \
	  echo 'feedback-report: exige ZIPS="<dir o lista de zips>" (exports de Ajustes > Exportar diagnóstico; un zip o subdirectorio por teléfono)'; exit 2; fi
	$(UV) python $(ORACLE)/tools/feedback_report.py $(ZIPS) --out $(HARNESS_OUT) $(if $(strip $(FEEDBACK_EXTRACT)),--extract "$(FEEDBACK_EXTRACT)",)

label-html: $(if $(and $(strip $(GOLDEN_DIR)),$(filter $(BUILD)/tools/ce,$(LABEL_CE))),build,)
	@if [ -z "$(strip $(GOLDEN_DIR))" ]; then \
	  echo 'label-html: exige GOLDEN_DIR=$$COLORSAPP_GOLDEN_DIR (directorio con las fotos PNG/JPEG sRGB de 256 px, fuera del repo)'; exit 2; fi
	$(UV) python $(ORACLE)/tools/label_page.py --golden-dir "$(GOLDEN_DIR)" --out "$(LABEL_HTML)" --ce "$(LABEL_CE)" --top $(LABEL_TOP)

labels-merge:
	@if [ -z "$(strip $(GOLDEN_DIR))" ] || [ -z "$(strip $(LABELS))" ]; then \
	  echo 'labels-merge: exige GOLDEN_DIR=$$COLORSAPP_GOLDEN_DIR y LABELS=<dir con labels-*.json de los tres jueces>'; exit 2; fi
	$(UV) python $(ORACLE)/tools/merge_labels.py merge --golden-dir "$(GOLDEN_DIR)" --labels "$(LABELS)"
