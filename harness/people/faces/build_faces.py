#!/usr/bin/env python3
"""Caras que NO son personas: retratos enmarcados y pantallas, solos y pegados a una persona real.

    # genera los 6 PNG en harness/out/faces (no se versionan) y comprueba el manifiesto
    uv run --project oracle python harness/people/faces/build_faces.py build [--out DIR]
    # regenera en memoria y compara el sha256 de los píxeles con faces.json (sin escribir)
    uv run --project oracle python harness/people/faces/build_faces.py check
    # reescribe faces.json (solo si cambia el generador a propósito)
    uv run --project oracle python harness/people/faces/build_faces.py manifest
    # regenera person01_mask.png desde una capa de visionmask (solo si cambia Vision)
    build-subject/visionmask harness/people/01_single_black_outfit.png --out-dir <tmp> \\
        --variants largest --layers
    uv run --project oracle python harness/people/faces/build_faces.py mask \\
        --person <tmp>/01_single_black_outfit.largest.layers/person.pgm

Para qué: la separación de instancias (ADR-010, `PersonSplitter`) convierte cada CARA de
Vision sin pose en una semilla de persona, y la regla anti-fantasmas acepta una instancia
que solo tiene cara. Una cara de póster, pantalla o retrato detrás de una persona real
crearía entonces una PERSONA FANTASMA que se lleva parte de la ropa de la persona de
verdad. Estas seis imágenes son la prueba: con `--no-face-seed-body` (sin la regla de
evidencia corporal) aparece la persona fantasma; con la regla, no.

Todo se deriva de `01_single_black_outfit.png` (mujer de negro sobre pared blanca) y de
`05_three_friends_closeup.png` (de donde salen los recortes de cara), las dos CC0 1.0 de
harness/people (ver SOURCES.md): no hay fotos nuevas ni del usuario. La máscara de la
persona de 01 está versionada (`person01_mask.png`, PNG de 1 bit, la instancia de Vision
reescalada al raster de 1024x682) para que `build` y `check` funcionen sin Vision.

  - poster_alone.png        retrato enmarcado en la pared, sin nadie (390x682)
  - screen_alone.png        pantalla encendida con una cara, sin nadie (390x682)
  - poster_touching.png     retrato enmarcado pegado a la silueta de la persona (1024x682)
  - poster_behind.png       retrato detrás de la persona: ella lo tapa (1024x682)
  - poster_on_torso.png     retrato SOBRE el torso de la persona, dentro de su silueta: el caso
                            peor para la separación (la cara falsa cae dentro de su instancia)
  - screen_touching.png     pantalla pegada a la silueta de la persona (1024x682)
  - screen_behind.png       pantalla detrás de la persona (1024x682)
  - screen_on_torso.png     pantalla (móvil o tableta) sostenida delante del torso, dentro de la
                            silueta: la cara falsa comparte instancia, rectángulo de persona y
                            puntos de pose con la persona de verdad

Sin red y sin dependencias fuera de numpy + Pillow; sin números aleatorios (todo es
determinista a partir de las dos fotos y de la máscara). El manifiesto guarda el sha256 de
los PÍXELES RGB (no del PNG, cuyo zlib puede variar).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
PEOPLE = HERE.parent
ROOT = HERE.parents[2]
MANIFEST = HERE / "faces.json"
MASK_PNG = HERE / "person01_mask.png"
DEFAULT_OUT = ROOT / "harness" / "out" / "faces"

PERSON_PHOTO = PEOPLE / "01_single_black_outfit.png"
FACE_PHOTO = PEOPLE / "05_three_friends_closeup.png"
# Rectángulos de cara de VNDetectFaceLandmarksRequest en 05 (macOS 26, píxeles del PNG
# 683x1024, redondeados hacia fuera): izquierda, derecha y centro.
FACE_BOXES = [(124, 149, 273, 298), (429, 159, 576, 305), (282, 176, 424, 318)]
# Alto de la cara (px) en el retrato y en la pantalla: la cara real de 01 mide 35 px, así
# que 80 px es un retrato grande y bien visible para Vision.
FACE_HEIGHT = 80
FRAME = 7          # marco de madera oscura (px)
MAT = 13           # paspartú claro (px)
BEZEL = 11         # marco de la pantalla (px)
# Esquina superior izquierda del bloque (retrato o pantalla) en la foto de 01.
BLOCK_TOP = 250
# Alto de la cara (px) del bloque que se pega SOBRE el torso: una cara estampada o la de
# una pantalla que la persona sostiene, más pequeña que un retrato de pared.
TORSO_FACE_HEIGHT = 34
# Centro del bloque sobre el torso (píxeles de 01: el pecho de la persona).
TORSO_CENTER = (495, 455)
# Para "alone": mitad izquierda de 01 (la persona empieza en x = 397).
ALONE_WIDTH = 390


def load_rgb(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.uint8)


def read_pgm(path: Path) -> np.ndarray:
    data = path.read_bytes()
    parts = data.split(b"\n", 3)
    if parts[0] != b"P5" or parts[2] != b"255":
        raise SystemExit(f"{path}: se esperaba P5 con maxval 255")
    w, h = map(int, parts[1].split())
    return np.frombuffer(parts[3][: w * h], dtype=np.uint8).reshape(h, w)


def person_mask() -> np.ndarray:
    """Máscara binaria (bool) de la persona de 01, del PNG versionado."""
    if not MASK_PNG.exists():
        raise SystemExit(f"falta {MASK_PNG}: regenérala con el subcomando `mask`")
    return np.asarray(Image.open(MASK_PNG).convert("L"), dtype=np.uint8) >= 128


def face_crop(index: int, height: int) -> np.ndarray:
    """Recorte de la cara `index` de 05 escalado a `height` px de alto (BICUBIC)."""
    x0, y0, x1, y1 = FACE_BOXES[index]
    img = Image.open(FACE_PHOTO).convert("RGB")
    # Un retrato enseña algo más que el rectángulo de la cara: se amplía un 35 % en alto
    # (pelo y barbilla) y un 20 % en ancho, recortado a la foto.
    w, h = x1 - x0, y1 - y0
    bx0 = max(0, x0 - int(0.20 * w))
    bx1 = min(img.width, x1 + int(0.20 * w))
    by0 = max(0, y0 - int(0.35 * h))
    by1 = min(img.height, y1 + int(0.20 * h))
    crop = img.crop((bx0, by0, bx1, by1))
    scale = height / (y1 - y0)
    size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
    return np.asarray(crop.resize(size, Image.BICUBIC), dtype=np.uint8)


def poster(index: int, height: int = FACE_HEIGHT) -> np.ndarray:
    """Retrato enmarcado: marco de madera oscura + paspartú claro + la cara."""
    face = face_crop(index, height)
    fh, fw, _ = face.shape
    h, w = fh + 2 * (FRAME + MAT), fw + 2 * (FRAME + MAT)
    out = np.zeros((h, w, 3), dtype=np.uint8)
    out[:, :] = (62, 44, 32)                              # marco
    out[FRAME:h - FRAME, FRAME:w - FRAME] = (238, 234, 226)  # paspartú
    out[FRAME + MAT:h - FRAME - MAT, FRAME + MAT:w - FRAME - MAT] = face
    # Bisel del marco: una línea clara arriba/izquierda y una oscura abajo/derecha.
    out[0, :] = out[:, 0] = (96, 72, 54)
    out[h - 1, :] = out[:, w - 1] = (38, 27, 20)
    return out


def screen(index: int, height: int = FACE_HEIGHT) -> np.ndarray:
    """Pantalla encendida: marco negro, la cara con dominante azul y un brillo diagonal."""
    face = face_crop(index, height)
    fh, fw, _ = face.shape
    # Una pantalla es más ancha que la cara: 16:10 alrededor de ella.
    ih, iw = fh + 26, max(fw + 40, int(round(1.6 * (fh + 26))))
    inner = np.zeros((ih, iw, 3), dtype=np.float64)
    inner[:, :] = (22, 26, 34)                            # fondo de la imagen en pantalla
    y0 = (ih - fh) // 2
    x0 = (iw - fw) // 2
    inner[y0:y0 + fh, x0:x0 + fw] = face.astype(np.float64)
    inner *= np.array([0.92, 0.97, 1.10])                 # dominante fría de un panel
    yy, xx = np.mgrid[0:ih, 0:iw]
    glare = np.clip(1.0 - np.abs((xx * 0.5 + yy) - 0.35 * (iw * 0.5 + ih)) / (0.10 * (iw + ih)), 0, 1)
    inner += (glare * 26.0)[:, :, None]
    h, w = ih + 2 * BEZEL, iw + 2 * BEZEL
    out = np.zeros((h, w, 3), dtype=np.uint8)
    out[:, :] = (17, 17, 19)                              # marco
    out[0, :] = out[:, 0] = (44, 44, 48)
    out[h - 1, :] = out[:, w - 1] = (8, 8, 9)
    out[BEZEL:h - BEZEL, BEZEL:w - BEZEL] = np.clip(inner, 0, 255).astype(np.uint8)
    return out


def paste(base: np.ndarray, block: np.ndarray, x: int, y: int, keep: np.ndarray | None) -> np.ndarray:
    """Pega `block` en (x, y) y, con `keep`, restaura los píxeles de la persona (queda delante)."""
    out = base.copy()
    bh, bw, _ = block.shape
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(base.shape[1], x + bw), min(base.shape[0], y + bh)
    if x0 >= x1 or y0 >= y1:
        raise SystemExit("el bloque cae fuera de la foto")
    sub = block[y0 - y:y1 - y, x0 - x:x1 - x]
    region = out[y0:y1, x0:x1]
    if keep is None:
        region[:, :] = sub
    else:
        m = keep[y0:y1, x0:x1]
        region[~m] = sub[~m]
    out[y0:y1, x0:x1] = region
    return out


def left_edge(mask: np.ndarray, y0: int, y1: int) -> int:
    """x del píxel de la persona más a la izquierda entre las filas [y0, y1)."""
    band = mask[max(0, y0):max(1, y1)]
    xs = np.nonzero(band.any(axis=0))[0]
    if len(xs) == 0:
        raise SystemExit("la máscara no tiene píxeles en esa banda")
    return int(xs[0])


def build() -> dict[str, np.ndarray]:
    photo = load_rgb(PERSON_PHOTO)
    mask = person_mask()
    if mask.shape != photo.shape[:2]:
        raise SystemExit("person01_mask.png no mide lo mismo que 01_single_black_outfit.png")
    out: dict[str, np.ndarray] = {}
    for name, block in (("poster", poster(0)), ("screen", screen(1))):
        bh, bw, _ = block.shape
        edge = left_edge(mask, BLOCK_TOP, BLOCK_TOP + bh)
        # Pegado: el borde derecho del bloque toca la silueta. Detrás: se mete 40 % de su
        # ancho por debajo de la persona, que lo tapa (keep = máscara).
        out[f"{name}_touching"] = paste(photo, block, edge - bw, BLOCK_TOP, None)
        out[f"{name}_behind"] = paste(photo, block, edge - bw + int(0.40 * bw), BLOCK_TOP, mask)
        # Solo: mitad izquierda de la pared, con el bloque centrado.
        wall = photo[:, :ALONE_WIDTH].copy()
        out[f"{name}_alone"] = paste(wall, block, (ALONE_WIDTH - bw) // 2, (photo.shape[0] - bh) // 2, None)
    # Sobre el torso: la cara falsa cae DENTRO de la instancia de Vision de la persona, con
    # su mismo rectángulo de persona y sus mismos puntos de pose (el caso peor para la
    # separación). El bloque se recorta con la silueta, como un estampado en la prenda o una
    # pantalla que ella sostiene: ni un píxel del bloque cae fuera de la persona.
    for name, block in (("poster", poster(0, TORSO_FACE_HEIGHT)), ("screen", screen(1, TORSO_FACE_HEIGHT))):
        bh, bw, _ = block.shape
        x, y = TORSO_CENTER[0] - bw // 2, TORSO_CENTER[1] - bh // 2
        inner = mask[y + bh // 4:y + 3 * bh // 4, x + bw // 4:x + 3 * bw // 4]
        if not inner.all():
            raise SystemExit("la cara del bloque sobre el torso se sale de la silueta de la persona")
        out[f"{name}_on_torso"] = paste(photo, block, x, y, ~mask)
    return out


def digest(a: np.ndarray) -> str:
    return hashlib.sha256(np.ascontiguousarray(a).tobytes()).hexdigest()


def manifest_entries(images: dict[str, np.ndarray]) -> dict:
    return {
        "note": "sha256 de los píxeles RGB de cada imagen (no del PNG)",
        "images": [
            {"file": f"{k}.png", "width": v.shape[1], "height": v.shape[0], "sha256_pixels": digest(v)}
            for k, v in sorted(images.items())
        ],
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--out", default=str(DEFAULT_OUT))
    sub.add_parser("check")
    sub.add_parser("manifest")
    m = sub.add_parser("mask")
    m.add_argument("--person", required=True, help="person.pgm de visionmask --layers sobre 01")
    a = ap.parse_args()

    if a.cmd == "mask":
        pgm = read_pgm(Path(a.person))
        Image.fromarray((pgm >= 128).astype(np.uint8) * 255, "L").convert("1").save(MASK_PNG, optimize=True)
        print(f"{MASK_PNG}: {pgm.shape[1]}x{pgm.shape[0]}, {MASK_PNG.stat().st_size} B")
        return 0

    images = build()
    want = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else None
    if a.cmd == "manifest":
        MANIFEST.write_text(json.dumps(manifest_entries(images), indent=2, ensure_ascii=False) + "\n")
        print(f"{MANIFEST}: {len(images)} imágenes")
        return 0
    if want is None:
        print(f"falta {MANIFEST}", file=sys.stderr)
        return 1
    have = {e["file"]: e for e in manifest_entries(images)["images"]}
    bad = 0
    for e in want["images"]:
        got = have.get(e["file"])
        if got is None or got["sha256_pixels"] != e["sha256_pixels"]:
            print(f"DIFIERE {e['file']}: {e['sha256_pixels']} != {got and got['sha256_pixels']}", file=sys.stderr)
            bad += 1
    if len(have) != len(want["images"]):
        print(f"imágenes: {len(have)} generadas, {len(want['images'])} en el manifiesto", file=sys.stderr)
        bad += 1
    if bad:
        return 1
    if a.cmd == "build":
        out = Path(a.out)
        out.mkdir(parents=True, exist_ok=True)
        for k, v in sorted(images.items()):
            Image.fromarray(v, "RGB").save(out / f"{k}.png", optimize=True)
        print(f"faces: {len(images)} PNG en {out} (manifiesto OK)")
    else:
        print(f"faces check: {len(images)} imágenes idénticas al manifiesto")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
