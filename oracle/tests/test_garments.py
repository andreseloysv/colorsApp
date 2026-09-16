"""Paleta por prenda (``oracle.garments``, ``ce garments`` / ``ce batch --garments``).

* Sin CLI: generador determinista (mismos bytes), reparto por familias, verdad de los pares de tono
  cercano (ΔE00 real en [8, 18]), casos canónicos (pantalón rosa y camiseta negra; azul marino y
  vaquero), geometría de la figura y métricas de ``evaluate_case`` con resultados fabricados.
* Con ``ce garments``: bloque «prendas» de L2 sobre 40 composiciones sin fusiones erróneas, el
  pantalón rosa en 2 swatches (el de abajo a ΔE00 < 4 de #ddc0c8), el par azul marino / vaquero sin
  fusionar, la paleta real del tranvía en bandas con un solo color abajo y la columna ``garments``
  de L3 (``ce batch --garments``) con hits.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

from oracle import garments as gm
from oracle import l3
from synth import wada_gen as wg

CLI = l3.find_cli_optional()
HAS = gm.has_garments(CLI)
needs_cli = pytest.mark.skipif(not HAS, reason="sin 'ce garments' (make build)")


def test_cases_are_deterministic():
    a = gm.build_cases(12)
    b = gm.build_cases(12)
    assert [c.kind for c in a] == [c.kind for c in b]
    for x, y in zip(a, b):
        assert x.img.tobytes() == y.img.tobytes()
        assert x.mask.tobytes() == y.mask.tobytes() and x.regions.tobytes() == y.regions.tobytes()
        assert x.truth == y.truth


def test_kind_shares_and_canonical_cases():
    cases = gm.build_cases(gm.N_CASES)
    counts = {k: sum(c.kind == k for c in cases) for k in gm.KINDS}
    assert counts == gm.KIND_SHARES
    assert counts["sombra_proyectada"] > 0
    cast = [c for c in cases if c.kind == "sombra_proyectada"]
    assert all(c.shadow_stops is not None and 2.0 <= c.shadow_stops <= 4.5 for c in cast)
    assert all(c.truth.keys() == {1, 2} for c in cast)
    liso = next(c for c in cases if c.kind == "liso")
    assert liso.truth == {1: [gm.PINK_PANTS["top"]], 2: [gm.PINK_PANTS["bottom"]]}
    close = [c for c in cases if c.kind == "tono_cercano"]
    assert close[0].truth == {1: [gm.NAVY_DENIM["top"]], 2: [gm.NAVY_DENIM["bottom"]]}
    assert close[0].pair_de00 == pytest.approx(16.76, abs=0.01)
    for c in close[1:]:
        assert 8.0 <= c.pair_de00 <= 18.0
        assert gm.de00(gm.lab_of(c.truth[1][0]), gm.lab_of(c.truth[2][0])) == pytest.approx(c.pair_de00)
    assert all(c.truth.keys() == {3} for c in cases if c.kind == "vestido")
    assert all(len(c.truth[1]) == 2 for c in cases if c.kind == "rayas")


def test_sky_matrix_and_gain_match_engine_constants():
    """La matriz del azuleo de la sombra (``CE_GARMENT_SKY_M`` de ce.h) y las ganancias del test
    Unity se recalculan aquí con colour-science: si alguien toca una constante sin rehacer la
    derivación, este test lo caza."""
    ce_h = (Path(__file__).resolve().parents[2] / "engine" / "Sources" / "CColorEngine" / "include" / "ce"
            / "ce.h").read_text(encoding="utf-8")
    src = (Path(__file__).resolve().parents[2] / "engine" / "Sources" / "CColorEngine"
           / "ce_garment.c").read_text(encoding="utf-8")
    body = src.split("CE_GARMENT_SKY_M[9] = {", 1)[1].split("};", 1)[0]
    values = [float(x) for x in body.replace("\n", " ").split(",") if x.strip()]
    assert len(values) == 9
    np.testing.assert_allclose(np.array(values).reshape(3, 3), gm.sky_matrix(), atol=1e-9)

    unity = (Path(__file__).resolve().parents[2] / "engine" / "tests" / "test_garment.c").read_text(encoding="utf-8")
    gains = [float(x) for x in unity.split("SKY_SHADOW_GAIN[3] = {", 1)[1].split("}", 1)[0].split(",")]
    np.testing.assert_allclose(np.array(gains), gm.sky_shadow_gain(2.5), atol=5e-9)

    # Las constantes de ce.h que fija ADR-011 (segunda vuelta) siguen donde dice el oráculo.
    for name, value in gm.ENGINE_SHADE_CONSTANTS.items():
        assert f"#define {name} {value}" in ce_h or f"#define {name} {value:g}" in ce_h, name


def test_new_families_are_well_formed():
    """Familias nuevas del bloque: sombra azul (2-3,3 pasos), estampado con sombra (los dos colores
    NO son un par tonal), degradado de color (dos extremos esperados) y las informativas."""
    cases = gm.build_cases(gm.N_CASES)
    sky = [c for c in cases if c.kind == "sombra_cielo"]
    assert sky and all(c.shadow_stops is not None and 2.0 <= c.shadow_stops <= 3.3 for c in sky)
    prints = [c for c in cases if c.kind == "estampado_sombra"]
    assert prints and all(gm.scaled_model_residual(*c.truth[1]) >= 8.0 for c in prints)
    assert all(gm.sky_model_residual(*c.truth[1]) >= 5.0 for c in prints)
    grads = [c for c in cases if c.kind == "degradado_color"]
    assert grads and all(c.expected_counts == {1: 1, 2: 2} for c in grads)
    # Los pares de las familias de GATE no pueden ser ambiguos para los dos modelos de sombra del
    # motor (si lo fueran, medirían el límite conocido de ADR-011 en vez de lo que dicen medir).
    stripes = [c for c in cases if c.kind == "rayas"]
    assert stripes and all(gm.same_material_residual(*c.truth[1]) >= 5.0 for c in stripes)
    # La familia informativa mide ese límite a propósito, con los DOS modelos (mitad y mitad). No
    # todos los pares del modelo (2) caen dentro: las ganancias del generador son una diagonal en
    # sRGB lineal y el motor modela la adaptación en conos de Bradford, así que en los tintes muy
    # saturados los dos modelos se separan (9 de 10 ambiguos; el que no lo es sale con dos colores).
    tonal = [c for c in cases if c.kind == "bicolor_tonal"]
    assert tonal and sum(1 for c in tonal if gm.same_material_residual(*c.truth[1]) < 3.0) >= 8
    assert sum(1 for c in tonal if gm.scaled_model_residual(*c.truth[1]) >= 3.0) >= len(tonal) // 2 - 1
    band = [c for c in cases if c.kind == "banda_fusion"]
    assert band and all(4.5 <= (c.pair_de00 or 0.0) <= 8.5 for c in band)
    assert set(gm.INFORMATIVE_KINDS) <= set(gm.KINDS)


def test_figure_regions_inside_mask():
    c = gm.make_case(3, "rayas", 99)
    assert c.img.shape == (gm.SIZE[1], gm.SIZE[0], 3)
    assert set(np.unique(c.regions)) == {0, 1, 2}
    assert np.all((c.regions > 0) == (c.mask == 255))
    rows_upper = np.where((c.regions == 1).any(axis=1))[0]
    rows_lower = np.where((c.regions == 2).any(axis=1))[0]
    assert rows_upper.max() < rows_lower.min()


def test_shading_darkens_in_linear_light():
    rng = np.random.default_rng(1)
    base = np.full((10, 40, 3), (0xDD, 0xC0, 0xC8), dtype=np.uint8)
    piece = gm.shade_piece(base, rng, light_x=0.0, folds=0, fold_factor=0.55, specular=0.0)
    lum = piece.astype(float).mean(axis=(0, 2))
    assert lum.max() <= 0xDD + 1 and lum.min() < lum.max() - 30  # bordes en sombra (factor 0,45)
    assert np.argmax(lum) in range(15, 25)  # luz de frente: el centro es lo más claro


def _result(garments):
    return {"garments": [{"region": r, "lab": list(gm.lab_of(rgb)), "hex": "#%02x%02x%02x" % rgb, "weight": w,
                          "n_merged_clusters": 2} for r, rgb, w in garments]}


def test_evaluate_case_metrics_without_cli():
    liso = gm.make_case(0, "liso", 5, canonical=True)
    ok = gm.evaluate_case(liso, _result([(2, gm.PINK_PANTS["bottom"], 0.6), (1, gm.PINK_PANTS["top"], 0.4)]))
    assert ok["colors_ok"] and not ok["wrong_fusion"] and max(ok["lit_de"]) < 1e-9
    fused = gm.evaluate_case(liso, _result([(3, gm.PINK_PANTS["bottom"], 1.0)]))
    assert not fused["colors_ok"] and fused["wrong_fusion"] and np.isinf(max(fused["lit_de"]))
    dress = gm.make_case(1, "vestido", 6)
    missed = gm.evaluate_case(dress, _result([(1, dress.truth[3][0], 0.5), (2, dress.truth[3][0], 0.5)]))
    assert missed["missed_fusion"] and not missed["colors_ok"]
    stripes = gm.make_case(2, "rayas", 7)
    merged = gm.evaluate_case(stripes, _result([(1, stripes.truth[1][0], 0.5), (2, stripes.truth[2][0], 0.5)]))
    assert merged["stripes_merged"] and not merged["colors_ok"]
    s = gm.summarize([ok, fused, missed, merged], 6.5)
    assert s["colors_ok"] == 1 and s["wrong_fusions"] == 1 and s["missed_fusions"] == 1 and s["stripes_merged"] == 1


def test_thresholds_default_and_override():
    th, defaulted = gm.resolve_thresholds({"L2": {"garments": {"cases": 40}}})
    assert th["cases"] == 40 and "cases" not in defaulted and "wrong_fusions_max" in defaulted
    th, defaulted = gm.resolve_thresholds(None)
    assert th == gm.DEFAULTS and len(defaulted) == len(gm.DEFAULTS)


@needs_cli
def test_block_on_all_compositions(tmp_path: Path):
    checks, detail = gm.run_block(CLI, None, tmp_path, log=lambda *_: None)
    status = {c.name.split(":")[0]: c.status for c in checks}
    summ = detail["summary"]
    assert summ["wrong_fusions"] == 0 and summ["stripes_merged"] == 0, summ
    assert summ["colors_ok_rate"] >= 0.95 and summ["lit_de00_p90"] < 4.0, summ
    n_close = sum(1 for c in gm.build_cases(gm.N_CASES) if c.kind == "tono_cercano")
    assert summ["close_pairs_over_threshold"] == summ["close_pairs"] == n_close
    assert summ["cast_shadow_split"] == 0 and summ["cast_shadow_cases"] > 0
    # Familias nuevas (ADR-011, segunda vuelta): la sombra azul de exterior no parte una prenda lisa
    # y un degradado de color no colapsa. El estampado con sombra tiene su propio umbral (1/10).
    assert summ["sky_shadow_split"] == 0 and summ["sky_shadow_cases"] > 0
    assert summ["gradient_collapsed"] == 0 and summ["gradient_cases"] > 0
    assert summ["print_shadow_lost"] <= gm.DEFAULTS["print_shadow_lost_max"]
    # Límites conocidos y medidos (informativos, fuera de los gates).
    # Informativo: casi todos los pares tonales se pierden (límite conocido de ADR-011); el margen
    # de 2 es para los pares del modelo de cielo muy saturados, donde el generador (diagonal en sRGB
    # lineal) y el motor (conos de Bradford) se separan y el par sobrevive.
    assert summ["tonal_kept"] <= 2 and summ["tonal_cases"] > 0
    assert [c.status for c in checks if "límites conocidos" in c.name] == ["info"]
    assert not [c for c in checks if c.status == "fail"]
    assert any(s == "pass" for s in status.values())


@needs_cli
def test_pink_pants_navy_denim_and_real_palette(tmp_path: Path):
    cases = [gm.pink_pants_case(), gm.make_case(1, "tono_cercano", 11, canonical=True), gm.real_pants_proxy()]
    rows, _summ = gm.evaluate(CLI, cases, tmp_path)
    pink, navy, real = rows
    assert pink["counts"] == {"1": 1, "2": 1} and pink["lit_de"][1] < 4.0 and pink["lit_de"][0] < 6.0
    assert navy["counts"] == {"1": 1, "2": 1} and not navy["wrong_fusion"]
    assert real["counts"] == {"1": 1, "2": 1}


@needs_cli
def test_l3_garments_column_runs_batch(tmp_path: Path):
    files = []
    for cid in (1, 200):
        img, _meta = wg.variant(cid, 0)
        from synth import compose as sc

        files.append(sc.write_ppm(img, tmp_path / f"c{cid}.ppm"))
    rows = l3.run_batch(CLI, files, extra_args=l3.COLUMNS["garments"]["extra"])
    assert len(rows) == 2 and all("hits" in r and "garments" in r for r in rows)
    assert all(g["region"] == 0 for r in rows for g in r["garments"])
