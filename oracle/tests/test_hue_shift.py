"""Métrica de giro de tono (``oracle.hue_shift``) y regresión del caso real rosa palo + negro.

* Sin CLI: muestreo determinista y dentro de gamut, familias, criterio de giro sobre el caso real
  (Nº 067 gira el mauve ~87°; Nº 337 no).
* Con ``ce match-palette``: el caso real por defecto no es azul y con la hipótesis de iluminante
  sí; en 300 paletas la tasa de giro por defecto no supera a la de ``+iluminante``.
"""

from __future__ import annotations

import numpy as np
import pytest

from oracle import hue_shift as hs
from oracle import l3
from synth import wada_gen as wg

CLI = l3.find_cli_optional()
HAS = hs.has_match_palette(CLI)
needs_cli = pytest.mark.skipif(not HAS, reason="sin 'ce match-palette' (make build)")

PINK = [("#222524", 0.394), ("#b49aa2", 0.227), ("#917a7e", 0.162), ("#d5b8c0", 0.134), ("#6b5a57", 0.083)]


def _pink_palette() -> dict:
    from oracle import reference as ref

    rgb = np.array([[int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)] for h, _ in PINK])
    return {"index": "pink", "family": "caso", "hex": [h for h, _ in PINK], "lab": ref.srgb8_to_lab_strict(rgb),
            "weights": [w for _, w in PINK], "tokens": " ".join(f"{h}:{w}" for h, w in PINK)}


def test_sampling_is_deterministic_and_in_gamut():
    a = hs.synthetic_candidates(np.random.default_rng(7), 0, 50)
    b = hs.synthetic_candidates(np.random.default_rng(7), 0, 50)
    assert [p["tokens"] for p in a] == [p["tokens"] for p in b]
    assert [p["family"] for p in a[:5]] == list(hs.FAMILIES)
    for p in a:
        assert 2 <= len(p["hex"]) <= 5
        assert abs(sum(p["weights"]) - 1.0) < 1e-9 and min(p["weights"]) > 0.03
        assert np.all(np.isfinite(p["lab"]))


def test_family_shapes():
    rng = np.random.default_rng(1)
    for _ in range(40):
        labs, w = hs.sample_palette(rng, "neutro_mas_color")
        c = hs.chroma(np.asarray(labs))
        assert np.all(c[:-1] < 3.0) and sum(w[:-1]) >= 0.35
        labs, w = hs.sample_palette(rng, "sombras_de_prenda")
        assert hs.chroma(np.asarray(labs))[-1] < 3.0 and 3 <= len(labs) <= 5
        labs, _ = hs.sample_palette(rng, "tierras")
        h = hs.hue_deg(np.asarray(labs))
        assert np.all((h >= 19.9) & (h <= 90.1))


def test_hue_diff_is_circular():
    assert hs.hue_diff_deg(350.0, 10.0) == pytest.approx(20.0)
    assert hs.hue_diff_deg(10.0, 190.0) == pytest.approx(180.0)


def test_pink_case_shift_criterion():
    d = wg.load_dictionary()
    labs = np.asarray(d["labs"], dtype=float)
    p = _pink_palette()
    blue = hs.palette_shift(p, {"id": 67, "colors": d["combos_by_id"][67]["colors"]}, labs)
    pink = hs.palette_shift(p, {"id": 337, "colors": d["combos_by_id"][337]["colors"]}, labs)
    assert blue["swatch"] == 1 and blue["shifted"] and blue["dh"] > 80.0
    assert pink["swatch"] == 1 and not pink["shifted"] and pink["dh"] < 10.0
    gray = {"lab": np.array([[50.0, 0.5, 0.5]]), "weights": [1.0]}
    assert hs.palette_shift(gray, {"id": 67, "colors": d["combos_by_id"][67]["colors"]}, labs) is None


@needs_cli
def test_pink_case_through_cli():
    default = hs.run_match_palette(CLI, [_pink_palette()], {})[0]
    illum = hs.run_match_palette(CLI, [_pink_palette()], {"illuminant_search": 1})[0]
    assert default["hits"][0]["id"] in (337, 27) and 67 not in [h["id"] for h in default["hits"]]
    assert illum["hits"][0]["id"] == 67


@needs_cli
def test_small_evaluation_orders_configs():
    detail = hs.evaluate(CLI, n=300, include_people=False, log=lambda *_: None)
    assert detail["n_palettes"] == 300 and detail["n_evaluated"] > 250
    d, i = detail["configs"]["defaults"], detail["configs"]["iluminante"]
    assert d["hue_shift_rate"] <= i["hue_shift_rate"]
    assert i["hue_shift_rate"] > 0.05  # la hipótesis de iluminante gira tonos a menudo
    again = hs.evaluate(CLI, n=300, include_people=False, log=lambda *_: None)
    assert again["configs"]["defaults"]["hue_shift_count"] == d["hue_shift_count"]
