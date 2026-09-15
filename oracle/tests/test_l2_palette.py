"""Capa 2 como pytest: ``ce palette`` sobre composiciones sintéticas (versión reducida de
``oracle.l2``: 20 composiciones y 5 invariancias; ``make eval`` ejecuta 200 y 30).

Se salta entera si no hay CLI con el subcomando ``palette`` (``build/tools/ce`` o
``$COLORSAPP_CE_CLI``). Los umbrales son los de ``harness/thresholds.json`` (sección L2),
con los defaults del contrato de F2 para las claves que falten.
"""

from __future__ import annotations

import numpy as np
import pytest

from oracle import l2
from synth import compose as sc

CLI = l2.find_cli_optional()
CLI_HAS_PALETTE = l2.has_palette(CLI)
pytestmark = pytest.mark.skipif(
    not CLI_HAS_PALETTE, reason=f"sin 'ce palette': {l2.not_implemented_reason(CLI)}"
)

TH, _DEFAULTED = l2.resolve_thresholds(l2.load_thresholds())
COMPOSITION_SEEDS = list(range(1, 21))
INVARIANCE_SEEDS = [l2.INVARIANCE_SEED_BASE + k for k in range(1, 6)]


def _ppm(tmp_path, img: np.ndarray, name: str):
    return sc.write_ppm(img, tmp_path / f"{name}.ppm")


# ---- bloque (a): composiciones -------------------------------------------------------------


@pytest.mark.parametrize("seed", COMPOSITION_SEEDS)
def test_composition_uniform_recovers_truth(tmp_path, seed: int):
    layout = l2.layout_for_seed(seed)
    img, truth = sc.compose(seed, layout=layout)
    _labels, variant = sc.compose_labels(seed, layout=layout)
    result = l2.run_palette(CLI, _ppm(tmp_path, img, "c"), center_sigma=0.0)
    assert l2.validate_result(result, img.shape[1], img.shape[0]) == []
    cmp = l2.compare_to_truth(result, truth)
    assert cmp["matched"], (seed, variant, cmp)
    assert cmp["de_max"] < float(TH["color_de00_max"]), (seed, variant, cmp["de"])
    assert cmp["w_err_max"] <= float(TH["weight_abs_error_max"]), (seed, variant, cmp["w_err"])


@pytest.mark.parametrize("seed", COMPOSITION_SEEDS[:6])
def test_composition_default_sigma_finds_the_colors(tmp_path, seed: int):
    """Con el sigma por defecto los colores siguen ahí (los pesos no se comparan: informativo)."""
    img, truth = sc.compose(seed, layout=l2.layout_for_seed(seed))
    result = l2.run_palette(CLI, _ppm(tmp_path, img, "c"))
    assert l2.validate_result(result, img.shape[1], img.shape[0]) == []
    assert result["opts"]["center_sigma"] == pytest.approx(l2.ENGINE_DEFAULT_OPTS["center_sigma"])
    cmp = l2.compare_to_truth(result, truth)
    assert cmp["matched"] and cmp["de_max"] < float(TH["color_de00_max"]), (seed, cmp)


def test_json_contract_details(tmp_path):
    img, _ = sc.compose(1)
    result = l2.run_palette(CLI, _ppm(tmp_path, img, "c"), center_sigma=0.0)
    assert result["engine"] and result["width"] == 200 and result["height"] == 200
    assert result["reduced_width"] == 200 and result["reduced_height"] == 200
    assert result["opts"]["center_sigma"] == 0.0
    for key, value in l2.ENGINE_DEFAULT_OPTS.items():
        if key != "center_sigma":
            assert result["opts"][key] == value, key
    assert abs(sum(s["weight"] for s in result["swatches"]) - 1.0) <= 1e-12
    weights = [s["weight"] for s in result["swatches"]]
    assert weights == sorted(weights, reverse=True)
    assert len(result["hash"]) == 16


def test_max_colors_and_downscale_options(tmp_path):
    img, truth = sc.compose(2)
    big = sc.scale(img, 2.0)  # 400x400 -> el motor reduce por 2 a 200x200
    result = l2.run_palette(CLI, _ppm(tmp_path, big, "big"), center_sigma=0.0, options={"max_colors": 2})
    assert result["width"] == 400 and result["reduced_width"] == 200 and result["reduced_height"] == 200
    assert result["opts"]["max_colors"] == 2
    assert 1 <= len(result["swatches"]) <= 2
    assert l2.validate_result(result, 400, 400, max_colors=2) == []
    # Los dos colores devueltos son los dos de mayor área de la verdad.
    pairs = l2.assign(np.array([t["lab"] for t in truth[:2]]), l2.swatch_labs(result))
    assert len(pairs) == 2 and max(d for _, _, d in pairs) < float(TH["color_de00_max"])


def test_mask_zeroes_a_color(tmp_path):
    """Una máscara P5 a 0 sobre el color de menor área lo elimina de la paleta."""
    img, truth = sc.compose(1, variant="stripes_h")
    smallest = np.array(truth[-1]["rgb"], dtype=np.uint8)
    mask = np.where(np.all(img == smallest, axis=2), 0, 255).astype(np.uint8)
    mask_path = sc.write_pgm(mask, tmp_path / "m.pgm")
    result = l2.run_palette(CLI, _ppm(tmp_path, img, "c"), center_sigma=0.0, mask=mask_path)
    assert l2.validate_result(result, 200, 200) == []
    labs = l2.swatch_labs(result)
    de_to_smallest = l2.de00_matrix(np.array([truth[-1]["lab"]]), labs).min()
    assert de_to_smallest > float(TH["color_de00_max"]), "el color enmascarado no debe aparecer"
    pairs = l2.assign(np.array([t["lab"] for t in truth[:2]]), labs)
    assert len(pairs) == 2 and max(d for _, _, d in pairs) < float(TH["color_de00_max"])
    # Pesos renormalizados sobre los dos colores restantes.
    expected = np.array([t["area"] for t in truth[:2]])
    expected /= expected.sum()
    got = l2.swatch_weights(result)
    for (i, j, _), e in zip(pairs, expected):
        assert abs(got[j] - e) <= float(TH["weight_abs_error_max"])


