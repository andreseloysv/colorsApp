#!/usr/bin/env python3
"""Selfie apretada sintética derivada de ``05_three_friends_closeup.png`` (CC0).

Reproduce el fallo de Vision que vio el usuario con una foto suya (que NO está en el repo):
``VNGeneratePersonInstanceMaskRequest`` junta en una sola instancia a dos adultos pegados
hombro con hombro. Aquí la mujer de la derecha de 05 se recorta con su máscara de Vision y
se desplaza ``--dx`` píxeles hacia la izquierda, por delante (``--order front``) o por
detrás (``--order behind``) de la mujer central; el hueco que deja se rellena con la
mediana por fila de la pared libre de la mitad derecha (listones horizontales; filas
con menos de 10 píxeles libres toman la fila libre más cercana) y el resultado se reduce
a ``--long-side`` píxeles (BICUBIC) para que ``harness/people`` siga por debajo de 8 MB.

    # máscaras de Vision de 05 (persona 0 = central, 1 = izquierda, 2 = derecha):
    build-subject/visionmask harness/people/05_three_friends_closeup.png --out-dir <tmp> \\
        --variants selected0,selected1,selected2 --layers
    uv run --project oracle python harness/people/make_tight_selfie.py \\
        --center <tmp>/05_three_friends_closeup.selected0.layers/person.pgm \\
        --left <tmp>/05_three_friends_closeup.selected1.layers/person.pgm \\
        --right <tmp>/05_three_friends_closeup.selected2.layers/person.pgm \\
        --dx 70 --order front --long-side 512 --out harness/people/synthetic_tight_selfie.png

Sin red y determinista (numpy + Pillow; mismas máscaras -> mismos bytes).
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent


def read_pgm(path: str) -> np.ndarray:
    data = Path(path).read_bytes()
    parts = data.split(b"\n", 3)
    if parts[0] != b"P5" or parts[2] != b"255":
        raise SystemExit(f"{path}: se esperaba P5 con maxval 255")
    w, h = map(int, parts[1].split())
    return np.frombuffer(parts[3][: w * h], dtype=np.uint8).reshape(h, w)


def dilate(mask: np.ndarray, r: int) -> np.ndarray:
    out = mask.copy()
    for _ in range(r):
        m = out.copy()
        m[1:, :] |= out[:-1, :]
        m[:-1, :] |= out[1:, :]
        m[:, 1:] |= out[:, :-1]
        m[:, :-1] |= out[:, 1:]
        out = m
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", default=str(HERE / "05_three_friends_closeup.png"))
    ap.add_argument("--center", required=True)
    ap.add_argument("--left", required=True)
    ap.add_argument("--right", required=True)
    ap.add_argument("--dx", type=int, default=70)
    ap.add_argument("--order", choices=("front", "behind"), default="front")
    ap.add_argument("--long-side", type=int, default=512)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    src = Image.open(a.source)
    icc = src.info.get("icc_profile")
    img = np.asarray(src.convert("RGB"), dtype=np.uint8)
    h, w, _ = img.shape
    center = read_pgm(a.center) >= 128
    left = read_pgm(a.left) >= 128
    right = read_pgm(a.right) >= 128
    for m in (center, left, right):
        if m.shape != (h, w):
            raise SystemExit("las máscaras no miden lo mismo que la foto")

    # Fondo: mediana por fila de la pared que no es de nadie (máscaras dilatadas 20 px),
    # en la mitad derecha de la foto (la zona que queda libre al mover a la persona).
    bg = ~dilate(center | left | right, 20)
    bg[:, : w // 2] = False
    fill = np.zeros((h, 3), dtype=np.uint8)
    have = np.zeros(h, dtype=bool)
    for y in range(h):
        row = img[y][bg[y]]
        if len(row) >= 10:
            fill[y] = np.median(row, axis=0).astype(np.uint8)
            have[y] = True
    rows = np.nonzero(have)[0]
    for y in range(h):
        if not have[y]:
            fill[y] = fill[rows[np.argmin(np.abs(rows - y))]]

    out = img.copy()
    vacate = dilate(right, 6) & ~center & ~left
    ys, xs = np.nonzero(vacate)
    out[ys, xs] = fill[ys]
    ys, xs = np.nonzero(right)
    nx = xs - a.dx
    ok = (nx >= 0) & (nx < w)
    ys, xs, nx = ys[ok], xs[ok], nx[ok]
    if a.order == "behind":
        keep = ~center[ys, nx]
        ys, xs, nx = ys[keep], xs[keep], nx[keep]
    out[ys, nx] = img[ys, xs]

    im = Image.fromarray(out, "RGB")
    scale = a.long_side / max(w, h)
    if scale < 1:
        im = im.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.BICUBIC)
    kwargs = {"icc_profile": icc} if icc else {}
    im.save(a.out, format="PNG", optimize=True, **kwargs)
    print(f"{a.out}: {im.size[0]}x{im.size[1]}, dx {a.dx}, {a.order}, {Path(a.out).stat().st_size} B")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())