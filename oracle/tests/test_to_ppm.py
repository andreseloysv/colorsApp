"""Tests de ``oracle/tools/to_ppm.py`` ejecutándolo como script (subprocess, mismo intérprete)."""

from __future__ import annotations

import io
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image, ImageCms

from synth import compose as sc

REPO_ROOT = Path(__file__).resolve().parents[2]
TO_PPM = REPO_ROOT / "oracle" / "tools" / "to_ppm.py"


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(TO_PPM), *args], capture_output=True, text=True, check=False)


@pytest.fixture
def img() -> np.ndarray:
    image, _ = sc.compose(4, size=(40, 24))
    return image


def test_png_without_icc_is_exact(tmp_path, img):
    src = tmp_path / "in.png"
    Image.fromarray(img).save(src)
    out = tmp_path / "out.ppm"
    proc = run(str(src), str(out))
    assert proc.returncode == 0, proc.stderr
    assert "se asume sRGB" in proc.stderr
    assert np.array_equal(sc.read_ppm(out), img)


def test_embedded_srgb_profile_is_not_converted(tmp_path, img):
    src = tmp_path / "srgb.png"
    icc = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    Image.fromarray(img).save(src, icc_profile=icc)
    out = tmp_path / "out.ppm"
    proc = run(str(src), str(out))
    assert proc.returncode == 0, proc.stderr
    assert "ya es sRGB" in proc.stderr
    assert np.array_equal(sc.read_ppm(out), img)


def test_non_srgb_profile_goes_through_imagecms(tmp_path):
    """Un TIFF en modo LAB con perfil Lab embebido debe convertirse a sRGB (ruta ImageCms)."""
    lab_img = Image.new("LAB", (6, 4), (128, 160, 140))
    icc = ImageCms.ImageCmsProfile(ImageCms.createProfile("LAB")).tobytes()
    src = tmp_path / "lab.tif"
    lab_img.save(src, icc_profile=icc)
    out = tmp_path / "out.ppm"
    proc = run(str(src), str(out))
    assert proc.returncode == 0, proc.stderr
    assert "-> sRGB, intent perceptual" in proc.stderr
    got = sc.read_ppm(out)
    assert got.shape == (4, 6, 3)
    expected = np.asarray(ImageCms.profileToProfile(
        lab_img, ImageCms.createProfile("LAB"), ImageCms.createProfile("sRGB"),
        renderingIntent=ImageCms.Intent.PERCEPTUAL, outputMode="RGB"))
    assert np.array_equal(got, expected)
    assert got[0, 0, 0] > got[0, 0, 1]  # a* > 0: más rojo que verde


def test_exif_orientation_is_applied(tmp_path):
    base = np.zeros((10, 20, 3), dtype=np.uint8)
    base[:, :10] = (255, 0, 0)  # mitad izquierda roja
    exif = Image.Exif()
    exif[0x0112] = 6  # rotar 90° en sentido horario al mostrar
    src = tmp_path / "o6.png"
    Image.fromarray(base).save(src, exif=exif)
    out = tmp_path / "out.ppm"
    proc = run(str(src), str(out))
    assert proc.returncode == 0, proc.stderr
    got = sc.read_ppm(out)
    assert got.shape == (20, 10, 3)
    assert tuple(got[0, 0]) == (255, 0, 0) and tuple(got[-1, -1]) == (0, 0, 0)


def test_max_side_reduces_by_integer_box_factor(tmp_path, img):
    src = tmp_path / "in.png"
    Image.fromarray(img).save(src)
    out = tmp_path / "out.ppm"
    proc = run(str(src), str(out), "--max-side", "20")
    assert proc.returncode == 0, proc.stderr
    got = sc.read_ppm(out)
    assert got.shape == (12, 20, 3)
    assert "reducción x2" in proc.stderr
    assert np.abs(got.astype(int) - sc.scale(img, 0.5).astype(int)).max() <= 1
    proc = run(str(src), str(out), "--max-side", "100")
    assert proc.returncode == 0 and np.array_equal(sc.read_ppm(out), img)


