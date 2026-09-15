"""Runner mínimo de la capa 4 (``l4.run``) con un set dorado ficticio en un directorio temporal:
6 imágenes sintéticas (PNG y JPEG) de ``wada_gen`` con manifest de 3 jueces, más rechazos
(HEIC simulado, imagen > 256 px, sha256 incorrecto). Sin ``COLORSAPP_GOLDEN_DIR`` la capa es
``skipped``. El match real solo se ejecuta si el CLI tiene ``ce match``."""

from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from l4 import run as l4
from oracle import l3
from synth import wada_gen as wg

CLI = l3.find_cli_optional()
CLI_HAS_MATCH = l3.has_match(CLI)
TAGS = ["negro", "denim", "gris", "interior", "fondo-sucio", "blanco"]


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write(path: Path, img: np.ndarray, fmt: str) -> None:
    Image.fromarray(img).save(path, format=fmt, **({"quality": 95} if fmt == "JPEG" else {}))


@pytest.fixture
def golden(tmp_path: Path) -> tuple[Path, list[dict]]:
    combos = [1, 12, 150, 300, 348, 77]
    entries = []
    for i, combo in enumerate(combos):
        img, _ = wg.variant(combo, 0)
        fmt = "JPEG" if i % 3 == 2 else "PNG"
        name = f"photo{i}.{'jpg' if fmt == 'JPEG' else 'png'}"
        _write(tmp_path / name, img, fmt)
        labels = {"ana": combo, "bea": combo, "carl": None if i == 0 else combo}
        if i == 5:  # sin consenso: tres votos distintos
            labels = {"ana": combo, "bea": 5, "carl": None}
        entries.append({"file": name, "sha256": _sha(tmp_path / name), "tags": [TAGS[i], "interior"] if i < 5 else [TAGS[5]], "labels": labels})
    (tmp_path / "manifest.json").write_text(json.dumps({"photos": entries}, indent=1), encoding="utf-8")
    return tmp_path, entries


def test_consensus_rules():
    assert l4.consensus({"a": 3, "b": 3, "c": 7}) == 3
    assert l4.consensus({"a": 3, "b": 5, "c": 7}) is None
    assert l4.consensus({"a": None, "b": None, "c": 7}) is None
    assert l4.consensus({"a": 9}) == 9
    assert l4.consensus({"a": 9, "b": 4}) is None
    assert l4.consensus({}) is None


def test_fleiss_kappa():
    perfect = [{"a": 1, "b": 1, "c": 1}, {"a": 2, "b": 2, "c": 2}, {"a": 3, "b": 3, "c": 3}]
    assert l4.fleiss_kappa(perfect) == pytest.approx(1.0)
    # Ejemplo clásico (Wikipedia, 10 sujetos x 14 jueces x 5 categorías): κ = 0.210
    table = [[0, 0, 0, 0, 14], [0, 2, 6, 4, 2], [0, 0, 3, 5, 6], [0, 3, 9, 2, 0], [2, 2, 8, 1, 1],
             [7, 7, 0, 0, 0], [3, 2, 6, 3, 0], [2, 5, 3, 2, 2], [6, 5, 2, 1, 0], [0, 2, 2, 3, 7]]
    rows = []
    for counts in table:
        r = {}
        k = 0
        for cat, n in enumerate(counts):
            for _ in range(n):
                r[f"j{k}"] = cat + 1
                k += 1
        rows.append(r)
    assert l4.fleiss_kappa(rows) == pytest.approx(0.2099, abs=1e-3)
    assert l4.fleiss_kappa([{"a": 1, "b": 1}, {"a": 1}]) is None  # jueces desiguales
    assert l4.fleiss_kappa([{"a": 1}, {"a": 2}]) is None  # un solo juez


def test_skipped_without_env(monkeypatch):
    monkeypatch.delenv(l4.GOLDEN_DIR_ENV, raising=False)
    status, checks, detail = l4.run_layer4(CLI, l3.load_thresholds(), None)
    assert status == "skipped" and checks[0].status == "skipped" and l4.GOLDEN_DIR_ENV in detail["reason"]


def test_manifest_and_photo_verification(golden, tmp_path: Path):
    gdir, entries = golden
    loaded = l4.load_manifest(gdir)
    assert len(loaded) == 6
    for e in loaded:
        problems, info = l4.verify_photo(gdir, e)
        assert problems == [] and info["format"] in ("PNG", "JPEG") and info["width"] == 256
    # Rechazos: sha256 incorrecto, lado > 256, HEIC simulado (cabecera ftyp), formato no admitido.
    bad = dict(entries[0], sha256="0" * 64)
    assert any("sha256" in p for p in l4.verify_photo(gdir, bad)[0])
    big = np.zeros((300, 100, 3), dtype=np.uint8)
    _write(gdir / "big.png", big, "PNG")
    assert any("supera 256" in p for p in l4.verify_photo(gdir, {"file": "big.png", "sha256": _sha(gdir / "big.png")})[0])
    (gdir / "fake.heic").write_bytes(b"\x00\x00\x00\x18ftypheic" + b"\x00" * 32)
    assert any("HEIC" in p for p in l4.verify_photo(gdir, {"file": "fake.heic", "sha256": _sha(gdir / "fake.heic")})[0])
    buf = io.BytesIO()
    Image.fromarray(np.zeros((8, 8, 3), dtype=np.uint8)).save(buf, format="BMP")
    (gdir / "x.bmp").write_bytes(buf.getvalue())
    assert any("no admitido" in p for p in l4.verify_photo(gdir, {"file": "x.bmp", "sha256": _sha(gdir / "x.bmp")})[0])
    (gdir / "manifest.json").write_text(json.dumps([{"file": "a", "sha256": "xx", "tags": [], "labels": {}}]))
    with pytest.raises(l4.ManifestError):
        l4.load_manifest(gdir)


@pytest.mark.skipif(not CLI_HAS_MATCH, reason=f"sin 'ce match': {l3.not_implemented_reason(CLI)}")
def test_run_layer4_end_to_end(golden, tmp_path: Path, monkeypatch):
    gdir, _entries = golden
    monkeypatch.setenv(l4.GOLDEN_DIR_ENV, str(gdir))
    status, checks, detail = l4.run_layer4(CLI, l3.load_thresholds(), tmp_path / "out", log=lambda *_: None)
    by_name = {c.name: c for c in checks}
    assert by_name["manifest.json del set dorado"].status == "pass"
    assert by_name["fotos: sha256, PNG/JPEG sRGB, lado <= 256 px, sin HEIC"].status == "pass"
    assert [c for c in checks if "golden_min_photos" in c.name][0].status == "fail"  # 6 < 50
    assert status == "fail"
    assert detail["n_scored"] == 5 and detail["fleiss_kappa"] is not None
    agg = detail["aggregate"]
    assert agg["n"] == 5 and agg["recall_at_1"] == 1.0  # variantes limpias
    assert set(detail["by_tag"]) >= set(TAGS) and detail["by_tag"]["interior"]["n"] == 5 and detail["by_tag"]["blanco"]["n"] == 0
    assert (tmp_path / "out" / "l4_detail.json").is_file()
    assert [c.status for c in checks if c.name.startswith("agregado: recall@3")] == ["pass"]
