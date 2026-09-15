#!/usr/bin/env python3
"""Fixtures de ``EngineParityTests`` (app iOS, fase 6) a partir de los goldens de la capa 3.

    uv run --project oracle python oracle/tools/make_ios_fixtures.py [--check]

Solo LEE ``harness/golden/`` (ruta protegida). Escribe en ``ios/ColorsAppTests/Fixtures/``:

- ``<fixture>.ppm``: copia byte a byte de 5 PPM de ``harness/golden/fixtures/`` (elegidos a
  mano para cubrir 2..5 swatches, ``ambiguous`` 0 y 1 y varias degradaciones).
- ``<fixture>_srgb.png``: el mismo PPM como PNG con el perfil ``sRGB Profile.icc`` embebido
  (Pillow; los píxeles son idénticos al PPM).
- ``<fixture>_p3.png``: ``sips --matchTo 'Display P3.icc'`` sobre el PNG sRGB: ColorSync
  convierte los píxeles a Display P3 y embebe ese perfil. En la app, CoreGraphics deshace la
  conversión al dibujar en un CGContext sRGB; el test mide la diferencia (ΔE00 y canales).
- ``expected_match.json``: para cada fixture, el ``sha256`` del PPM, ``combo_id``, los hits
  (id + score en ``%.17g`` tal cual en el golden), los swatches (lab, weight, rgb, hex),
  ``ambiguous`` y ``hash`` de ``harness/golden/match_50.json`` (``ce match --top 3``,
  opciones por defecto), más ``ce_version``/``dict_version`` del golden.

``--check`` no escribe: sale 1 si algún fichero generado falta o difiere (los PNG se
comparan por píxeles y perfil, no por bytes, porque sips no es reproducible byte a byte).
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageCms

REPO_ROOT = Path(__file__).resolve().parents[2]
GOLDEN_DIR = REPO_ROOT / "harness" / "golden"
MATCHES_PATH = GOLDEN_DIR / "match_50.json"
FIXTURES_DIR = GOLDEN_DIR / "fixtures"
OUT_DIR = REPO_ROOT / "ios" / "ColorsAppTests" / "Fixtures"
EXPECTED_NAME = "expected_match.json"
SRGB_ICC = Path("/System/Library/ColorSync/Profiles/sRGB Profile.icc")
P3_ICC = Path("/System/Library/ColorSync/Profiles/Display P3.icc")

# 5 fixtures: 2 swatches exactos (shapes), 3 (jpeg), 4 con ambiguous=1 (distractor),
# 5 swatches (distractor) y 4 con textura.
CHOSEN = [
    "f01_c003_v01.ppm",
    "f13_c076_v07.ppm",
    "f24_c148_v09.ppm",
    "f37_c253_v09.ppm",
    "f50_c348_v02.ppm",
]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_p6(data: bytes) -> Image.Image:
    """P6 binario con maxval 255 (el único formato de los goldens)."""
    parts = data.split(maxsplit=4)
    if parts[0] != b"P6" or parts[3] != b"255":
        raise RuntimeError("PPM no es P6/255")
    w, h = int(parts[1]), int(parts[2])
    header_len = len(data) - len(parts[4])
    pixels = data[header_len:header_len + w * h * 3]
    return Image.frombytes("RGB", (w, h), pixels)


def png_bytes(img: Image.Image, icc: bytes) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG", icc_profile=icc)
    return buf.getvalue()


def profile_description(path: Path) -> str:
    with Image.open(path) as im:
        icc = im.info.get("icc_profile")
    if not icc:
        return ""
    return (ImageCms.getProfileDescription(ImageCms.ImageCmsProfile(io.BytesIO(icc))) or "").strip()


def build_expected(golden: dict, chosen: list[str]) -> dict:
    by_file = {e["file"]: e for e in golden["entries"]}
    entries = []
    for name in chosen:
        e = by_file[name]
        stem = Path(name).stem
        entries.append({
            "file": name,
            "png_srgb": f"{stem}_srgb.png",
            "png_p3": f"{stem}_p3.png",
            "sha256": e["sha256"],
            "combo_id": e["combo_id"],
            "variant": e["variant"],
            "opts": e["opts"],
            "swatches": e["swatches"],
            "hits": e["hits"],
            "ambiguous": e["ambiguous"],
            "hash": e["hash"],
        })
    return {
        "schema": 1,
        "kind": "ios_parity_fixtures",
        "source": "harness/golden/match_50.json",
        "generator": "oracle/tools/make_ios_fixtures.py",
        "ce_version": golden["ce_version"],
        "dict_version": golden["dict_version"],
        "tolerance": golden["tolerance"],
        "top_k": golden["top_k_required"],
        "n": len(entries),
        "entries": entries,
    }


def generate(out_dir: Path) -> None:
    golden = json.loads(MATCHES_PATH.read_text(encoding="utf-8"))
    out_dir.mkdir(parents=True, exist_ok=True)
    srgb_icc = SRGB_ICC.read_bytes()
    for name in CHOSEN:
        src = FIXTURES_DIR / name
        data = src.read_bytes()
        stem = Path(name).stem
        shutil.copyfile(src, out_dir / name)
        img = read_p6(data)
        srgb_png = out_dir / f"{stem}_srgb.png"
        srgb_png.write_bytes(png_bytes(img, srgb_icc))
        p3_png = out_dir / f"{stem}_p3.png"
        subprocess.run(
            ["sips", "--matchTo", str(P3_ICC), str(srgb_png), "--out", str(p3_png)],
            check=True, stdout=subprocess.DEVNULL,
        )
        with Image.open(p3_png) as p3:
            p3_pixels = p3.convert("RGB").tobytes()
        desc = profile_description(p3_png)
        if "p3" not in desc.lower():
            raise RuntimeError(f"{p3_png.name}: perfil embebido '{desc}', se esperaba Display P3")
        if p3_pixels == img.tobytes():
            raise RuntimeError(f"{p3_png.name}: sips no convirtió los píxeles (idénticos al sRGB)")
        print(f"{name}: sha256 {sha256_bytes(data)[:12]} -> {srgb_png.name} (sRGB), {p3_png.name} ('{desc}')")
    expected = build_expected(golden, CHOSEN)
    (out_dir / EXPECTED_NAME).write_text(json.dumps(expected, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{EXPECTED_NAME}: {expected['n']} entradas, ce {expected['ce_version']}, dict {expected['dict_version']}")


def check(out_dir: Path) -> int:
    golden = json.loads(MATCHES_PATH.read_text(encoding="utf-8"))
    problems: list[str] = []
    for name in CHOSEN:
        src = FIXTURES_DIR / name
        dst = out_dir / name
        if not dst.exists() or dst.read_bytes() != src.read_bytes():
            problems.append(f"{name}: falta o difiere del golden")
            continue
        stem = Path(name).stem
        img = read_p6(src.read_bytes())
        srgb_png = out_dir / f"{stem}_srgb.png"
        p3_png = out_dir / f"{stem}_p3.png"
        for png, want_desc in ((srgb_png, "srgb"), (p3_png, "p3")):
            if not png.exists():
                problems.append(f"{png.name}: falta")
                continue
            desc = profile_description(png)
            if want_desc not in desc.lower():
                problems.append(f"{png.name}: perfil '{desc}', se esperaba {want_desc}")
        if srgb_png.exists():
            with Image.open(srgb_png) as im:
                if im.convert("RGB").tobytes() != img.tobytes():
                    problems.append(f"{srgb_png.name}: píxeles distintos del PPM")
    expected_path = out_dir / EXPECTED_NAME
    if not expected_path.exists():
        problems.append(f"{EXPECTED_NAME}: falta")
    elif json.loads(expected_path.read_text(encoding="utf-8")) != build_expected(golden, CHOSEN):
        problems.append(f"{EXPECTED_NAME}: difiere de match_50.json")
    for p in problems:
        print(f"make_ios_fixtures --check: {p}", file=sys.stderr)
    print(f"make_ios_fixtures --check: {'OK' if not problems else 'FALLO'} ({len(CHOSEN)} fixtures)")
    return 1 if problems else 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="solo comprueba que las fixtures están al día")
    ap.add_argument("--out", type=Path, default=OUT_DIR, help=f"directorio de salida (defecto {OUT_DIR})")
    args = ap.parse_args(argv)
    if args.check:
        return check(args.out)
    generate(args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