def test_mask_from_alpha_and_without_alpha(tmp_path, img):
    rgba = np.dstack([img, np.full(img.shape[:2], 7, np.uint8)])
    rgba[:5, :, 3] = 250
    src = tmp_path / "a.png"
    Image.fromarray(rgba, "RGBA").save(src)
    out, mask = tmp_path / "out.ppm", tmp_path / "mask.pgm"
    proc = run(str(src), str(out), "--mask", str(mask))
    assert proc.returncode == 0, proc.stderr
    assert np.array_equal(sc.read_ppm(out), img)
    got = sc.read_pnm(mask)
    assert got.shape == img.shape[:2] and int(got[0, 0]) == 250 and int(got[-1, -1]) == 7

    src2 = tmp_path / "noalpha.png"
    Image.fromarray(img).save(src2)
    proc = run(str(src2), str(out), "--mask", str(mask))
    assert proc.returncode == 0 and "sin canal alfa" in proc.stderr
    assert int(sc.read_pnm(mask).min()) == 255


def test_heic_is_rejected_with_exit_2(tmp_path):
    fake = tmp_path / "foto.heic"
    fake.write_bytes(b"\x00\x00\x00\x18ftypheic\x00\x00\x00\x00mif1heic" + b"\x00" * 64)
    proc = run(str(fake), str(tmp_path / "out.ppm"))
    assert proc.returncode == 2
    assert "HEIC" in proc.stderr and "pillow-heif" in proc.stderr
    # Mismo contenedor con otra extensión: se detecta por la marca 'ftyp'.
    disguised = tmp_path / "foto.jpg"
    disguised.write_bytes(fake.read_bytes())
    proc = run(str(disguised), str(tmp_path / "out.ppm"))
    assert proc.returncode == 2 and "HEIC" in proc.stderr


def test_invalid_inputs_exit_2(tmp_path):
    assert run(str(tmp_path / "missing.png"), str(tmp_path / "o.ppm")).returncode == 2
    garbage = tmp_path / "g.png"
    garbage.write_bytes(b"not an image")
    proc = run(str(garbage), str(tmp_path / "o.ppm"))
    assert proc.returncode == 2 and "no se puede abrir" in proc.stderr
    assert run().returncode == 2
    ok = tmp_path / "ok.png"
    Image.fromarray(np.zeros((4, 4, 3), np.uint8)).save(ok)
    assert run(str(ok), str(tmp_path / "o.ppm"), "--max-side", "0").returncode == 2


def test_rgb_output_from_palette_and_grayscale(tmp_path):
    pal = Image.fromarray(np.tile(np.arange(8, dtype=np.uint8) * 30, (3, 1))).convert("P")
    src = tmp_path / "p.gif"
    pal.save(src)
    out = tmp_path / "o.ppm"
    assert run(str(src), str(out)).returncode == 0
    assert sc.read_ppm(out).shape == (3, 8, 3)
    gray = tmp_path / "g.png"
    Image.fromarray(np.full((2, 3), 90, np.uint8), "L").save(gray)
    assert run(str(gray), str(out)).returncode == 0
    assert np.array_equal(sc.read_ppm(out), np.full((2, 3, 3), 90, np.uint8))


def test_in_memory_helpers_match_script(tmp_path, img):
    import importlib.util

    spec = importlib.util.spec_from_file_location("to_ppm", TO_PPM)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    assert mod.reduce_factor(4000, 3000, 256) == 16
    assert mod.reduce_factor(256, 100, 256) == 1
    assert mod.reduce_factor(257, 100, 256) == 2
    assert mod.reduce_factor(10, 10, None) == 1
    buf = io.BytesIO()
    Image.fromarray(img).save(buf, "PNG")
    buf.seek(0)
    rgb, note = mod.to_srgb(Image.open(buf))
    assert rgb.mode == "RGB" and "asume sRGB" in note
