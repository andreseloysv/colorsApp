# harness/CHANGELOG.md

Registro de cambios en umbrales, golden files y rutas protegidas del harness (sección 6
del plan, "Anti-Goodhart"). Una entrada por cambio, con el motivo. Los cambios de umbral
los promueve solo el usuario; el agente propone en `harness/out/thresholds.proposed.json`.

## 2026-09-14 — F1: harness base

- `harness/thresholds.json` creado con los umbrales iniciales de la sección 6 del plan
  (L1 tolerancias; L2 composiciones e invariancias; L3 por degradación y cuota máxima 5 %;
  L4 por tag y agregados). `proposed_by: agent`, `promoted_by: null`: **pendiente de que el
  usuario los apruebe** (punto 5 de "lo que se necesita del usuario").
- `engine/tests/data/golden_wada_lab.tsv` creado por `oracle.gen_golden` con el Lab D65 de
  los 159 colores del diccionario (`dict_version fd95ac692777`, status `provisional`,
  0 overrides). Se regenera con `make dict && make golden` cada vez que cambie el diccionario.
- `data/wada/overrides.json` creado vacío (`{"schema": 1, "overrides": []}`); solo lo edita el
  usuario al aceptar una errata.
- `harness/label/names.html` v1 (generado por `make names-html`): curación de nombres por
  lotes de 20; exporta `names.es.json`.
- `make eval` / `make eval-fast` (`oracle.eval`): check-protected + capa 1 completa;
  L2–L4 `not implemented` hasta las fases 2, 3 y 9. Scorecard en `harness/out/`.

## 2026-09-15 — F0/F1: baseline de rutas protegidas promovido

- Baseline de rutas protegidas de F0/F1 (`harness/thresholds.json`, `engine/tests/data/**`,
  `harness/label/names.html`, `data/wada/overrides.json`, `oracle/oracle/reference.py`,
  `data/wada/source/**`) promovido por el orquestador el 2026-09-15 con
  `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash` tras revisión; `make check-protected`
  sale 0 desde entonces. El usuario revisará `PLAN.md` §6 (regla de bootstrap y promoción
  por fase). Los umbrales siguen `promoted_by: null` hasta que el usuario los promueva.

## 2026-09-15 — F2 (lado Python): generador de la capa 2

- `oracle/synth/{__init__,compose}.py` creados (ruta protegida `oracle/synth/**`, primera
  creación: `make check-protected` los lista como `nuevo` hasta que el orquestador promueva el
  baseline con `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash`). Capa 2 en `oracle.l2`
  (200 composiciones + 30 invariancias; `--fast` 40 + 8) integrada en `make eval`/`eval-fast`
  y sola en `make l2`/`l2-fast`; el barajado en modo uniforme exige lab/weight bit-idénticos,
  mismo hash y JSON byte a byte; `eval-fast` gatea además su tiempo total con
  `L2.eval_fast_seconds_max` (120 s). Las claves `compositions_fast`,
  `invariance_compositions(_fast)` y `l2_fast_seconds_max` no están en `thresholds.json` y
  se usan como defaults no promovidos (40/30/8/60 s), anotados en el scorecard.

## 2026-09-15 — F2: baseline de `oracle/synth/**` promovido

- `oracle/synth/compose.py` y `__init__.py` (primera creación en ruta protegida) revisados y
  promovidos por el orquestador con `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash`.
- Umbrales L2 adicionales propuestos en `harness/thresholds.proposed.json` (pendientes del usuario).
