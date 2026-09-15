"""``oracle/tools/layers_report.py`` (``make layers-report``) con 2 imágenes sintéticas, el doble
``l4.fake_visionmask`` (sin Vision) y el CLI ``ce`` real con ``--debug-dir``: HTML autocontenido
(solo PNG en base64, sin red ni JavaScript), una sección por foto con una fila por variante y
todas las capas; modo sin visionmask (solo ``none``) y errores de uso."""

from __future__ import annotations

import base64
import io
import json
import re
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from l4 import fake_visionmask as fvm
from oracle import l3
from synth import wada_gen as wg
from tools import layers_report as lr

CLI = l3.find_cli_optional()
CLI_DEBUG = lr.has_debug_dir(CLI)
needs_cli = pytest.mark.skipif(not CLI_DEBUG, reason=f"ce sin --debug-dir: {CLI}")
VARIANTS = ["none", "largest", "largest-clothing", "largest-clothing-skin"]


@pytest.fixture
def photos(tmp_path: Path) -> list[Path]:
    d = tmp_path / "fotos con espacios"
    d.mkdir()
    a, _ = wg.variant(12, 0)
    b, _ = wg.variant(300, 3)
    pa = d / "persona.png"
    Image.fromarray(a).save(pa)
    pb = d / "nopeople.jpg"
    Image.fromarray(np.asarray(Image.fromarray(b).resize((200, 256)))).save(pb, quality=95)
    return [pa, pb]


def _imgs(page: str) -> list[str]:
    return re.findall(r'<img src="([^"]+)"', page)


@needs_cli
def test_report_with_fake_visionmask(photos: list[Path], tmp_path: Path, capsys):
    vm = fvm.write_executable(tmp_path / "visionmask")
    out = tmp_path / "capas"
    code = lr.main([str(photos[0].parent / "*.png"), str(photos[1]), "--out", str(out), "--ce", str(CLI), "--visionmask", str(vm)])
    assert code == 0
    page = (out / "index.html").read_text(encoding="utf-8")
    assert page.startswith("<title>Capas del color")
    # Autocontenido: solo PNG embebidos, sin scripts ni recursos de red.
    srcs = _imgs(page)
    assert srcs and all(s.startswith("data:image/png;base64,") for s in srcs)
    assert "<script" not in page and not re.search(r'(src|href)="https?://', page)
    for s in srcs[:40]:
        with Image.open(io.BytesIO(base64.b64decode(s.split(",", 1)[1]))) as im:
            assert max(im.size) <= 256
    assert (out / "index.html").stat().st_size < 3_000_000
    # Dos fotos, cuatro variantes cada una, y todas las columnas.
    assert page.count('<section class="card" id="p') == 2
    assert page.count('<td class="variant">') == 8
    for header in ("Foto", "Raster del motor", "Reducida (motor)", "Personas (Vision)", "Pose y región de ropa", "Piel quitada",
                   "Máscara final", "Peso por píxel", "Clusters (Lloyd)", "Label map", "Paleta", "Top-3 y por qué"):
        assert f"<th>{header}</th>" in page
    assert "magenta = piel quitada" in page and "Gana por" in page and "conservado" in page
    assert page.count('class="official"') == 2 and "Resumen" in page
    assert "sin máscara: se analizó la foto completa" in page  # foto sin personas
    data = json.loads((out / "layers.json").read_text(encoding="utf-8"))
    assert data["variants"] == VARIANTS and len(data["photos"]) == 2
    p0 = data["photos"][0]["variants"]
    assert p0["largest-clothing-skin"]["steps"] == ["poseRegions", "skinExcluded"] and p0["largest-clothing-skin"]["mask"]
    assert p0["none"]["mask"] is None and len(p0["none"]["top"]) == 3
    assert data["photos"][1]["variants"]["largest"]["mask"] is None
    # Capas reproducibles: los debug-dir de ce existen con sus ficheros.
    dbg = Path(p0["largest-clothing-skin"]["debug_dir"])
    for name in ("reduced.ppm", "weights.pgm", "labels.pgm", "clusters.ppm", "swatch_0.pgm", "mask.pgm", "debug.json"):
        assert (dbg / name).is_file()
    assert "--debug-dir" in page and "fotos con espacios" in page
    assert "layers-report:" in capsys.readouterr().out


@needs_cli
def test_report_without_visionmask(photos: list[Path], tmp_path: Path):
    out = tmp_path / "sin-vm"
    assert lr.main([str(p) for p in photos] + ["--out", str(out), "--ce", str(CLI), "--no-visionmask"]) == 0
    page = (out / "index.html").read_text(encoding="utf-8")
    assert page.count('<td class="variant">') == 8
    assert "sin visionmask (--no-visionmask)" in page and page.count("Gana por") == 2
    data = json.loads((out / "layers.json").read_text(encoding="utf-8"))
    assert all(ph["variants"]["largest"]["skipped"] for ph in data["photos"])
    assert all(len(ph["variants"]["none"]["top"]) == 3 for ph in data["photos"])


def test_usage_errors(tmp_path: Path, photos: list[Path], monkeypatch):
    assert lr.main([str(tmp_path / "nada" / "*.png"), "--out", str(tmp_path / "o")]) == 2
    assert lr.main([str(photos[0]), "--out", str(tmp_path / "o"), "--ce", str(tmp_path / "no-ce"), "--no-visionmask"]) == 2
    assert not (tmp_path / "o" / "index.html").exists()
    # ~ y globs: se expanden aunque el shell no lo haga.
    monkeypatch.setenv("HOME", str(photos[0].parent.parent))
    found = lr.collect_images(["~/fotos con espacios/*.png", str(photos[0].parent)])
    assert found[0].name == "persona.png" and {p.name for p in found} == {"persona.png", "nopeople.jpg"}


def test_pose_and_overlays(tmp_path: Path):
    pose = tmp_path / "pose.txt"
    pose.write_text("# cabecera\n" + "".join(f"{10 + i} {20 + i} {0.9 if i % 2 else 0.1}\n" for i in range(15)), encoding="utf-8")
    pts = lr.read_pose(pose)
    assert pts is not None and len(pts) == 15 and pts[0] == (10.0, 20.0, 0.1)
    img = Image.new("RGB", (64, 64))
    lr.draw_pose(img, pts, 1.0)
    assert img.getbbox() is not None
    assert lr.thumb_size(1024, 682, 256) == (256, 170) and lr.thumb_size(100, 50, 256) == (100, 50)
