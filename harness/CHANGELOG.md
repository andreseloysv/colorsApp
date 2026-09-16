# harness/CHANGELOG.md

Registro de cambios en umbrales, golden files y rutas protegidas del harness (sección 6
del plan, "Anti-Goodhart"). Una entrada por cambio, con el motivo. Los cambios de umbral
los promueve solo el usuario; el agente propone en `harness/out/thresholds.proposed.json`.

## 2026-09-16 (3) — Paleta por prenda, tercera vuelta: la penumbra de una sombra cromática NO es una mezcla

- **Motivo** (verificación final, un MAYOR): el requisito literal del usuario (CONTEXT §13, «el
  pantalón es de un solo color») **seguía roto** con sombra azul de exterior, el caso que la vuelta
  anterior declaraba arreglado. Con el generador independiente del verificador, un pantalón liso
  #ddc0c8 con sombra de cielo salía con DOS colores en **32 de 32** escenas, con un segundo color
  azul-violeta falso a ΔE00 24-40. Causa raíz: el **veto de mezcla**. Una oclusión PARCIAL de la luz
  es una combinación lineal de los dos iluminantes, así que los tonos de la PENUMBRA caen sobre el
  segmento entre el tono al sol y el tono en sombra; el motor los tomaba por MEZCLA de dos colores y
  esa marca vetaba `CE_GARMENT_PAIR_SHADE`, el único camino por el que el modelo de cielo puede
  agrupar. La frase de `ce.h` «la penumbra de una sombra no es una mezcla» era FALSA para una sombra
  cromática. Además, el tono iluminado se oscurecía ~1 ΔE00 por paso de sombra (ΔE00 5,2-6,3 con 3
  pasos, por encima del «< 5» de la checklist).
- **Motor** (`ce_garment.c`, `ce.h`): (1) un par que es el **mismo material con distinta luz bajo
  cualquiera de los dos modelos** no puede ser extremo de una mezcla; (2) segundo control de cadena
  **ESTRELLA DE SOMBRA** (todos los miembros de la unión son sombra del más luminoso), alternativo al
  enlace completo, porque el modelo cromático se define desde la luz y dos penumbras de la misma
  rampa no siempre se ajustan entre ellas; (3) los **extremos de una mezcla** tienen que pesar
  ≥ `min_weight` de la región; (4) el núcleo del tono iluminado añade un filtro de **nivel de luz**
  (`CE_GARMENT_LIT_Y_RATIO` 0,5, nuevo `#define` ADITIVO en `ce.h`). Ningún cambio de firma.
- **Goldens**: **NO se han regenerado** (`make golden-check` 20/20 paletas y 50/50 matches a 1e-9).
  El único hash que se mueve es `GARMENT_HASH` (`15db5b325e98c7ac` → `2f33620fa4322acb`), a propósito
  y anotado en el test Unity; idéntico en nativo, ASan y WASM.
- **Generador del bloque «prendas»** (`oracle/oracle/garments.py`, NO protegido): la familia
  `sombra_cielo` era **ciega al fallo** (penumbra de 0-3 px: sin tonos intermedios el motor nunca
  llegaba a tomarlos por mezcla). Ahora tiene penumbra de **6-18 px**, cobertura del **55-70 %** y un
  tercio de los casos con transición **continua**; `estampado_sombra` lleva penumbra de 8-16 px; las
  familias de gate (`rayas`, `estampado_sombra`) rechazan los pares que los dos modelos de sombra
  hacen ambiguos (`same_material_residual < 5`) y la informativa `bicolor_tonal` los mide a propósito
  con los DOS modelos. Con la familia reforzada, el motor ANTERIOR da `sky_shadow_split` 4/15 y el
  bloque 143/150 (7/8 checks); el nuevo, 0/15 y 148/150 (8/8).
- **Umbrales**: sin cambios (`sky_shadow_split_max` 0, `gradient_collapsed_max` 0,
  `print_shadow_lost_max` 1, `colors_ok_rate_min` 0,95, `lit_de00_p90_max` 4,0). Lo que cambia es la
  dureza del generador. Propuesta nueva (no promovida) en `harness/out/thresholds.proposed.json`:
  `lit_de00_deep_shadow_max` 5,0 (ΔE00 del tono iluminado con sombra de 3 pasos; medido 5,24-6,30
  antes y 0,43 ahora) y el límite conocido «cobertura > ~70 % ⇒ se devuelve el tono en sombra».