def test_invalid_inputs_exit_2(tmp_path):
    bad = tmp_path / "bad.ppm"
    bad.write_bytes(b"P6\n1000 1000\n255\n" + b"\x00" * 100)  # cuerpo truncado
    with pytest.raises(l2.PaletteError, match="exit 2"):
        l2.run_palette(CLI, bad, center_sigma=0.0)
    with pytest.raises(l2.PaletteError, match="exit 2"):
        l2.run_palette(CLI, tmp_path / "missing.ppm", center_sigma=0.0)


# ---- bloque (b): invariancias ---------------------------------------------------------------


@pytest.fixture(scope="module")
def invariance_results(tmp_path_factory):
    """Resultados base (uniforme x2 y sigma por defecto) y de cada transformación por semilla."""
    tmp = tmp_path_factory.mktemp("inv")
    out = {}
    for seed in INVARIANCE_SEEDS:
        img, _ = sc.compose(seed, layout=l2.layout_for_seed(seed))
        p = {
            "base": sc.write_ppm(img, tmp / f"{seed}_base.ppm"),
            "shuffle": sc.write_ppm(sc.shuffle_pixels(img, seed), tmp / f"{seed}_shuffle.ppm"),
            "scale_0.5": sc.write_ppm(sc.scale(img, 0.5), tmp / f"{seed}_half.ppm"),
            "scale_2": sc.write_ppm(sc.scale(img, 2.0), tmp / f"{seed}_double.ppm"),
            "mirror": sc.write_ppm(sc.mirror(img), tmp / f"{seed}_mirror.ppm"),
            "rotate180": sc.write_ppm(sc.rotate180(img), tmp / f"{seed}_rot.ppm"),
            "noise": sc.write_ppm(sc.add_noise(img, 2.0, seed), tmp / f"{seed}_noise.ppm"),
        }
        out[seed] = {
            "base_u": l2.run_palette(CLI, p["base"], center_sigma=0.0),
            "base_u2": l2.run_palette(CLI, p["base"], center_sigma=0.0),
            "base_d": l2.run_palette(CLI, p["base"]),
            "shuffle_d": l2.run_palette(CLI, p["shuffle"]),
            **{name: l2.run_palette(CLI, path, center_sigma=0.0) for name, path in p.items() if name != "base"},
        }
    return out


@pytest.mark.parametrize("seed", INVARIANCE_SEEDS)
def test_shuffle_uniform_is_bit_identical(invariance_results, seed: int):
    r = invariance_results[seed]
    cmp = l2.compare_palettes(r["base_u"], r["shuffle"])
    assert cmp["exact"] and cmp["hash_equal"] and cmp["stdout_equal"], cmp
    assert r["base_u"]["_stdout"] == r["shuffle"]["_stdout"]


@pytest.mark.parametrize("seed", INVARIANCE_SEEDS)
def test_shuffle_default_sigma_same_set(invariance_results, seed: int):
    """Con peso al centro el barajado cambia los pesos (no es bit-idéntico por diseño), pero
    el conjunto de colores es el mismo."""
    cmp = l2.compare_palettes(invariance_results[seed]["base_d"], invariance_results[seed]["shuffle_d"])
    assert cmp["same_n"] and cmp["de_max"] < float(TH["invariance.shuffle_center_weighted_de00_max"]), cmp
    assert not cmp["stdout_equal"], "con sigma > 0 los pesos dependen de la posición: no debe ser bit-idéntico"


@pytest.mark.parametrize("seed", INVARIANCE_SEEDS)
@pytest.mark.parametrize("name", ["scale_0.5", "scale_2"])
def test_scale_invariance(invariance_results, seed: int, name: str):
    cmp = l2.compare_palettes(invariance_results[seed]["base_u"], invariance_results[seed][name])
    assert cmp["same_n"] and cmp["de_max"] < float(TH["invariance.scale_de00_max"]), (name, cmp)


@pytest.mark.parametrize("seed", INVARIANCE_SEEDS)
@pytest.mark.parametrize("name", ["mirror", "rotate180"])
def test_mirror_rotate_invariance(invariance_results, seed: int, name: str):
    cmp = l2.compare_palettes(invariance_results[seed]["base_u"], invariance_results[seed][name])
    assert cmp["same_n"] and cmp["de_max"] < float(TH["invariance.mirror_rotate_de00_max"]), (name, cmp)


@pytest.mark.parametrize("seed", INVARIANCE_SEEDS)
def test_noise_invariance(invariance_results, seed: int):
    cmp = l2.compare_palettes(invariance_results[seed]["base_u"], invariance_results[seed]["noise"])
    assert cmp["same_n"] and cmp["de_max"] < float(TH["invariance.noise_sigma2_de00_max"]), cmp


@pytest.mark.parametrize("seed", INVARIANCE_SEEDS)
def test_rerun_same_hash_and_json(invariance_results, seed: int):
    a, b = invariance_results[seed]["base_u"], invariance_results[seed]["base_u2"]
    assert a["hash"] == b["hash"]
    assert a["_stdout"] == b["_stdout"]
