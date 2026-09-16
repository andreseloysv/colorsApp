#!/usr/bin/env python3
"""Imágenes sintéticas SIN personas para medir las «personas fantasma» de Vision.

    # genera las 148 PNG en harness/out/nopeople (no se versionan) y comprueba el manifiesto
    uv run --project oracle python harness/people/nopeople/build_nopeople.py build [--out DIR]
    # regenera en memoria y compara el sha256 de los píxeles con nopeople.json (sin escribir)
    uv run --project oracle python harness/people/nopeople/build_nopeople.py check
    # reescribe nopeople.json (solo si cambia el generador a propósito)
    uv run --project oracle python harness/people/nopeople/build_nopeople.py manifest

VNGeneratePersonInstanceMaskRequest devuelve instancias en imágenes sin nadie (PNG liso,
bandas de color, sintéticos de la capa 3): SubjectKit exige evidencia corporal
(docs/DECISIONS.md, ADR-010). Este conjunto es la prueba negativa: 148 imágenes
deterministas en cuatro familias, con colores del diccionario de Wada
(data/wada/dictionary.json) y tamaños variados (Vision reescala la entrada):

  - blocks (34):    bandas verticales u horizontales, rejilla, bloque central sobre fondo y
                    rectángulos sueltos con 2–4 colores de una combinación, con ruido leve.
  - gradients (33): degradados lineales y radiales entre colores de una combinación, color
                    liso (el caso del PNG amarillo) y viñeteado.
  - textures (33):  rayas, cuadros, tela escocesa, tejido (senos cruzados), puntos, mármol y
                    manchas de ruido suave (formas orgánicas, las más parecidas a una silueta).
  - garments (48):  prendas SIN persona, el caso de uso «foto de una prenda» y del carrete:
                    vestidos, abrigos, camisas, monos, pantalones, faldas y camisetas colgados en
                    percha (retrato y apaisado), percheros con 2-4 prendas, prendas planas sobre
                    una superficie (sueltas o un conjunto top + pantalón + zapatos, colocado como
                    un cuerpo), abrigo en un colgador de puerta y prendas dobladas en pila. Vision
                    confunde estas siluetas con personas (verificación de ADR-010: la regla de
                    forma sola aceptaba vestidos colgados).

Sin red y sin dependencias fuera de numpy + Pillow. Semilla fija por imagen
(numpy.random.default_rng(1000 + i), PCG64, estable entre versiones de numpy). El
manifiesto guarda el sha256 de los PÍXELES RGB (no del PNG, cuyo zlib puede variar).
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
ROOT = HERE.parents[2]
MANIFEST = HERE / "nopeople.json"
DEFAULT_OUT = ROOT / "harness" / "out" / "nopeople"
SIZES = [(256, 256), (640, 480), (1024, 768), (768, 1024), (512, 512)]
# Prendas: fotos de móvil en retrato sobre todo (Vision reescala la entrada).
GARMENT_SIZES = [(768, 1024), (600, 800), (1024, 768), (720, 960), (512, 512), (768, 1024)]
FAMILIES = [("blocks", 34), ("gradients", 33), ("textures", 33), ("garments", 48)]


def wada():
    d = json.loads((ROOT / "data" / "wada" / "dictionary.json").read_text())
    colors = np.array([c["rgb"] for c in d["colors"]], dtype=np.float64)
    combos = [c["colors"] for c in d["combinations"]]
    return colors, combos, d["dict_version"]


def to_u8(img: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(img), 0, 255).astype(np.uint8)


def smooth_noise(rng, h, w, cell):
    """Ruido de valor bilineal (manchas suaves) en [0, 1]."""
    gh, gw = h // cell + 2, w // cell + 2
    g = rng.random((gh, gw))
    ys = np.arange(h) / cell
    xs = np.arange(w) / cell
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = (ys - y0)[:, None]
    fx = (xs - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0]
    b = g[y0][:, x0 + 1]
    c = g[y0 + 1][:, x0]
    e = g[y0 + 1][:, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + e * fx) * fy


def blocks(rng, h, w, pal, k):
    layout = ["vbands", "hbands", "grid", "center", "rects"][k % 5]
    img = np.zeros((h, w, 3))
    n = len(pal)
    if layout == "vbands":
        cuts = np.sort(rng.uniform(0.15, 0.85, n - 1))
        edges = np.r_[0, (cuts * w).astype(int), w]
        for j in range(n):
            img[:, edges[j]:edges[j + 1]] = pal[j]
    elif layout == "hbands":
        cuts = np.sort(rng.uniform(0.15, 0.85, n - 1))
        edges = np.r_[0, (cuts * h).astype(int), h]
        for j in range(n):
            img[edges[j]:edges[j + 1], :] = pal[j]
    elif layout == "grid":
        gy, gx = int(rng.integers(2, 5)), int(rng.integers(2, 5))
        for yy in range(gy):
            for xx in range(gx):
                img[yy * h // gy:(yy + 1) * h // gy, xx * w // gx:(xx + 1) * w // gx] = pal[int(rng.integers(0, n))]
    elif layout == "center":
        img[:] = pal[0]
        bh, bw = int(h * rng.uniform(0.3, 0.7)), int(w * rng.uniform(0.2, 0.6))
        y0, x0 = (h - bh) // 2, (w - bw) // 2
        img[y0:y0 + bh, x0:x0 + bw] = pal[1]
        if n > 2:
            img[y0 + bh // 3:y0 + 2 * bh // 3, x0 + bw // 3:x0 + 2 * bw // 3] = pal[2]
    else:
        img[:] = pal[0]
        for _ in range(int(rng.integers(3, 9))):
            bh, bw = int(h * rng.uniform(0.1, 0.5)), int(w * rng.uniform(0.1, 0.4))
            y0, x0 = int(rng.integers(0, h - bh)), int(rng.integers(0, w - bw))
            img[y0:y0 + bh, x0:x0 + bw] = pal[int(rng.integers(1, n))] if n > 1 else pal[0]
    img += rng.normal(0, rng.uniform(0, 5), img.shape)
    return img, layout


def gradients(rng, h, w, pal, k):
    layout = ["linear", "radial", "flat", "vignette", "diagonal3"][k % 5]
    yy, xx = np.mgrid[0:h, 0:w]
    if layout == "flat":
        img = np.broadcast_to(pal[0], (h, w, 3)).copy()
    elif layout == "linear":
        t = (xx / max(1, w - 1)) if rng.random() < 0.5 else (yy / max(1, h - 1))
        img = pal[0] * (1 - t[..., None]) + pal[1 % len(pal)] * t[..., None]
    elif layout == "radial":
        cy, cx = h * rng.uniform(0.3, 0.7), w * rng.uniform(0.3, 0.7)
        t = np.clip(np.hypot(yy - cy, xx - cx) / (0.6 * max(h, w)), 0, 1)
        img = pal[0] * (1 - t[..., None]) + pal[1 % len(pal)] * t[..., None]
    elif layout == "vignette":
        t = np.clip(np.hypot(yy - h / 2, xx - w / 2) / (0.7 * max(h, w)), 0, 1)
        img = pal[0] * (1 - 0.6 * t[..., None] ** 2)
    else:
        t = np.clip((xx / max(1, w - 1) + yy / max(1, h - 1)) / 2, 0, 1)[..., None]
        c2 = pal[2 % len(pal)]
        img = np.where(t < 0.5, pal[0] * (1 - 2 * t) + pal[1 % len(pal)] * 2 * t,
                       pal[1 % len(pal)] * (2 - 2 * t) + c2 * (2 * t - 1))
    img = img + rng.normal(0, rng.uniform(0, 3), (h, w, 3))
    return img, layout


def textures(rng, h, w, pal, k):
    layout = ["stripes", "checker", "plaid", "weave", "dots", "marble", "blobs"][k % 7]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    n = len(pal)
    img = np.broadcast_to(pal[0], (h, w, 3)).copy()
    if layout == "stripes":
        period = rng.uniform(8, 60)
        ang = rng.uniform(0, np.pi)
        u = (xx * np.cos(ang) + yy * np.sin(ang)) / period
        img = np.where((np.floor(u) % 2 == 0)[..., None], pal[0], pal[1 % n])
    elif layout == "checker":
        s = int(rng.integers(12, 80))
        img = np.where((((yy // s) + (xx // s)) % 2 == 0)[..., None], pal[0], pal[1 % n])
    elif layout == "plaid":
        s1, s2 = rng.uniform(20, 70), rng.uniform(20, 70)
        a = (np.sin(xx / s1 * 2 * np.pi) > 0.3)[..., None]
        b = (np.sin(yy / s2 * 2 * np.pi) > 0.3)[..., None]
        img = pal[0] * 1.0
        img = np.where(a, 0.5 * img + 0.5 * pal[1 % n], img)
        img = np.where(b, 0.5 * img + 0.5 * pal[2 % n], img)
    elif layout == "weave":
        f = rng.uniform(0.2, 0.6)
        t = (0.5 + 0.25 * np.sin(xx * f) * np.sin(yy * f * 1.3) + 0.25 * np.sin((xx + yy) * f * 0.5))[..., None]
        img = pal[0] * (1 - t) + pal[1 % n] * t
    elif layout == "dots":
        s = rng.uniform(16, 64)
        r = s * rng.uniform(0.15, 0.4)
        d = np.hypot((xx % s) - s / 2, (yy % s) - s / 2)
        img = np.where((d < r)[..., None], pal[1 % n], pal[0])
    elif layout == "marble":
        nz = smooth_noise(rng, h, w, int(rng.integers(24, 96)))
        t = (0.5 + 0.5 * np.sin(xx / rng.uniform(20, 80) + 6 * nz))[..., None]
        img = pal[0] * (1 - t) + pal[1 % n] * t
    else:
        nz = smooth_noise(rng, h, w, int(rng.integers(40, 160)))
        levels = np.quantile(nz, np.linspace(0, 1, n + 1)[1:-1]) if n > 1 else []
        idx = np.digitize(nz, levels)
        img = pal[np.clip(idx, 0, n - 1)]
    img = img + rng.normal(0, rng.uniform(0, 4), img.shape)
    return img, layout


# --- Prendas sin persona -------------------------------------------------------------------
# Contornos normalizados: x centrado en 0, y = 0 arriba y 1 abajo (alto de la prenda).
SHAPES = {
    "dress": [(-0.12, 0), (0.12, 0), (0.17, 0.08), (0.16, 0.38), (0.42, 1.0), (-0.42, 1.0), (-0.16, 0.38), (-0.17, 0.08)],
    "coat": [(-0.16, 0), (0.16, 0), (0.42, 0.1), (0.52, 0.72), (0.38, 0.74), (0.36, 1.0), (-0.36, 1.0), (-0.38, 0.74),
             (-0.52, 0.72), (-0.42, 0.1)],
    "shirt": [(-0.14, 0), (0.14, 0), (0.44, 0.1), (0.62, 0.5), (0.46, 0.56), (0.38, 0.4), (0.37, 1.0), (-0.37, 1.0),
              (-0.38, 0.4), (-0.46, 0.56), (-0.62, 0.5), (-0.44, 0.1)],
    "tshirt": [(-0.16, 0), (0.16, 0), (0.48, 0.08), (0.66, 0.34), (0.44, 0.44), (0.4, 0.3), (0.4, 1.0), (-0.4, 1.0),
               (-0.4, 0.3), (-0.44, 0.44), (-0.66, 0.34), (-0.48, 0.08)],
    "jumpsuit": [(-0.2, 0), (0.2, 0), (0.3, 0.12), (0.28, 0.5), (0.32, 1.0), (0.07, 1.0), (0.0, 0.58), (-0.07, 1.0),
                 (-0.32, 1.0), (-0.28, 0.5), (-0.3, 0.12)],
    "trousers": [(-0.26, 0), (0.26, 0), (0.3, 1.0), (0.05, 1.0), (0.0, 0.3), (-0.05, 1.0), (-0.3, 1.0)],
    "skirt": [(-0.2, 0), (0.2, 0), (0.46, 1.0), (-0.46, 1.0)],
}
HANGER_KINDS = ["dress", "coat", "shirt", "jumpsuit", "trousers", "skirt", "tshirt"]


def fill_polygon(h, w, pts, ss=2):
    """Cobertura (0..1) de un polígono en píxeles: regla par-impar en los centros de una rejilla
    `ss` x `ss` por píxel (sin dependencias de rasterizado de Pillow, estable entre versiones)."""
    H, W = h * ss, w * ss
    ys = (np.arange(H) + 0.5) / ss
    xs = (np.arange(W) + 0.5) / ss
    inside = np.zeros((H, W), dtype=bool)
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        if y0 == y1:
            continue
        rows = (ys >= min(y0, y1)) & (ys < max(y0, y1))
        if not rows.any():
            continue
        xc = x0 + (ys[rows] - y0) * (x1 - x0) / (y1 - y0)
        inside[rows] ^= xs[None, :] < xc[:, None]
    return inside.reshape(h, ss, w, ss).mean(axis=(1, 3))


def blur(img, sigma):
    if sigma <= 0:
        return img
    r = int(np.ceil(3 * sigma))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    pad = np.pad(img, ((r, r), (r, r), (0, 0)), mode="edge")
    tmp = np.apply_along_axis(lambda v: np.convolve(v, k, mode="valid"), 0, pad)
    return np.apply_along_axis(lambda v: np.convolve(v, k, mode="valid"), 1, tmp)


def paint(img, cov, color, shade=None):
    c = np.asarray(color, dtype=np.float64)[None, None, :]
    if shade is not None:
        c = c * shade[..., None]
    return img * (1 - cov[..., None]) + c * cov[..., None]


def folds(rng, h, w):
    """Pliegues: modulación suave de la luminancia (0.8..1.1)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    f1, f2 = rng.uniform(0.01, 0.04), rng.uniform(0.004, 0.02)
    return 0.95 + 0.08 * np.sin(xx * f1 + 3 * np.sin(yy * f2)) + 0.04 * np.sin(yy * f1 * 0.7)