- **Rutas protegidas**: ninguna tocada. `make check-protected` sigue en rojo por las **14 rutas
  preexistentes** de la entrada del 2026-09-15 (11 PPM de `harness/golden/fixtures`, `match_50.json`,
  `palettes_20.json` y `oracle/synth/wada_gen.py`), a la espera de que el usuario las revise y
  promueva con `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash`. Ningún agente puede hacerlo.

## 2026-09-16 (2) — Paleta por prenda, segunda vuelta: enlace completo, sombra cromática y degradados

- **Motivo** (verificación de la corrección anterior, dos MAYORES): (1) la regla
  `ce_garment_same_material` no tiene límite de luminancia y, con agrupación por **enlace simple
  transitivo**, encadenaba el fondo oscuro de un estampado con su motivo claro — reproducido en la
  MISMA foto real que motivó el límite (`harness/people/02`: el estampado blanco, el 38 % de la
  región, desaparecía y el vestido se partía en dos tarjetas con el mismo marino); (2) la promesa de
  `ce.h` («el límite es dos NEUTROS») no era la del código: la regla une cualquier par que comparta
  cromaticidad. Además, la sombra de exterior contra cielo azul (la única foto real del fallo del
  usuario, `harness/people/06`) seguía partiendo el vaquero liso en dos colores, los degradados de
  color podían colapsar y `ce.h` documentaba percentiles obsoletos.
- **Motor** (`ce_garment.c`, `ce.h`): agrupación por **ENLACE COMPLETO** (un grupo es una camarilla:
  nada se encadena) con el límite de luminancia como condición del par «agrupable»; **veto de
  mezcla** (dos colores unidos por un tono de mezcla nunca son el mismo material con distinta luz);
  **ancla** en la selección (un grupo se suma a un color solo si es compatible con su tono actual y
  con el del primer grupo); **sombra cromática de exterior** como mezcla de dos iluminantes
  (`c ≈ s·(a + w·S·a)`, `S` del cielo CIE D 12000 K sobre escena 5500 K en conos de Bradford, `w`
  estimada del par y acotada por `CE_GARMENT_SKY_W_MAX` 1,15 y `CE_GARMENT_SKY_W_SLOPE` 0,54);
  **regla del degradado** (`CE_GARMENT_GRADIENT_MIN_SHARE` 0,10 con evidencia de mezcla ≥ 0,25 del
  grupo y separación de tono ≥ 12). `CE_GARMENT_SHADE_S_MIN` **0,02 → 0,04** (~4,6 pasos).
  **Sin cambios de API**: solo constantes nuevas en `ce.h`.
- **Bloque «prendas» de L2: 115 → 170 composiciones.** Las 115 anteriores conservan índice, semilla y
  bytes. Familias nuevas: `sombra_cielo` (15, gate `sky_shadow_split_max` 0),
  `estampado_sombra` (10, gate `print_shadow_lost_max` 1: medido 1/10 ahora y 2/10 antes),
  `degradado_color` (10, gate `gradient_collapsed_max` 0) e informativas `bicolor_tonal` (10) y
  `banda_fusion` (10), que miden límites conocidos y quedan FUERA de los gates de `colors_ok_rate` y
  `lit_de00_p90`. Propuesta (no promoción) en `harness/out/thresholds.proposed.json`, sección
  `L2_garments`.
- **Sin cambios en rutas protegidas**: ni `harness/thresholds.json`, ni goldens, ni generadores de
  `oracle/synth/`. `make golden-check` 20/20 + 50/50 y `make parity` en verde; LIGHT_MERGE, MASK,
  DEBUG_LAYERS y RESULT_HASH_COMBO42 no se mueven. **`GARMENT_HASH` cambia a propósito**
  `c9168139c0efbc51` → `15db5b325e98c7ac` (idéntico en nativo, ASan y WASM; el test Unity incluye
  ahora tres escenas nuevas). Los scans guardados con la versión anterior deben re-analizarse.

## 2026-09-16 — Corrección de la paleta por prenda: sombra proyectada y percentiles del tono iluminado

- **Motivo** (verificación de la entrega anterior, hallazgo mayor): una **sombra proyectada
  contigua** (sol contra sombra abierta, 1,5-4 pasos) sobre una prenda lisa sacaba un **segundo
  color falso**, que es literalmente la queja del usuario (CONTEXT §13). Con el generador
  independiente del verificador fallaban 14 de 24 configuraciones de (luz × profundidad), 1 de 15
  con sombra propia y 2 de 5 semillas de un beige liso con luz dura. Ahora **0 en las tres**.
