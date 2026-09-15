"""Valida al generador de la capa 2 (``synth.compose``) y a su oráculo de referencia.

* Determinismo por semilla (imagen y verdad byte a byte).
* Verdad coherente: áreas reales = fracción de píxeles, suma 1, a menos de 0,01 de las
  nominales del layout; colores con 15 <= L <= 90 y ΔE00 mutuo > 15.
* Las cinco variantes geométricas aparecen y las tres no lineales no coinciden con el
  peso al centro (justificación de comparar pesos solo en modo uniforme).
* Transformaciones: barajado (mismo multiconjunto), escala (2x luego 0,5x = identidad),
  espejo y rotación (involuciones), ruido acotado, E/S PPM sin pérdida.
* ``palette_reference`` (KMeans k=3) recupera la verdad con ΔE00 < 2 y área ± 3 puntos
  en 50 semillas limpias y en 10 con ruido sigma = 2; es invariante al barajado.
"""

from __future__ import annotations

import numpy as np
import pytest
from scipy.optimize import linear_sum_assignment

from oracle import reference as ref
from synth import compose as sc

SEEDS_50 = list(range(1, 51))


def _layout_for(seed: int) -> str:
    return list(sc.LAYOUTS)[(seed - 1) % 2]


def _match(truth, palette):
    """Asignación óptima verdad <-> paleta por ΔE00; devuelve (ΔE por color, pesos emparejados)."""
    t_lab = np.array([t["lab"] for t in truth])
    p_lab = np.array([p["lab"] for p in palette])
    cost = np.array([[float(ref.de2000(a, b)) for b in p_lab] for a in t_lab])
    rows, cols = linear_sum_assignment(cost)
    des = [cost[i, j] for i, j in zip(rows, cols)]
    weights = [palette[j]["weight"] for j in cols]
    return des, weights


# ---- compose ------------------------------------------------------------------------------


def test_compose_is_deterministic():
    a_img, a_truth = sc.compose(11, layout="40/35/25")
    b_img, b_truth = sc.compose(11, layout="40/35/25")
    assert np.array_equal(a_img, b_img)
    assert a_truth == b_truth
    c_img, _ = sc.compose(12, layout="40/35/25")
    assert not np.array_equal(a_img, c_img)


def test_compose_shape_dtype_and_size_order():
    img, truth = sc.compose(1, size=(120, 80))
    assert img.shape == (80, 120, 3) and img.dtype == np.uint8
    assert len(truth) == 3
    assert [t["area"] for t in truth] == sorted((t["area"] for t in truth), reverse=True)


@pytest.mark.parametrize("seed", SEEDS_50)
def test_truth_matches_pixels_and_layout(seed: int):
    layout = _layout_for(seed)
    img, truth = sc.compose(seed, layout=layout)
    nominal = sc.parse_layout(layout)
    total = img.shape[0] * img.shape[1]
    assert abs(sum(t["area"] for t in truth) - 1.0) < 1e-12
    for t, f in zip(truth, nominal):
        rgb = np.array(t["rgb"], dtype=np.uint8)
        count = int(np.all(img == rgb, axis=2).sum())
        assert count / total == pytest.approx(t["area"], abs=1e-12)
        assert abs(t["area"] - f) < 0.01, (seed, layout, t["area"], f)
        np.testing.assert_allclose(t["lab"], ref.srgb8_to_lab_strict(t["rgb"]), atol=1e-12)
        assert sc.L_MIN <= t["lab"][0] <= sc.L_MAX
    labs = [np.array(t["lab"]) for t in truth]
    for i in range(3):
        for j in range(i + 1, 3):
            assert float(ref.de2000(labs[i], labs[j])) > sc.DEFAULT_MIN_DE


def test_all_variants_appear_and_are_rectangular():
    seen = {}
    for seed in range(1, 11):
        labels, variant = sc.compose_labels(seed)
        seen.setdefault(variant, seed)
        assert set(np.unique(labels)) == {0, 1, 2}
        # Cada etiqueta es unión de rectángulos: en cada fila hay a lo sumo 4 cambios de
        # etiqueta (A|B|C|B|A en la variante anidada) y en cada columna también.
        assert (np.diff(labels, axis=1) != 0).sum(axis=1).max() <= 4, variant
        assert (np.diff(labels, axis=0) != 0).sum(axis=0).max() <= 4, variant
    assert set(seen) == set(sc.VARIANTS)


def test_center_weight_differs_from_area_in_nonlinear_variants():
    """Con peso gaussiano al centro (sigma = 0,35·min(w,h)) el peso no es el área."""
    h = w = 200
    yy, xx = np.mgrid[0:h, 0:w]
    sigma = 0.35 * min(w, h)
    g = np.exp(-(((xx - (w - 1) / 2) ** 2 + (yy - (h - 1) / 2) ** 2) / (2 * sigma * sigma)))
    worst = 0.0
    for seed in range(1, 31):
        labels, variant = sc.compose_labels(seed)
        if variant in ("stripes_h", "stripes_v"):
            continue
        areas = np.bincount(labels.ravel(), minlength=3) / labels.size
        weighted = np.array([g[labels == k].sum() for k in range(3)])
        weighted /= weighted.sum()
        worst = max(worst, float(np.abs(weighted - areas).max()))
    assert worst > 0.05, "las variantes anidada/esquinas/L deben separar peso al centro y área"


def test_parse_layout_validation():
    assert sc.parse_layout("50/30/20") == (0.5, 0.3, 0.2)
    assert sc.parse_layout("60/25/15") == (0.6, 0.25, 0.15)
    with pytest.raises(ValueError):
        sc.parse_layout("50/50")
    with pytest.raises(ValueError):
        sc.parse_layout("20/30/50")
    with pytest.raises(ValueError):
        sc.compose(1, variant="hexagons")