def place(shape, cx, top, scale, sx=1.0):
    return [(cx + x * scale * sx, top + y * scale) for x, y in SHAPES[shape]]


def hanger_lines(img, cx, top, scale, rng):
    """Percha: gancho y dos brazos finos (polígonos delgados)."""
    col = (rng.uniform(40, 90),) * 3 if rng.random() < 0.7 else (150, 110, 70)
    h, w = img.shape[:2]
    t = max(1.5, 0.006 * scale)
    arm = 0.3 * scale
    for (ax, ay), (bx, by) in [((cx, top - 0.06 * scale), (cx - arm, top + 0.02 * scale)),
                               ((cx, top - 0.06 * scale), (cx + arm, top + 0.02 * scale)),
                               ((cx - arm, top + 0.02 * scale), (cx + arm, top + 0.02 * scale)),
                               ((cx, top - 0.06 * scale), (cx, top - 0.12 * scale))]:
        dx, dy = bx - ax, by - ay
        n = max(1e-9, np.hypot(dx, dy))
        ox, oy = -dy / n * t, dx / n * t
        img = paint(img, fill_polygon(h, w, [(ax + ox, ay + oy), (bx + ox, by + oy), (bx - ox, by - oy), (ax - ox, ay - oy)]), col)
    return img


def garments(rng, h, w, pal, k, colors):
    layout = ["hanger", "hanger_wide", "rack", "flatlay", "outfit_flat", "door_coat", "hanger", "pile"][k % 8]
    bg1 = np.array([rng.uniform(170, 245)] * 3) + rng.uniform(-12, 12, 3)
    bg2 = bg1 * rng.uniform(0.8, 0.97)
    yy = (np.arange(h) / max(1, h - 1))[:, None, None]
    img = bg1[None, None, :] * (1 - yy) + bg2[None, None, :] * yy
    img = np.repeat(img, w, axis=1)
    sh = folds(rng, h, w)
    kind = HANGER_KINDS[(k // 8) % len(HANGER_KINDS)]
    if layout in ("hanger", "hanger_wide"):
        scale = min(h, w) * rng.uniform(0.62, 0.9) if layout == "hanger" else h * rng.uniform(0.6, 0.8)
        cx, top = w / 2 + rng.uniform(-0.08, 0.08) * w, h * rng.uniform(0.08, 0.16)
        img = hanger_lines(img, cx, top, scale, rng)
        img = paint(img, fill_polygon(h, w, place(kind, cx, top, scale, rng.uniform(0.85, 1.15))), pal[0], sh)
        if len(pal) > 1 and rng.random() < 0.5:  # cinturón o estampado en bloque
            y0 = top + scale * rng.uniform(0.3, 0.45)
            band = [(cx - 0.5 * scale, y0), (cx + 0.5 * scale, y0), (cx + 0.5 * scale, y0 + 0.05 * scale), (cx - 0.5 * scale, y0 + 0.05 * scale)]
            img = paint(img, fill_polygon(h, w, band) * fill_polygon(h, w, place(kind, cx, top, scale)), pal[1], sh)
    elif layout == "rack":
        n = int(rng.integers(2, 5))
        scale = min(h / 1.25, w / (n * 0.95)) * rng.uniform(0.8, 1.0)
        top = h * 0.12
        rail = [(0, top - 0.13 * scale), (w, top - 0.13 * scale), (w, top - 0.11 * scale), (0, top - 0.11 * scale)]
        img = paint(img, fill_polygon(h, w, rail), (70, 70, 70))
        for j in range(n):
            cx = w * (j + 0.5) / n
            img = hanger_lines(img, cx, top, scale, rng)
            kk = HANGER_KINDS[int(rng.integers(0, len(HANGER_KINDS)))]
            img = paint(img, fill_polygon(h, w, place(kk, cx, top, scale * rng.uniform(0.85, 1.0))), pal[j % len(pal)], sh)
    elif layout == "flatlay":
        scale = min(h, w) * rng.uniform(0.6, 0.85)
        kk = ["tshirt", "shirt", "trousers", "dress", "coat"][int(rng.integers(0, 5))]
        cx, top = w / 2, (h - scale) / 2
        pts = place(kk, cx, top, scale)
        ang = rng.uniform(-0.25, 0.25)
        cy = top + scale / 2
        pts = [(cx + (x - cx) * np.cos(ang) - (y - cy) * np.sin(ang), cy + (x - cx) * np.sin(ang) + (y - cy) * np.cos(ang)) for x, y in pts]
        img = paint(img, fill_polygon(h, w, pts), pal[0], sh)
    elif layout == "outfit_flat":
        # Conjunto colocado como un cuerpo: top arriba, pantalón o falda debajo, zapatos al final.
        total = h * rng.uniform(0.82, 0.94)
        cx, top = w / 2, (h - total) / 2
        top_h = total * 0.42
        img = paint(img, fill_polygon(h, w, place("tshirt" if rng.random() < 0.5 else "shirt", cx, top, top_h)), pal[0], sh)
        bottom = "trousers" if rng.random() < 0.6 else "skirt"
        img = paint(img, fill_polygon(h, w, place(bottom, cx, top + top_h * 0.95, total * 0.5, 0.8)), pal[1 % len(pal)], sh)
        for sx in (-1, 1):
            shoe = [(cx + sx * 0.02 * total, top + total * 0.93), (cx + sx * 0.14 * total, top + total * 0.93),
                    (cx + sx * 0.15 * total, top + total), (cx + sx * 0.01 * total, top + total)]
            img = paint(img, fill_polygon(h, w, shoe), pal[2 % len(pal)] if len(pal) > 2 else (30, 30, 30))
    elif layout == "door_coat":
        door = [(w * 0.22, h * 0.04), (w * 0.78, h * 0.04), (w * 0.78, h), (w * 0.22, h)]
        img = paint(img, fill_polygon(h, w, door), colors[int(rng.integers(0, len(colors)))] * 0.6 + 60)
        scale = h * rng.uniform(0.55, 0.75)
        cx, top = w / 2, h * 0.14
        hook = [(cx - 6, top - 14), (cx + 6, top - 14), (cx + 6, top + 4), (cx - 6, top + 4)]
        img = paint(img, fill_polygon(h, w, hook), (50, 50, 50))
        img = paint(img, fill_polygon(h, w, place(["coat", "dress", "jumpsuit"][int(rng.integers(0, 3))], cx, top, scale)), pal[0], sh)
    else:  # pile: prendas dobladas apiladas (rectángulos redondeados por capas)
        n = int(rng.integers(3, 7))
        wid, hh = w * rng.uniform(0.4, 0.6), h * rng.uniform(0.06, 0.1)
        base = h * rng.uniform(0.7, 0.85)
        for j in range(n):
            x0 = w / 2 - wid / 2 + rng.uniform(-0.03, 0.03) * w
            y1 = base - j * hh * 0.95
            img = paint(img, fill_polygon(h, w, [(x0, y1 - hh), (x0 + wid, y1 - hh), (x0 + wid, y1), (x0, y1)]), pal[j % len(pal)], sh)
    img = blur(img, rng.uniform(0.6, 1.6))
    img = img + rng.normal(0, rng.uniform(1, 4), img.shape)
    return img, f"{layout}_{kind}" if layout in ("hanger", "hanger_wide") else layout


def generate():
    colors, combos, dict_version = wada()
    out = []
    i = 0
    for family, count in FAMILIES:
        for k in range(count):
            rng = np.random.default_rng(1000 + i)
            w, h = GARMENT_SIZES[k % len(GARMENT_SIZES)] if family == "garments" else SIZES[i % len(SIZES)]
            combo = combos[int(rng.integers(0, len(combos)))]
            pal = colors[combo]
            if family == "garments":
                img, layout = garments(rng, h, w, pal, k, colors)
            else:
                fn = {"blocks": blocks, "gradients": gradients, "textures": textures}[family]
                img, layout = fn(rng, h, w, pal, k)
            u8 = to_u8(img)
            name = f"np{i:03d}_{family}_{layout}.png"
            out.append((name, u8, {"file": name, "family": family, "layout": layout, "width": w, "height": h,
                                   "combo_colors": [int(c) for c in combo],
                                   "sha256_rgb": hashlib.sha256(u8.tobytes()).hexdigest()}))
            i += 1
    return out, dict_version


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["build", "check", "manifest"])
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args()
    images, dict_version = generate()
    entries = [e for _, _, e in images]
    if args.cmd == "manifest":
        MANIFEST.write_text(json.dumps({"schema": 1, "kind": "subjectkit-nopeople", "dict_version": dict_version,
                                        "n": len(entries), "entries": entries}, indent=1) + "\n")
        print(f"nopeople: manifiesto con {len(entries)} entradas -> {MANIFEST}")
        return 0
    manifest = json.loads(MANIFEST.read_text())
    want = {e["file"]: e["sha256_rgb"] for e in manifest["entries"]}
    got = {e["file"]: e["sha256_rgb"] for e in entries}
    bad = sorted(f for f in set(want) | set(got) if want.get(f) != got.get(f))
    if args.cmd == "build":
        args.out.mkdir(parents=True, exist_ok=True)
        for old in args.out.glob("np*.png"):
            old.unlink()
        for name, u8, _ in images:
            Image.fromarray(u8, "RGB").save(args.out / name, optimize=False)
        print(f"nopeople: {len(images)} PNG en {args.out}")
    if bad:
        print(f"nopeople: {len(bad)} imágenes no coinciden con el manifiesto: {bad[:5]}", file=sys.stderr)
        return 1
    print(f"nopeople: {len(entries)} imágenes coinciden con {MANIFEST.name} (sha256 de píxeles)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