- **Motor** (`ce_garment.c`, `ce.h`): regla nueva `ce_garment_same_material` — dos tonos son el
  mismo tejido con distinta luz si uno es el otro escalado en XYZ lineal (`c ≈ s·a`, s de mínimos
  cuadrados en [`CE_GARMENT_SHADE_S_MIN` 0,02, 50], ΔE00 al modelo < `CE_GARMENT_SHADE_LIT_DE` 3),
  aplicada al agrupar clusters (salta el límite de luminancia) y al seleccionar colores.
  `ce_garment_opts_default`: percentiles **0,60-0,90 → 0,75-0,95** (recalibrados con la métrica
  válida: ΔE00 al color base p50 0,49 → 0,31, p90 3,27 → 1,51). Reserva sin regiones con peso: con
  máscara válida, media de la **máscara** y no de toda la imagen (CONTEXT §12). `region_share`
  documentado como cuota sobre el área que cubre el mapa. **Sin cambios de API**: solo constantes
  nuevas en `ce.h` y valores por defecto.
- **Sin cambios en rutas protegidas**: ni `harness/thresholds.json` ni goldens ni generadores de
  `oracle/synth/`. `make golden-check` 20/20 + 50/50 y `make parity` en verde; los hashes previos
  (LIGHT_MERGE, MASK, DEBUG_LAYERS, RESULT_HASH_COMBO42) no se mueven. **`GARMENT_HASH` cambia**
  (`3f5e33cb77978a44` → `c9168139c0efbc51`, igual en nativo, ASan y WASM): es el hash de la capa de
  prendas, cuyo comportamiento cambia a propósito.
- **L2, bloque «prendas»**: familia nueva `sombra_proyectada` (15 casos; el bloque pasa de 100 a
  **115** composiciones) — sombra contigua de 2-4,5 pasos sobre el 40-60 % de una pieza, borde recto
  con penumbra de 0-3 px, ambiente 0,6-0,8 — y check nuevo **`cast_shadow_split_max` = 0** (prendas
  lisas partidas en dos). Medido: 114/115 colores exactos, `sombra_proyectada` 15/15, p90 1,51,
  0 fusiones erróneas, 0 rayas fundidas. Sin la regla: 108/115, 9/15, 6 prendas partidas.
  Umbrales actualizados en `harness/out/thresholds.proposed.json` (`L2_garments`), **no promovidos**.
- **Tests**: `test_cast_shadow` nuevo en `engine/tests/test_garment.c` (1, 2, 3 y 4 pasos sobre
  media pierna con peso = área, más la camisa de rayas bajo la misma sombra como control) y el caso
  «máscara válida + mapa vacío» en `test_empty_region`. `oracle/tests/test_garments.py` cubre la
  familia nueva.
- **Contrapartida deliberada y límite conocido**: dos neutros cumplen el modelo de sombra (un gris
  medio ES el blanco con menos luz), así que una prenda a rayas blanco + gris sale con un solo
  color; y el vaquero real de `harness/people/06` al sol y a la sombra necesitaría una tolerancia de
  5,75 (la luz del cielo azulea la sombra), pero a partir de 5 se funde una camisa de rayas: sigue
  en `knownEngineLimits` de `GarmentRegionsTests`. Barridos en `engine/BENCHLOG.md`.

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

## 2026-09-15 — F8: tooling del set dorado

- `harness/label/index.html` creado por primera vez (ruta protegida, pendiente de promoción) con `make label-html` sobre 8 imágenes sintéticas; tags del set dorado ampliados con `grupo` (fotos con varias personas: se etiqueta la persona más grande), pendiente de añadir a `L4.tags` de `thresholds.json` por el usuario.
- F9 (capa 4 por variantes de recorte e informe de capas; sin cambios en umbrales, goldens ni rutas protegidas): `oracle/l4/run.py` evalúa `none`, `allPeople`, `largest`, `largest-clothing` y `largest-clothing-skin` (oficial) con máscaras del manifest (`masks`) > `visionmask` > `skipped` con motivo (`make l4-variants`), `make l4-people-smoke` (ΔE00 informativo sobre `harness/people`) y `make layers-report` (HTML de capas); gate propuesto no promovido `L4_variants.official_recall_at_3_minus_none_min_points = -3` en `harness/out/thresholds.proposed.json` (no en `harness/thresholds.proposed.json`, que es ruta protegida).

## 2026-09-15 — Recorte de sujeto, piel y capas: baseline de `harness/label/index.html` promovido

- `harness/label/index.html` (página de etiquetado del set dorado, F8, primera creación) promovido por el
  orquestador con `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash` para poder commitear el punto de control.

