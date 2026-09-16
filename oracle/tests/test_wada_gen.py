"""Valida al generador de la capa 3 (``synth.wada_gen``).

* Determinismo por semilla (imagen y metadatos byte a byte; variantes dev y holdout).
* Variante limpia: solo colores de la combinación, cada área entre 15 y 60 %.
* Distractor: 40 % del lienzo con un color a ΔE00 > 15 de la combinación; el resto intacto.
* Iluminantes: la matriz de Bradford usada reproduce ``engine/tests/data/golden_bradford.tsv``
  a 1e-9 y desplaza un gris hacia cálido (A) o frío (D75); las variantes 4-6 aplican el tinte
  residual tras el balance de blancos (25-35 % de la adaptación, ADR-009), no el completo.
* JPEG registra q en {10, 30}; textura y sombreado alteran L* dentro de una franja.
* ``generate_set``: mismos bytes en dos ejecuciones, manifest con ``generator_hash``,
  ``set_is_current``; el holdout exige semilla y nunca la escribe.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

from oracle import reference as ref
from synth import compose as sc
from synth import wada_gen as wg

REPO_ROOT = Path(__file__).resolve().parents[2]
BRADFORD_TSV = REPO_ROOT / "engine" / "tests" / "data" / "golden_bradford.tsv"
SAMPLE_COMBOS = [1, 12, 150, 300, 348]  # tamaños 2, 2, 3, 4, 4


def _combo_colors(combo_id: int) -> np.ndarray:
    d = wg.load_dictionary()
    return d["rgbs"][d["combos_by_id"][combo_id]["colors"]]


# ---- determinismo -------------------------------------------------------------------------


@pytest.mark.parametrize("combo_id", SAMPLE_COMBOS)
@pytest.mark.parametrize("v", list(wg.DEV_VARIANTS))
def test_variant_is_deterministic_and_well_formed(combo_id: int, v: int):
    a, ma = wg.variant(combo_id, v)
    b, mb = wg.variant(combo_id, v)
    assert a.shape == (wg.SIZE, wg.SIZE, 3) and a.dtype == np.uint8
    assert np.array_equal(a, b) and ma == mb
    assert ma["seed"] == combo_id * 1000 + v
    assert ma["variant"] == wg.VARIANT_NAMES[v]
    assert ma["degradation"] == wg.degradation_group(v, ma["params"])
    assert abs(sum(ma["proportions"]) - 1.0) < 1e-9
    assert all(wg.PROP_MIN - 1e-9 <= p <= wg.PROP_MAX + 1e-9 for p in ma["proportions"])


def test_seed_base_changes_bytes():
    a, _ = wg.variant(12, 0, seed_base=0)
    b, _ = wg.variant(12, 0, seed_base=1)
    assert not np.array_equal(a, b)
    c, _ = wg.variant(13, 0, seed_base=0)
    assert not np.array_equal(a, c)


@pytest.mark.parametrize("v", list(wg.HOLDOUT_VARIANTS))
def test_holdout_variant_deterministic_and_seedless(v: int):
    a, ma = wg.variant(150, v, seed_base=987654321)
    b, mb = wg.variant(150, v, seed_base=987654321)
    assert np.array_equal(a, b) and ma == mb
    assert "seed" not in ma and ma["degradation"] == "holdout"
    # Misma distribución que el dev: una variante 0..9 (a lo sumo una degradación).
    assert len(ma["degradations"]) <= 1 and set(ma["degradations"]) <= set(wg.DEGRADATION_ORDER)
    assert ma["holdout_variant"] in {wg.VARIANT_NAMES[d] for d in wg.DEV_VARIANTS}
    assert ma["holdout_degradation"] in wg.DEGRADATION_GROUPS
    c, _ = wg.variant(150, v, seed_base=987654322)
    assert not np.array_equal(a, c)


def test_holdout_matches_dev_distribution():
    """Con muchas imágenes de holdout aparecen todas las variantes dev y ninguna otra cosa."""
    seen: set[str] = set()
    for combo_id in range(1, 41):
        for v in wg.HOLDOUT_VARIANTS:
            _img, meta = wg.variant(combo_id, v, seed_base=2468, size=32)
            seen.add(meta["holdout_variant"])
            assert meta["holdout_degradation"] in wg.DEGRADATION_GROUPS
            if meta["holdout_variant"] == "jpeg":
                assert meta["params"]["jpeg"]["quality"] in wg.JPEG_Q_DEV
    assert seen == {wg.VARIANT_NAMES[d] for d in wg.DEV_VARIANTS}


# ---- variantes -----------------------------------------------------------------------------


@pytest.mark.parametrize("combo_id", SAMPLE_COMBOS)
def test_clean_variant_uses_only_combo_colors_with_bounded_areas(combo_id: int):
    img, meta = wg.variant(combo_id, 0)
    colors = _combo_colors(combo_id)
    flat = img.reshape(-1, 3)
    uniq = {tuple(int(v) for v in row) for row in np.unique(flat, axis=0)}
    assert uniq == {tuple(int(v) for v in c) for c in colors}
    assert abs(sum(meta["areas"]) - 1.0) < 1e-6
    for area in meta["areas"]:
        assert wg.PROP_MIN - 0.01 <= area <= wg.PROP_MAX + 0.01
    assert meta["layout"] == "stripes"


@pytest.mark.parametrize("combo_id", SAMPLE_COMBOS)
def test_shapes_variant_keeps_every_color_visible(combo_id: int):
    img, meta = wg.variant(combo_id, 1)
    assert meta["layout"] in wg.SHAPE_KINDS
    flat = img.reshape(-1, 3)
    uniq = {tuple(int(v) for v in row) for row in np.unique(flat, axis=0)}
    assert uniq == {tuple(int(v) for v in c) for c in _combo_colors(combo_id)}
    assert min(meta["areas"]) >= 0.05  # ninguna elipse tapa por completo a otra


@pytest.mark.parametrize("combo_id", SAMPLE_COMBOS)
def test_distractor_variant(combo_id: int):
    img, meta = wg.variant(combo_id, 9)
    p = meta["params"]["distractor"]
    assert abs(p["area"] - wg.DISTRACTOR_AREA) < 0.01
    assert p["min_de00"] > wg.DISTRACTOR_MIN_DE
    flat = img.reshape(-1, 3)
    uniq = {tuple(int(v) for v in row) for row in np.unique(flat, axis=0)}
    assert uniq == {tuple(int(v) for v in c) for c in _combo_colors(combo_id)} | {tuple(p["rgb"])}
    distractor_px = np.count_nonzero(np.all(flat == np.asarray(p["rgb"], dtype=np.uint8), axis=1)) / flat.shape[0]
    assert abs(distractor_px - p["area"]) < 1e-6


def test_bradford_matrices_match_engine_golden():
    rows = [line.split("\t") for line in BRADFORD_TSV.read_text().splitlines() if line and not line.startswith("#")]
    assert len(rows) == 80
    worst = 0.0
    for src, dst, *nums in rows:
        xyz = np.array([float(v) for v in nums[:3]])
        expected = np.array([float(v) for v in nums[3:6]])
        got = ref.bradford_matrix(src, dst) @ xyz
        worst = max(worst, float(np.abs(got - expected).max()))
    assert worst <= 1e-9, worst


def test_illuminant_shift_direction():
    gray = np.full((8, 8, 3), 128, dtype=np.uint8)
    warm, _ = wg.apply_illuminant(gray, "A")
    cool, _ = wg.apply_illuminant(gray, "D75")
    assert int(warm[0, 0, 0]) > int(warm[0, 0, 2])  # A: rojo > azul
    assert int(cool[0, 0, 2]) > int(cool[0, 0, 0])  # D75: azul > rojo
    for v, name in ((4, "A"), (5, "F2"), (6, "D75")):
        _img, meta = wg.variant(12, v)
        assert meta["params"]["illuminant"]["illuminant"] == name and meta["degradation"] == "illuminant"


def test_residual_illuminant_is_partial_adaptation():
    lo, hi = wg.ILLUMINANT_RESIDUAL_RANGE
    assert (lo, hi) == (0.25, 0.35)
    for name in wg.ILLUMINANTS:
        full = ref.bradford_matrix("D65", name)
        assert np.allclose(wg.residual_illuminant_matrix(name, 1.0), full, atol=0, rtol=0)
        assert np.array_equal(wg.residual_illuminant_matrix(name, 0.0), np.eye(3))
        half = wg.residual_illuminant_matrix(name, 0.3)
        assert np.allclose(half, 0.7 * np.eye(3) + 0.3 * full, atol=1e-15)
    with pytest.raises(ValueError):
        wg.residual_illuminant_matrix("A", 1.2)
    # Un gris medio: el tinte residual de A es cálido pero mucho más débil que el completo.
    gray = np.full((4, 4, 3), 128, dtype=np.uint8)
    full_img, full_p = wg.apply_illuminant(gray, "A")
    res_img, res_p = wg.apply_illuminant(gray, "A", 0.3)
    assert full_p == {"illuminant": "A"}
    assert res_p == {"illuminant": "A", "strength": 0.3, "model": "residual_after_awb"}
    gray_lab = ref.srgb8_to_lab_strict(gray[0, 0])
    de_full = float(ref.de2000(gray_lab, ref.srgb8_to_lab_strict(full_img[0, 0])))
    de_res = float(ref.de2000(gray_lab, ref.srgb8_to_lab_strict(res_img[0, 0])))
    assert int(res_img[0, 0, 0]) > int(res_img[0, 0, 2])
    assert 0.1 * de_full < de_res < 0.5 * de_full, (de_res, de_full)
    # Variantes 4-6: intensidad sorteada por imagen dentro del intervalo y registrada.
    strengths = set()
    for combo_id in range(1, 31):
        for v, name in ((4, "A"), (5, "F2"), (6, "D75")):
            _img, meta = wg.variant(combo_id, v)
            p = meta["params"]["illuminant"]
            assert p["illuminant"] == name and p["model"] == "residual_after_awb"
            assert lo <= p["strength"] <= hi
            strengths.add(p["strength"])
    assert len(strengths) > 80


def test_golden_fixtures_without_illuminant_keep_their_bytes():
    # La intensidad del tinte se sortea después de la geometría y solo en las variantes 4-6: el
    # resto de fixtures de harness/golden (128 px) conserva exactamente sus bytes (sha256).
    golden = json.loads((REPO_ROOT / "harness" / "golden" / "match_50.json").read_text(encoding="utf-8"))
    import hashlib

    checked = 0
    for e in golden["entries"]:
        if int(e["v"]) in (4, 5, 6):
            continue
        img, _meta = wg.variant(int(e["combo_id"]), int(e["v"]), size=128)
        h, w, _ = img.shape
        ppm = f"P6\n{w} {h}\n255\n".encode("ascii") + img.tobytes()
        assert hashlib.sha256(ppm).hexdigest() == e["sha256"], e["file"]
        checked += 1
    assert checked >= 30


def test_jpeg_exposure_texture_shading_params():
    qs = set()
    for combo_id in range(1, 41):
        _img, meta = wg.variant(combo_id, 7)
        qs.add(meta["params"]["jpeg"]["quality"])
        assert meta["degradation"] == f"jpeg_q{meta['params']['jpeg']['quality']}"
    assert qs == set(wg.JPEG_Q_DEV)
    _img, meta = wg.variant(12, 8)
    assert meta["params"]["exposure"]["ev"] in (-1.0, 1.0) and 0.7 <= meta["params"]["exposure"]["saturation"] <= 1.3
    # Textura y sombreado: la franja más grande deja de ser plana pero conserva su color medio.
    for v in (2, 3):
        clean, cmeta = wg.variant(12, 0)
        img, meta = wg.variant(12, v)
        lab = ref.srgb8_to_lab_strict(img.reshape(-1, 3))
        assert float(np.std(lab[:, 0])) > 0.0
        assert meta["degradation"] in ("texture", "shading")


# ---- generate_set ----------------------------------------------------------------------------


def test_generate_set_is_byte_deterministic(tmp_path: Path):
    combos = [1, 150, 300]
    m1 = wg.generate_set(tmp_path / "a", wg.DEV_VARIANTS, combos)
    m2 = wg.generate_set(tmp_path / "b", wg.DEV_VARIANTS, combos)
    assert m1.read_bytes() == m2.read_bytes()
    meta, rows = wg.read_manifest(m1)
    assert meta["generator_hash"] == wg.generator_hash() and meta["dict_version"] == wg.dict_version()
    assert meta["seed_base"] == 0 and meta["holdout"] is False and meta["combos"] == combos
    assert len(rows) == len(combos) * len(wg.DEV_VARIANTS)
    for r in rows:
        assert (tmp_path / "a" / r["file"]).read_bytes() == (tmp_path / "b" / r["file"]).read_bytes()
        assert r["seed"] == r["combo_id"] * 1000 + r["v"]
        img = sc.read_ppm(tmp_path / "a" / r["file"])
        assert img.shape == (wg.SIZE, wg.SIZE, 3)
    assert wg.set_is_current(tmp_path / "a", wg.DEV_VARIANTS, combos)
    assert not wg.set_is_current(tmp_path / "a", wg.DEV_VARIANTS, [1, 150])
    (tmp_path / "a" / rows[0]["file"]).unlink()
    assert not wg.set_is_current(tmp_path / "a", wg.DEV_VARIANTS, combos)


def test_generate_set_holdout_requires_seed_and_never_writes_it(tmp_path: Path):
    with pytest.raises(ValueError):
        wg.generate_set(tmp_path / "h", wg.HOLDOUT_VARIANTS, [1, 2], seed_base=None)
    secret = 987654321
    manifest = wg.generate_set(tmp_path / "h", wg.HOLDOUT_VARIANTS, [1, 2], seed_base=secret)
    text = manifest.read_text(encoding="utf-8")
    assert str(secret) not in text
    meta, rows = wg.read_manifest(manifest)
    assert meta["holdout"] is True and "seed_base" not in meta
    assert all("seed" not in r for r in rows) and len(rows) == 4
    assert all(r["degradation"] == "holdout" for r in rows)


def test_holdout_seed_base_env(monkeypatch):
    monkeypatch.delenv(wg.HOLDOUT_SEED_ENV, raising=False)
    assert wg.holdout_seed_base() is None
    monkeypatch.setenv(wg.HOLDOUT_SEED_ENV, " 42 ")
    assert wg.holdout_seed_base() == 42
    monkeypatch.setenv(wg.HOLDOUT_SEED_ENV, "abc")
    with pytest.raises(ValueError):
        wg.holdout_seed_base()


def test_sample_proportions_bounds():
    rng = np.random.default_rng(3)
    for n in (2, 3, 4, 6):
        p = wg.sample_proportions(rng, n)
        assert abs(p.sum() - 1.0) < 1e-12 and len(p) == n
        assert np.all(p >= wg.PROP_MIN - 1e-9) and np.all(p <= wg.PROP_MAX + 1e-9)
    # 7 colores (reserva del Vol. 2): 7 x 15 % > 100 %, así que cae a partes iguales.
    assert np.allclose(wg.sample_proportions(rng, 7), 1.0 / 7.0)
