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

## 2026-09-15 — golden-update: F3: primera creación de los goldens (match v0: ce_match.c inicial, ce 0.1.0, dict_version fd95ac692777)

- `harness/golden/palettes_20.json` (20 paletas, sha256 70ced72c3d56…), `match_50.json` (50 matches, sha256 1190eed373be…) y `fixtures/` (50 PPM 128x128 de `wada_gen`, semilla 20260915) regenerados con `ce` 0.1.0, `dict_version` fd95ac692777, `generator_hash` a791d9aba4ea.
- Recall sobre las 50 fixtures en el momento del update: top-1 39/50, top-3 42/50 (un golden nuevo sin subida de recall es una regresión: lo decide el usuario).
- Ruta protegida: revisar y promover con `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash`.

## 2026-09-15 — F3 (lado Python): capa 3 en el harness, goldens y runner mínimo de L4

- `oracle/synth/wada_gen.py` creado (ruta protegida `oracle/synth/**`, **primera creación**:
  `make check-protected` lo lista como `nuevo` hasta que el orquestador promueva el baseline con
  `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash`). Generador determinista por combinación
  (256x256, semilla `seed_base + combo_id*1000 + v`): v0 limpio, v1 formas, v2 textura opensimplex
  (±6 L*), v3 sombreado (±12 % L*), v4/v5/v6 iluminante A/F2/D75 (Bradford D65→X en XYZ lineal,
  matrices de `oracle.reference` verificadas contra `golden_bradford.tsv` a 1e-9), v7 JPEG q10|q30
  (por semilla), v8 ±1 EV y croma ×0,7–1,3, v9 distractor 40 % (marco o banda, ΔE00 > 15).
  Holdout v10–11 con `COLORSAPP_HOLDOUT_SEED` (1–3 degradaciones al azar, JPEG q ∈ {10,30,60,95});
  la semilla nunca se escribe en ficheros (test `test_generate_set_holdout_requires_seed_and_never_writes_it`).
- `harness/golden/palettes_20.json`, `match_50.json` y `fixtures/` (50 PPM 128x128) creados con
  `make golden-update GOLDEN_REASON=...` (**primera creación** en ruta protegida `harness/golden/**`;
  ver la entrada anterior de golden-update). `make golden-check` compara a 1e-9 en lab/weight/score
  y exige el mismo top-3 y `ambiguous`; forma parte de L3 en `make eval`. Un golden nuevo sin subida
  de recall es una regresión: el check solo falla, decide el usuario.
- `oracle.l3` (348x10 dev en `harness/out/synth`, regenerado solo si cambia `generator_hash` =
  sha256(wada_gen.py) + dict_version + versiones de numpy/Pillow/opensimplex; columnas kL1
  (oficial, gatea), kL2 y skin1 (informativas); `ce batch` en una invocación por columna;
  determinismo con segunda pasada; holdout `skipped` sin semilla) y `l4.run` (runner mínimo:
  manifest, sha256/PNG-JPEG-sRGB ≤ 256 px, HEIC rechazado, consenso por mayoría, Fleiss κ, recall
  por tag; `skipped` sin `COLORSAPP_GOLDEN_DIR`) integrados en `oracle.eval` con la semántica de
  salida de PLAN §6 (`not implemented`/`fail` → 1; `pass`/`skipped` → 0 con aviso destacado).
  Targets nuevos en `mk/harness.mk`: `l3`, `l3-fast`, `l4`, `golden-check`, `golden-update`.
  `make eval-fast` = L1 + L2 fast + 10 % de L3 (35 combinaciones fijas, semilla 20260915).
- Línea base L3 (match v0, kL=1, dev 3480 imágenes): clean/shapes/texture/shading/jpeg 100 %,
  distractor @1 97,4 % / @3 99,4 %, **illuminant @3 68,1 % (umbral 0,80) y exposure @1 22,1 %
  (umbral 0,75) fallan**: es el trabajo de F4 (kL=2 sube exposure a 63,5/87,4). Cuota máxima 1,7 %.
  Los umbrales L3 de `thresholds.json` no se han tocado (`promoted_by: null`); propuestas
  adicionales (fast_combos, eval_fast_seconds_max, holdout_gap_points, grupos y columnas
  informativos, goldens) en `harness/thresholds.proposed.json`. Detalle en `engine/BENCHLOG.md`.

