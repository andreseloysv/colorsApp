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
