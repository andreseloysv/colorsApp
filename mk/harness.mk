# Harness de validación (sección 6 del plan) y curación de nombres (fase 1).
# Incluido automáticamente por el Makefile raíz (usa ROOT, ORACLE, UV, BUILD).
#
#   make eval        check-protected + capa 1 completa + capa 2 (200 composiciones,
#                    30 invariancias; L3-L4 cuando existan); escribe
#                    harness/out/scorecard.{json,md}; exit 1 mientras falte o falle
#                    alguna capa
#   make eval-fast   igual pero diff-oracle con 10k colores y L2 con 40 composiciones
#                    y 8 invariancias (< 60 s la L2; < 2 min en total)
#   make l2 / l2-fast  solo la capa 2 (oracle.l2) sobre build/tools/ce; escribe
#                    harness/out/l2_detail.json y harness/out/l2/fail/ con los casos
#                    que fallan; exit 1 si 'ce palette' no existe o falla un umbral
#   make names-todo  cuántas combinaciones siguen sin nombre (pending) y sus ids
#   make names-html  genera harness/label/names.html (curación por lotes de 20,
#                    HTML autocontenido; exporta names.es.json)
#
# El scorecard lleva ce_version, dict_version y las versiones de python/numpy/colour.

HARNESS ?= $(ROOT)/harness
HARNESS_OUT ?= $(HARNESS)/out
NAMES_HTML ?= $(HARNESS)/label/names.html

.PHONY: eval eval-fast l2 l2-fast names-todo names-html

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

names-todo:
	$(UV) python -m oracle.names todo

names-html:
	$(UV) python -m oracle.names html --out $(NAMES_HTML)