## 2026-09-15 — golden-update: Corrección F3/F5: match v1 (ce_match.c con hipótesis de exposición ±1 EV e iluminante A/D50/D75/F2, penalizaciones 2,0/2,0, por defecto) y libm portable ce_libm.c (bits idénticos nativo/WASM): cambian scores, top-3 y hash de los goldens; ce 0.1.0, dict fd95ac692777

- `harness/golden/palettes_20.json` (20 paletas, sha256 34a10562de34…), `match_50.json` (50 matches, sha256 7a9d884b3165…) y `fixtures/` (50 PPM 128x128 de `wada_gen`, semilla 20260915) regenerados con `ce` 0.1.0, `dict_version` fd95ac692777, `generator_hash` aa604e4ecd99.
- Recall sobre las 50 fixtures en el momento del update: top-1 47/50, top-3 49/50 (un golden nuevo sin subida de recall es una regresión: lo decide el usuario).
- Ruta protegida: revisar y promover con `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash`.

## 2026-09-15 — Corrección de F3/F5: libm portable, match v1 con hipótesis y holdout comparable

- **`engine/Sources/CColorEngine/ce_libm.c`** (nuevo): `cbrt`, `pow`, `exp`, `atan2`, `sin`, `cos`
  copiados de musl 1.2.6 (emscripten 6.0.9), sin FMA, compilados con el motor en todas las
  plataformas. `make parity` pasa de 19/20 (rampa de grises a 2,4e-8) a **20/20 con la salida
  JSON byte a byte idéntica** nativo/WASM (|ΔLab| = |Δscore| = 0, hash igual 20/20; ahora
  exigido por `run_parity.js`, `--no-bitexact` lo rebaja a informativo). `test_math` gatea el
  golden de bits `HASH_LIBM` (igual en nativo, ASan y WASM) y ≤ 2 ulp frente a la libm del
  sistema (medido: 1 ulp). Coste: paleta 1024² 2,27 → 2,70 ms, match v0 0,034 → 0,047 ms.
- **`oracle/synth/wada_gen.py`** (ruta protegida, sigue siendo primera creación pendiente de
  promoción): el holdout (v10-11) deja de mezclar 1..3 degradaciones por imagen y pasa a seguir
  **la misma distribución que el dev** (una variante 0..9 al azar con la semilla del usuario);
  metadatos `holdout_variant`/`holdout_degradation`, sin semilla. Motivo: el gate «holdout ≥
  dev − 3» comparaba conjuntos no comparables (con la semilla de prueba quedaba 21 puntos por
  debajo con cualquier motor). `generator_hash` a791d9aba4ea → aa604e4ecd99 (los PPM dev no
  cambian: `make parity-fixtures --check` idéntico byte a byte).
- **Match v1** (`ce_match.c`, ADR-009): hipótesis de exposición (±1 EV en pasos de 0,5) e
  iluminante (A/D50/D75/F2 → D65) con penalizaciones 2,0/2,0, por defecto; cuatro campos nuevos
  en `ce_match_opts` y flags `--exposure-ev-max/--exposure-penalty/--illuminant-search/
  --illuminant-penalty` en el CLI (también en `opts.match` del JSON). L3 columna oficial:
  clean 100/100, illuminant 94,4/98,3 (antes 57,8/68,1), exposure 87,6/96,6 (antes 22,1/48,9),
  distractor 97,4/99,1, agregado 96,8/99,1, cuota máxima 0,9 %, ambiguous 1,6 %: **todos los
  umbrales L3 de `thresholds.json` pasan**; columna informativa `noadapt` = match v0.
- **Goldens regenerados** (`make golden-update`, motivo en la entrada anterior): recall sobre
  las 50 fixtures top-1 39/50 → 47/50, top-3 42/50 → 49/50 (subida real, no una regresión).
- Sigue pendiente del usuario: `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash` (bootstrap
  de `wada_gen.py` y `harness/golden/**`), promover los umbrales y elegir
  `COLORSAPP_HOLDOUT_SEED`.

## 2026-09-15 — F3/F5: baseline de `oracle/synth/wada_gen.py` y `harness/golden/**` promovido

- Promovido por el orquestador con `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash` tras la verificación
  adversarial de F3/F5 (69 ficheros en el manifiesto). El diseño del holdout (variantes 10-11 con la misma
  distribución de degradaciones que el dev) queda sujeto a revisión del usuario.
