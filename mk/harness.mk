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
#   make names-todo  cuántas combinaciones siguen sin nombre (pending) y sus ids
#   make names-html  genera harness/label/names.html (curación por lotes de 20,
#                    HTML autocontenido; exporta names.es.json)
#
# El scorecard lleva ce_version, dict_version y las versiones de python/numpy/colour.

HARNESS ?= $(ROOT)/harness
HARNESS_OUT ?= $(HARNESS)/out
NAMES_HTML ?= $(HARNESS)/label/names.html

GOLDEN_REASON ?=

.PHONY: eval eval-fast l2 l2-fast l3 l3-fast golden-check golden-update l4 names-todo names-html

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

golden-check: build
	$(UV) python -m oracle.golden check --cli $(BUILD)/tools/ce

# Los goldens son ruta protegida: solo se regeneran con motivo (va al CHANGELOG) y
# después el usuario revisa y promueve con COLORSAPP_ALLOW_PROTECTED=1 make protected-hash.
golden-update: build
	@if [ -z "$(strip $(GOLDEN_REASON))" ]; then \
	  echo 'golden-update: exige GOLDEN_REASON="motivo" (se anota en harness/CHANGELOG.md; un golden nuevo sin subida de recall es una regresión)'; exit 1; fi
	$(UV) python -m oracle.golden update --cli $(BUILD)/tools/ce --reason "$(GOLDEN_REASON)"

l4: build
	$(UV) python -m l4.run --cli $(BUILD)/tools/ce --out $(HARNESS_OUT)

names-todo:
	$(UV) python -m oracle.names todo

names-html:
	$(UV) python -m oracle.names html --out $(NAMES_HTML)