# ---- transformaciones ----------------------------------------------------------------------


def test_transforms_properties():
    img, _ = sc.compose(3)
    shuffled = sc.shuffle_pixels(img, seed=99)
    assert shuffled.shape == img.shape and not np.array_equal(shuffled, img)
    assert np.array_equal(np.sort(img.reshape(-1, 3), axis=0), np.sort(shuffled.reshape(-1, 3), axis=0))
    assert np.array_equal(sc.shuffle_pixels(img, 99), shuffled)

    up = sc.scale(img, 2.0)
    assert up.shape == (400, 400, 3)
    assert np.array_equal(up[::2, ::2], img)
    assert np.array_equal(sc.scale(up, 0.5), img)
    down = sc.scale(img, 0.5)
    assert down.shape == (100, 100, 3)
    with pytest.raises(ValueError):
        sc.scale(img, 1.5)

    assert np.array_equal(sc.mirror(sc.mirror(img)), img)
    assert np.array_equal(sc.rotate180(sc.rotate180(img)), img)
    assert np.array_equal(sc.mirror(img)[:, 0], img[:, -1])
    assert np.array_equal(sc.rotate180(img)[0, 0], img[-1, -1])

    noisy = sc.add_noise(img, sigma=2.0, seed=1)
    assert noisy.dtype == np.uint8 and noisy.shape == img.shape
    diff = np.abs(noisy.astype(int) - img.astype(int))
    assert 0 < diff.mean() < 3 and diff.max() <= 12
    assert np.array_equal(sc.add_noise(img, 2.0, 1), noisy)


def test_scale_box_average_rounds_half_up():
    block = np.array([[[0, 0, 0], [1, 1, 1]], [[1, 1, 1], [0, 0, 0]]], dtype=np.uint8)  # media 0,5
    assert tuple(sc.scale(block, 0.5)[0, 0]) == (1, 1, 1)
    block2 = np.array([[[0, 0, 0], [0, 0, 0]], [[0, 0, 0], [1, 1, 1]]], dtype=np.uint8)  # media 0,25
    assert tuple(sc.scale(block2, 0.5)[0, 0]) == (0, 0, 0)


def test_ppm_roundtrip(tmp_path):
    img, _ = sc.compose(7, size=(33, 17))
    path = sc.write_ppm(img, tmp_path / "x.ppm")
    raw = path.read_bytes()
    assert raw.startswith(b"P6\n33 17\n255\n") and len(raw) == len(b"P6\n33 17\n255\n") + 33 * 17 * 3
    assert np.array_equal(sc.read_ppm(path), img)
    mask = (np.arange(33 * 17) % 256).astype(np.uint8).reshape(17, 33)
    mpath = sc.write_pgm(mask, tmp_path / "m.pgm")
    assert np.array_equal(sc.read_pnm(mpath), mask)
    with pytest.raises(ValueError):
        sc.read_ppm(mpath)
    (tmp_path / "trunc.ppm").write_bytes(raw[:-10])
    with pytest.raises(ValueError):
        sc.read_ppm(tmp_path / "trunc.ppm")


# ---- oráculo de referencia --------------------------------------------------------------------


@pytest.mark.parametrize("seed", SEEDS_50)
def test_palette_reference_recovers_truth(seed: int):
    img, truth = sc.compose(seed, layout=_layout_for(seed))
    palette = sc.palette_reference(img)
    assert len(palette) == 3
    assert abs(sum(p["weight"] for p in palette) - 1.0) < 1e-12
    des, weights = _match(truth, palette)
    assert max(des) < 2.0, (seed, des)
    assert max(abs(w - t["area"]) for w, t in zip(weights, truth)) <= 0.03
    for p in palette:
        assert all(0 <= v <= 255 for v in p["rgb"])


@pytest.mark.parametrize("seed", list(range(1, 11)))
def test_palette_reference_with_noise(seed: int):
    img, truth = sc.compose(seed, layout=_layout_for(seed))
    palette = sc.palette_reference(sc.add_noise(img, 2.0, seed))
    des, weights = _match(truth, palette)
    assert max(des) < 2.0, (seed, des)
    assert max(abs(w - t["area"]) for w, t in zip(weights, truth)) <= 0.03


def test_palette_reference_is_order_invariant():
    """Mismo resultado tras barajar (colores únicos + conteos); los centros de sklearn pueden
    diferir en algún ulp entre ejecuciones por la reducción paralela, de ahí la tolerancia."""
    img, _ = sc.compose(5)
    assert sc.palette_reference(img) == sc.palette_reference(sc.shuffle_pixels(img, 3))
    noisy = sc.add_noise(img, 2.0, 5)
    a, b = sc.palette_reference(noisy), sc.palette_reference(sc.shuffle_pixels(noisy, 4))
    assert [x["weight"] for x in a] == [x["weight"] for x in b]
    assert [x["rgb"] for x in a] == [x["rgb"] for x in b]
    np.testing.assert_allclose([x["lab"] for x in a], [x["lab"] for x in b], rtol=0, atol=1e-9)


def test_lab_to_srgb8_roundtrip_and_clamp():
    rgb = np.array([[12, 200, 77], [0, 0, 0], [255, 255, 255], [250, 3, 128]])
    back = sc.lab_to_srgb8(ref.srgb8_to_lab_strict(rgb))
    assert np.array_equal(back, rgb)
    assert list(sc.lab_to_srgb8([120.0, 0.0, 0.0])) == [255, 255, 255]  # fuera de gamut: clamp
    assert list(sc.lab_to_srgb8([-5.0, 0.0, 0.0])) == [0, 0, 0]
    assert list(sc.lab_to_srgb8([50.0, 200.0, -200.0])) == [174, 0, 255]  # canales saturados
