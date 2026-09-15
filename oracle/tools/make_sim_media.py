#!/usr/bin/env python3
"""Fotos sintéticas para el carrete del simulador (``DayZeroScanTests``, fase 7).

    uv run --project oracle python oracle/tools/make_sim_media.py [--check]

Escribe en ``ios/ColorsAppTests/Fixtures/sim_media/``:

- ``sim_cNNN.png``: 20 PNG sRGB de 256×256 (perfil ``sRGB Profile.icc`` embebido) con
  bandas verticales de igual anchura y los colores sRGB8 **exactos** de la combinación
  ``NNN`` de ``data/wada/dictionary.json`` (ids fijos en ``CHOSEN``: 7 de 2 colores, 7 de
  3 y 6 de 4). Es la misma construcción que el test de recall exacto de ``test_match.c``.
- ``expected_sim_media.json``: por fixture, los colores de la combinación (índice, nombre,
  hex, rgb), el color medio de la imagen y el resultado de ``build/tools/ce match --json
  --top 3`` (opciones por defecto) sobre los mismos píxeles: hits (id + score),
  ``ambiguous`` y swatches. El test de la app empareja cada scan con su fixture por la
  paleta (todos los colores de la combinación a ΔE00 ≤ 3 de un swatch) y exige que el
  top-1 del motor en el iPhone coincida con ``hits[0].id``.

Si ``build/tools/ce`` no existe, ejecuta ``make build`` en la raíz del repo. ``--check`` no
escribe: sale 1 si algún fichero falta o difiere (los PNG se comparan por píxeles y perfil).
``xcrun simctl addmedia`` los mete en el carrete (``make ios-test-sim-media``).
"""

from __future__ import annotations

import argparse
import io
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
DICT_PATH = REPO_ROOT / "data" / "wada" / "dictionary.json"
CE_CLI = REPO_ROOT / "build" / "tools" / "ce"
OUT_DIR = REPO_ROOT / "ios" / "ColorsAppTests" / "Fixtures" / "sim_media"
EXPECTED_NAME = "expected_sim_media.json"
SRGB_ICC = Path("/System/Library/ColorSync/Profiles/sRGB Profile.icc")
SIZE = 256

# 20 combinaciones fijas: ids 1-120 tienen 2 colores, 121-240 tres y 241-348 cuatro.
CHOSEN = [
    3, 12, 31, 47, 76, 102, 120,            # 2 colores
    121, 148, 160, 177, 199, 222, 240,      # 3 colores
    241, 253, 270, 299, 320, 348,           # 4 colores
]


def load_dictionary() -> dict:
    return json.loads(DICT_PATH.read_text(encoding="utf-8"))