## 2026-09-15 — golden-update: illuminant_search=0 por defecto: caso real rosa+negro -> Nº 067 (CONTEXT §11)

- `harness/golden/palettes_20.json` (20 paletas, sha256 30c09f218a57…), `match_50.json` (50 matches, sha256 01bf6fde2a05…) y `fixtures/` (50 PPM 128x128 de `wada_gen`, semilla 20260915) regenerados con `ce` 0.1.0, `dict_version` fd95ac692777, `generator_hash` 37151dcc01ae.
- Recall sobre las 50 fixtures en el momento del update: top-1 47/50, top-3 49/50 (un golden nuevo sin subida de recall es una regresión: lo decide el usuario).
- Ruta protegida: revisar y promover con `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash`.

## 2026-09-15 — Match sin hipótesis de iluminante por defecto, L3 con tinte residual y gate de giro de tono (ADR-009 actualizado)

- **Motivo** (CONTEXT §11): foto real del usuario (camiseta negra + pantalón rosa palo, paleta
  #222524 39 %, #b49aa2 23 %, #917a7e 16 %, #d5b8c0 13 %, #6b5a57 8 %) → Nº 067 (azules) por la
  hipótesis de iluminante A del match v1. `ce_match_opts_default`: `illuminant_search` 1 → **0**
  (la opción sigue existiendo). Por defecto: Nº 337 (19,56), Nº 027 (21,56), Nº 069.
- **`oracle/synth/wada_gen.py`** (ruta protegida, **pendiente de promoción** con
  `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash`): las variantes 4-6 (`illuminant`) simulan el
  tinte residual tras el balance de blancos del teléfono, `(1 − s)·I + s·Bradford(D65 → X)` con
  `s` ~ U[0,25, 0,35] por imagen (sorteado tras la geometría: el resto de variantes conserva sus
  bytes; comprobado contra los sha256 de las 39 fixtures doradas no-iluminante), en vez del
  iluminante completo. `generator_hash` aa604e4ecd99 → 37151dcc01ae.
- **Goldens** (`make golden-update`, entrada anterior): cambian los 11 PPM de iluminante
  (f06, f07, f09, f11, f29, f31, f34, f36, f41, f43, f49), 4 paletas (las 4 fixtures de
  iluminante entre las 20 primeras), el top-3 de 17 matches y solo los scores de otros 8 (25/50
  matches distintos); **ningún top-1 cambia**;
  `ambiguous` 2 → 2. **Recall de las 50 fixtures: top-1 47/50 → 47/50, top-3 49/50 → 49/50 (sin
  subida ni bajada)**; fallan las mismas tres de antes (f24 distractor, f44 y f45 exposición; f44
  pierde 292 del top-3 y f45 gana 305). Desglose: sobre las fixtures viejas (iluminante
  completo) los defaults nuevos darían 41/50 y 44/50 y la hipótesis 47/49; sobre las nuevas
  (tinte residual) las dos configuraciones dan 47/50 y 49/50. No es una mejora de recall en
  sintéticos sino una corrección motivada por una foto real: lo decide el usuario.
- **L3 (dev 3480, columna oficial kL1)** antes → después: illuminant 94,4/98,3 → 98,0/100;
  exposure 87,6/96,6 → 88,8/97,1; distractor 97,4/99,1 → 97,4/99,1; resto 100/100; agregado
  96,8/99,1 → 98,0/99,6; cuota máxima 0,9 % → 0,4 %; ambiguous 1,6 % → 1,0 %. Todos los umbrales
  de `harness/thresholds.json` pasan sin tocarlos. Columna informativa nueva `illum1`
  (defaults + `illuminant_search` 1). Con el generador viejo los defaults nuevos habrían fallado
  illuminant @3 (65,1 < 80).
- **Gate nuevo de giro de tono** en L3 (`oracle/oracle/hue_shift.py`, `ce match-palette`):
  defaults 0,70 % (14/2005), +iluminante 15,6 % (313/2005); umbral propuesto ≤ 1 % en
  `harness/out/thresholds.proposed.json` (`L3_hue_shift`, no promovido; `oracle.l3` lo aplica con
  ese valor por defecto y lo lista entre los umbrales no promovidos).
- **Fixtures derivadas pendientes fuera del área de este cambio**: `make parity-fixtures`
  (`harness/wasm/fixtures/p15_wada_c200_v4_illumA.ppm` y `wada_gen_hash` del manifest; `make parity`
  sigue en verde con las actuales) y `uv run --project oracle python oracle/tools/make_ios_fixtures.py`
  (`ios/ColorsAppTests/Fixtures/expected_match.json`: f24 y f50 cambian de score/top-3, así que
  `EngineParityTests` de la app falla hasta regenerarlo). `make_sim_media.py --check` sigue OK.
- **Experimento de paleta (desactivado)**: `ce_palette_opts.merge_light_de` (campo nuevo al final,
  0 por defecto) fusiona centros con ΔE00(kL = 3) < umbral; medido en `engine/BENCHLOG.md`.

## 2026-09-16 — Paleta por prenda: bloque «prendas» de L2, columna `garments` de L3 y giro de tono por prendas (ADR-011)

- **Motivo** (CONTEXT §13): el mismo pantalón rosa palo salía como cuatro colores (luz, sombra y
  pliegues). Motor: `ce_palette_extract_garments`, `ce_analyze_garments`, `ce_mask_garment_regions`
  y capas `ce_debug_garment_map` / `ce_debug_region_map` (ADR-011, `engine/README.md`).
- **Sin cambios en rutas protegidas**: ni `harness/thresholds.json` ni goldens ni generadores de
  `oracle/synth/`. La paleta clásica y el match no cambian (el refactor del histograma conserva
  todas las operaciones de coma flotante): `make golden-check` 20/20 + 50/50, `make parity` y los
  hashes de `make test` (LIGHT_MERGE, MASK, DEBUG_LAYERS, RESULT_HASH_COMBO42) iguales.
- **L2, bloque nuevo «prendas»** (`oracle/oracle/garments.py`, dentro de `oracle.l2` y por tanto de
  `make eval` / `eval-fast`): 100 composiciones deterministas de una figura sombreada (liso 25,
  rayas 20 (la mitad estampados; bordes desenfocados en luz lineal), vestido 15, dos prendas de tono
  cercano 25 con ΔE00 real 8-18, sombras duras 15; caso 0
  = camiseta #2b2c2c + pantalón #ddc0c8; primer par de tono cercano = #1f2a44 + #3d5b7d) con mapa
  de regiones, por `ce batch --garments`. Checks: colores exactos por prenda >= 0,95 (medido
  99/100), ΔE00 al tono iluminado p90 < 4 (2,61), fusiones erróneas <= 0 (0) con >= 20 pares de
  tono cercano sobre el umbral (25), vestidos sin fusionar <= 5 % (0/15). Umbrales **propuestos**
  en `harness/out/thresholds.proposed.json` (`L2_garments`), no promovidos: `oracle.l2` usa los
  valores por defecto y lo anota. El generador está fuera de `oracle/synth/` (no protegido):
  se propone moverlo ahí al promover.
- **L3**: columna informativa `garments` (`ce batch --garments` sin mapa de regiones: los sintéticos
  de Wada no tienen pose; mide lo que perdería el camino de prendas con una sola región). La
  columna oficial `kL1` y sus umbrales no cambian.
- **Giro de tono** (`oracle.hue_shift`, gate de L3): familia nueva `people-garments:<variante>`
  (paleta por prenda de `harness/people` con las regiones de `ce garment-regions` sobre la pose de
  visionmask). Defaults 0,69 % (14/2023; people-garments 0/18), +iluminante 15,5 % (313/2023).
- **Calibración** (`make garments-sweep`, `harness/out/garments_sweep.{json,md}`): `shade_kL` ×
  `shade_merge_de` (10 × 11) y 9 pares de percentiles sobre el bloque, las 200 composiciones de L2,
  las imágenes de `test_garment` y `harness/people`. Elegido kL 3, umbral 6,5, percentiles
  0,60-0,90; constantes del motor (límite de luminancia 0,2, núcleo 0,35, mezcla 3) calibradas con
  compilaciones del scratchpad (tablas en `engine/BENCHLOG.md`).
- **Capas**: `make layers-report` y `make l4-people-smoke` muestran la capa / tabla «Prendas».

## 2026-09-16 — Paleta por prenda, separación de personas y arreglos del match: baseline promovido

- Promovido por el orquestador con `COLORSAPP_ALLOW_PROTECTED=1 make protected-hash` tras la verificación
  final (passed, ready_to_install): goldens regenerados por `make golden-update` con motivo anotado y
  `oracle/synth/wada_gen.py` con la degradación de iluminante residual (ADR-009). Pendiente de que el
  usuario revise `harness/thresholds.proposed.json` (L2_garments, L3_hue_shift) y promueva umbrales.