def band_image(rgbs: list[tuple[int, int, int]]) -> Image.Image:
    """Bandas verticales de igual anchura (la última absorbe el resto de píxeles)."""
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    n = len(rgbs)
    width = SIZE // n
    for x in range(SIZE):
        band = min(x // width, n - 1)
        for y in range(SIZE):
            px[x, y] = rgbs[band]
    return img


def png_bytes(img: Image.Image, icc: bytes) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG", icc_profile=icc, optimize=True)
    return buf.getvalue()


def ppm_bytes(img: Image.Image) -> bytes:
    return b"P6\n%d %d\n255\n" % img.size + img.tobytes()


def ensure_cli() -> Path:
    if not CE_CLI.exists():
        print(f"make_sim_media: falta {CE_CLI}, ejecutando make build", file=sys.stderr)
        subprocess.run(["make", "-C", str(REPO_ROOT), "build"], check=True, stdout=subprocess.DEVNULL)
    if not CE_CLI.exists():
        raise RuntimeError(f"no existe {CE_CLI} tras make build")
    return CE_CLI


def ce_match(cli: Path, img: Image.Image, tmpdir: Path, name: str) -> dict:
    ppm = tmpdir / f"{name}.ppm"
    ppm.write_bytes(ppm_bytes(img))
    out = subprocess.run([str(cli), "match", str(ppm), "--json", "--top", "3"],
                         check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def mean_rgb(img: Image.Image) -> list[int]:
    data = img.tobytes()
    n = len(data) // 3
    sums = [0, 0, 0]
    for i in range(0, len(data), 3):
        sums[0] += data[i]
        sums[1] += data[i + 1]
        sums[2] += data[i + 2]
    return [round(s / n) for s in sums]


def build(cli: Path) -> tuple[dict, dict[str, Image.Image]]:
    d = load_dictionary()
    colors = {c["index"]: c for c in d["colors"]}
    combos = {c["id"]: c for c in d["combinations"]}
    version = subprocess.run([str(cli), "version"], check=True, capture_output=True, text=True).stdout.strip()
    entries = []
    images: dict[str, Image.Image] = {}
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        for cid in CHOSEN:
            combo = combos[cid]
            rgbs = [tuple(colors[i]["rgb"]) for i in combo["colors"]]
            img = band_image(rgbs)
            name = f"sim_c{cid:03d}"
            images[name] = img
            result = ce_match(cli, img, tmpdir, name)
            entries.append({
                "file": f"{name}.png",
                "combo_id": cid,
                "size": combo["size"],
                "layout": "vertical_bands",
                "colors": [
                    {"index": i, "name": colors[i]["name"], "hex": colors[i]["hex"], "rgb": colors[i]["rgb"]}
                    for i in combo["colors"]
                ],
                "mean_rgb": mean_rgb(img),
                "expected": {
                    "hits": [{"id": h["id"], "score": h["score"]} for h in result["hits"]],
                    "ambiguous": result["ambiguous"],
                    "swatches": result["swatches"],
                    "hash": result["hash"],
                },
            })
    expected = {
        "schema": 1,
        "kind": "ios_sim_media",
        "generator": "oracle/tools/make_sim_media.py",
        "ce_version": version,
        "dict_version": d["dict_version"],
        "width": SIZE,
        "height": SIZE,
        "top_k": 3,
        "palette_match_max_de00": 3.0,
        "n": len(entries),
        "entries": entries,
    }
    return expected, images


def generate(out_dir: Path) -> None:
    cli = ensure_cli()
    expected, images = build(cli)
    out_dir.mkdir(parents=True, exist_ok=True)
    icc = SRGB_ICC.read_bytes()
    for e in expected["entries"]:
        img = images[Path(e["file"]).stem]
        (out_dir / e["file"]).write_bytes(png_bytes(img, icc))
        top = e["expected"]["hits"][0]
        print(f"{e['file']}: combo {e['combo_id']} ({e['size']} colores) -> top-1 {top['id']} "
              f"score {top['score']:.3g} ambiguous {e['expected']['ambiguous']}")
    (out_dir / EXPECTED_NAME).write_text(json.dumps(expected, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    mismatched = [e["combo_id"] for e in expected["entries"] if e["expected"]["hits"][0]["id"] != e["combo_id"]]
    print(f"{EXPECTED_NAME}: {expected['n']} entradas, ce {expected['ce_version']}, dict {expected['dict_version']}, "
          f"top-1 == combo en {expected['n'] - len(mismatched)}/{expected['n']}"
          + (f" (difieren: {mismatched})" if mismatched else ""))


def check(out_dir: Path) -> int:
    cli = ensure_cli()
    expected, images = build(cli)
    problems: list[str] = []
    for e in expected["entries"]:
        png = out_dir / e["file"]
        if not png.exists():
            problems.append(f"{png.name}: falta")
            continue
        with Image.open(png) as im:
            icc = im.info.get("icc_profile")
            pixels = im.convert("RGB").tobytes()
        if not icc:
            problems.append(f"{png.name}: sin perfil sRGB embebido")
        if pixels != images[Path(e["file"]).stem].tobytes():
            problems.append(f"{png.name}: píxeles distintos de los de la combinación {e['combo_id']}")
    expected_path = out_dir / EXPECTED_NAME
    if not expected_path.exists():
        problems.append(f"{EXPECTED_NAME}: falta")
    elif json.loads(expected_path.read_text(encoding="utf-8")) != expected:
        problems.append(f"{EXPECTED_NAME}: difiere de lo que produce ce match hoy")
    for p in problems:
        print(f"make_sim_media --check: {p}", file=sys.stderr)
    print(f"make_sim_media --check: {'OK' if not problems else 'FALLO'} ({len(CHOSEN)} fixtures)")
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
