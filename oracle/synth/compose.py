"""Composiciones sintéticas de bloques con verdad conocida (capa 2 del harness).

    from synth import compose as sc
    img, truth = sc.compose(seed=7, size=(200, 200), layout="50/30/20")

``compose`` devuelve una imagen sRGB8 ``HxWx3`` (``uint8``) formada por tres
rectángulos de colores planos y la verdad ``truth`` (lista ordenada por área
descendente) con, por color, ``rgb`` (enteros), ``lab`` (CIELAB D65 del oráculo
estricto ``oracle.reference``) y ``area`` (fracción exacta de píxeles).

Determinismo: toda la aleatoriedad sale de ``numpy.random.default_rng(seed)``;
misma semilla, misma imagen y misma verdad, byte a byte.

Colores: sRGB8 uniformes, aceptados solo si ``15 <= L <= 90`` y el ΔE00 mutuo
(colour-science) supera ``min_de`` (15 por defecto), para que la extracción no
tenga excusa para fusionarlos.

Geometría: cinco variantes de rectángulos elegidas por semilla (round-robin, así
las cinco aparecen en cualquier lote de 5 semillas consecutivas):

* ``stripes_h`` / ``stripes_v``: tres franjas en orden aleatorio;
* ``nested``: fondo + rectángulo desplazado que contiene otro rectángulo;
* ``corners``: fondo + dos rectángulos anclados a esquinas opuestas;
* ``l_shape``: una L (franja lateral + franja superior) y el rectángulo restante
  partido en dos, con espejo/volteo aleatorio.

Las tres últimas hacen que la ponderación al centro NO coincida con el área: por
eso la capa 2 compara pesos solo en modo uniforme (``--center-sigma 0``). Las
áreas reales pueden diferir de las nominales del layout en menos de 0,01 por el
redondeo a píxeles enteros; ``truth`` lleva siempre la fracción real.

Transformaciones para los tests de invariancia: ``shuffle_pixels``, ``scale``
(0,5x por promedio de bloque 2x2 y 2x por vecino más cercano), ``mirror``,
``rotate180`` y ``add_noise``; E/S PNM con ``write_ppm``/``read_ppm``.

Oráculo de referencia de la capa: ``palette_reference`` = KMeans de scikit-learn
(k = 3, ``n_init = 10``, ``random_state = 0``) sobre el Lab de los colores únicos
de la imagen ponderados por su frecuencia (equivalente a k-means sobre todos los
píxeles, pero invariante al orden y mucho más rápido).
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Any

import numpy as np

from oracle import reference as ref

#: Layouts admitidos: fracciones nominales de área (siempre tres colores).
LAYOUTS: dict[str, tuple[float, float, float]] = {
    "50/30/20": (0.50, 0.30, 0.20),
    "40/35/25": (0.40, 0.35, 0.25),
}

#: Variantes geométricas; ``compose`` elige ``VARIANTS[(seed - 1) % 5]``.
VARIANTS: tuple[str, ...] = ("stripes_h", "stripes_v", "nested", "corners", "l_shape")

#: Rango admitido de L* para los colores muestreados.
L_MIN = 15.0
L_MAX = 90.0

DEFAULT_SIZE: tuple[int, int] = (200, 200)
DEFAULT_MIN_DE = 15.0


# --------------------------------------------------------------------------------------
# Layouts y colores
# --------------------------------------------------------------------------------------


def parse_layout(layout: str) -> tuple[float, float, float]:
    """``"50/30/20"`` -> ``(0.5, 0.3, 0.2)``; tres partes > 0 que sumen 100, en orden descendente."""
    if layout in LAYOUTS:
        return LAYOUTS[layout]
    parts = [float(p) for p in layout.split("/")]
    if len(parts) != 3 or any(p <= 0 for p in parts) or abs(sum(parts) - 100.0) > 1e-9:
        raise ValueError(f"layout inválido {layout!r}: se esperan tres porcentajes > 0 que sumen 100")
    if parts != sorted(parts, reverse=True):
        raise ValueError(f"layout inválido {layout!r}: las fracciones deben ir en orden descendente")
    return (parts[0] / 100.0, parts[1] / 100.0, parts[2] / 100.0)


def sample_colors(rng: np.random.Generator, n: int = 3, min_de: float = DEFAULT_MIN_DE,
                  max_tries: int = 20000) -> tuple[list[list[int]], list[list[float]]]:
    """``n`` colores sRGB8 con ``L_MIN <= L <= L_MAX`` y ΔE00 mutuo > ``min_de``."""
    rgbs: list[list[int]] = []
    labs: list[list[float]] = []
    tries = 0
    while len(rgbs) < n:
        tries += 1
        if tries > max_tries:
            raise RuntimeError(f"no encontré {n} colores con ΔE00 > {min_de} en {max_tries} intentos")
        rgb = [int(v) for v in rng.integers(0, 256, size=3)]
        lab = ref.srgb8_to_lab_strict(rgb)
        if not (L_MIN <= lab[0] <= L_MAX):
            continue
        if any(float(ref.de2000(lab, np.asarray(other))) <= min_de for other in labs):
            continue
        rgbs.append(rgb)
        labs.append([float(v) for v in lab])
    return rgbs, labs


# --------------------------------------------------------------------------------------
# Geometría (mapas de etiquetas 0, 1, 2; la etiqueta 0 es siempre la de mayor área nominal)
# --------------------------------------------------------------------------------------


def _clamp(v: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, v))


def _rect_dims(area: float, aspect: float, max_w: int, max_h: int) -> tuple[int, int]:
    """Anchura y altura enteras de un rectángulo de ``area`` píxeles y proporción ``aspect`` (w/h)."""
    w = _clamp(int(round(math.sqrt(area * aspect))), 1, max_w)
    h = int(round(area / w))
    if h > max_h or h < 1:
        h = _clamp(h, 1, max_h)
        w = _clamp(int(round(area / h)), 1, max_w)
    return w, h


def _stripes(width: int, height: int, fr: tuple[float, float, float], rng: np.random.Generator,
             vertical: bool) -> np.ndarray:
    length = width if vertical else height
    sizes = [int(round(f * length)) for f in fr[:-1]]
    sizes.append(length - sum(sizes))
    labels = np.empty((height, width), dtype=np.int64)
    pos = 0
    for label in rng.permutation(3):
        size = sizes[int(label)]
        if vertical:
            labels[:, pos:pos + size] = label
        else:
            labels[pos:pos + size, :] = label
        pos += size
    return labels


def _nested(width: int, height: int, fr: tuple[float, float, float], rng: np.random.Generator) -> np.ndarray:
    n = width * height
    labels = np.zeros((height, width), dtype=np.int64)
    wb, hb = _rect_dims((fr[1] + fr[2]) * n, float(rng.uniform(0.6, 1.6)), width, height)
    x0 = int(rng.integers(0, width - wb + 1))
    y0 = int(rng.integers(0, height - hb + 1))
    labels[y0:y0 + hb, x0:x0 + wb] = 1
    wc, hc = _rect_dims(fr[2] * n, float(rng.uniform(0.6, 1.6)), wb, hb)
    x1 = x0 + int(rng.integers(0, wb - wc + 1))
    y1 = y0 + int(rng.integers(0, hb - hc + 1))
    labels[y1:y1 + hc, x1:x1 + wc] = 2
    return labels


def _corners(width: int, height: int, fr: tuple[float, float, float], rng: np.random.Generator) -> np.ndarray:
    n = width * height
    labels = np.zeros((height, width), dtype=np.int64)
    # Un rectángulo en la banda superior y otro en la inferior (alturas que no se
    # solapan), cada uno pegado a la izquierda o a la derecha al azar.
    wb, hb = _rect_dims(fr[1] * n, float(rng.uniform(0.7, 1.5)), width, height // 2)
    wc, hc = _rect_dims(fr[2] * n, float(rng.uniform(0.7, 1.5)), width, height - hb)
    b_on_top = bool(rng.integers(0, 2))
    xb = 0 if rng.integers(0, 2) else width - wb
    xc = 0 if rng.integers(0, 2) else width - wc
    if b_on_top:
        labels[0:hb, xb:xb + wb] = 1
        labels[height - hc:height, xc:xc + wc] = 2
    else:
        labels[height - hb:height, xb:xb + wb] = 1
        labels[0:hc, xc:xc + wc] = 2
    return labels


def _l_shape(width: int, height: int, fr: tuple[float, float, float], rng: np.random.Generator) -> np.ndarray:
    n = width * height
    n0 = int(round(fr[0] * n))
    wa = _clamp(int(round(float(rng.uniform(0.15, 0.35)) * width)), 1, width - 2)
    ha = _clamp(int(round((n0 - wa * height) / (width - wa))), 1, height - 2)
    labels = np.zeros((height, width), dtype=np.int64)
    rem_w = width - wa
    wb = _clamp(int(round(rem_w * fr[1] / (fr[1] + fr[2]))), 1, rem_w - 1)
    labels[ha:, wa:wa + wb] = 1
    labels[ha:, wa + wb:] = 2
    if rng.integers(0, 2):
        labels = labels[:, ::-1]
    if rng.integers(0, 2):
        labels = labels[::-1, :]
    return np.ascontiguousarray(labels)


def _build(seed: int, size: tuple[int, int], layout: str, min_de: float,
           variant: str | None) -> tuple[np.ndarray, str, list[list[int]], list[list[float]]]:
    """Núcleo determinista: colores (primero) y mapa de etiquetas (después) para una semilla."""
    width, height = int(size[0]), int(size[1])
    if width < 8 or height < 8:
        raise ValueError("size mínimo 8x8")
    fr = parse_layout(layout)
    if variant is None:
        variant = VARIANTS[(int(seed) - 1) % len(VARIANTS)]
    if variant not in VARIANTS:
        raise ValueError(f"variante desconocida {variant!r}; válidas: {VARIANTS}")
    rng = np.random.default_rng(int(seed))
    rgbs, labs = sample_colors(rng, 3, min_de)
    if variant == "stripes_h":
        labels = _stripes(width, height, fr, rng, vertical=False)
    elif variant == "stripes_v":
        labels = _stripes(width, height, fr, rng, vertical=True)
    elif variant == "nested":
        labels = _nested(width, height, fr, rng)
    elif variant == "corners":
        labels = _corners(width, height, fr, rng)
    else:
        labels = _l_shape(width, height, fr, rng)
    return labels, variant, rgbs, labs


def compose_labels(seed: int, size: tuple[int, int] = DEFAULT_SIZE, layout: str = "50/30/20",
                   min_de: float = DEFAULT_MIN_DE, variant: str | None = None) -> tuple[np.ndarray, str]:
    """Mapa de etiquetas ``HxW`` (0, 1, 2; la 0 es la de mayor área nominal) y nombre de la variante."""
    labels, variant, _rgbs, _labs = _build(seed, size, layout, min_de, variant)
    return labels, variant


def compose(seed: int, size: tuple[int, int] = DEFAULT_SIZE, layout: str = "50/30/20",
            min_de: float = DEFAULT_MIN_DE, variant: str | None = None) -> tuple[np.ndarray, list[dict[str, Any]]]:
    """Imagen sRGB8 ``HxWx3`` de tres rectángulos y su verdad (área descendente).

    ``size`` es ``(ancho, alto)`` como en Pillow. ``min_de`` es el ΔE00 mutuo mínimo de
    los colores. ``variant`` fuerza una geometría (por defecto, round-robin por semilla).
    """
    labels, _variant, rgbs, labs = _build(seed, size, layout, min_de, variant)
    palette = np.asarray(rgbs, dtype=np.uint8)
    img = np.ascontiguousarray(palette[labels])
    total = float(labels.size)
    counts = np.bincount(labels.ravel(), minlength=3)
    truth = [
        {"rgb": list(rgbs[i]), "lab": list(labs[i]), "area": float(counts[i]) / total}
        for i in range(3)
    ]
    truth.sort(key=lambda t: -t["area"])
    return img, truth


# --------------------------------------------------------------------------------------
# Transformaciones (tests de invariancia)
# --------------------------------------------------------------------------------------


def shuffle_pixels(img: np.ndarray, seed: int) -> np.ndarray:
    """Permutación aleatoria (determinista por ``seed``) de todos los píxeles."""
    h, w, c = img.shape
    flat = img.reshape(-1, c)
    perm = np.random.default_rng(int(seed)).permutation(h * w)
    return np.ascontiguousarray(flat[perm].reshape(h, w, c))


def scale(img: np.ndarray, factor: float) -> np.ndarray:
    """Escala por un factor entero (vecino más cercano) o 1/entero (promedio de bloque).

    Con 0,5 cada píxel de salida es la media (redondeo, mitades hacia arriba) de un
    bloque 2x2; si la dimensión es impar se descarta la última fila/columna. Con 2,0 cada
    píxel se replica 2x2.
    """
    if factor >= 1.0:
        if abs(factor - round(factor)) > 1e-12:
            raise ValueError("factor >= 1 debe ser entero")
        k = int(round(factor))
        return np.ascontiguousarray(np.repeat(np.repeat(img, k, axis=0), k, axis=1))
    inv = 1.0 / factor
    if abs(inv - round(inv)) > 1e-12:
        raise ValueError("factor < 1 debe ser 1/entero")
    k = int(round(inv))
    h, w, c = img.shape
    h2, w2 = h // k, w // k
    if h2 < 1 or w2 < 1:
        raise ValueError("imagen demasiado pequeña para reducirla")
    blocks = img[:h2 * k, :w2 * k].reshape(h2, k, w2, k, c).astype(np.int64)
    sums = blocks.sum(axis=(1, 3))
    area = k * k
    return np.ascontiguousarray(((sums + area // 2) // area).astype(np.uint8))


def mirror(img: np.ndarray) -> np.ndarray:
    """Espejo horizontal (izquierda <-> derecha)."""
    return np.ascontiguousarray(img[:, ::-1])


def rotate180(img: np.ndarray) -> np.ndarray:
    """Rotación de 180 grados."""
    return np.ascontiguousarray(img[::-1, ::-1])


def add_noise(img: np.ndarray, sigma: float = 2.0, seed: int = 0) -> np.ndarray:
    """Ruido gaussiano por canal (``sigma`` en niveles sRGB8), redondeado y con clamp a 0..255."""
    rng = np.random.default_rng(int(seed))
    noisy = img.astype(np.float64) + rng.normal(0.0, float(sigma), size=img.shape)
    return np.ascontiguousarray(np.clip(np.rint(noisy), 0, 255).astype(np.uint8))


# --------------------------------------------------------------------------------------
# E/S PNM (P6 binario, maxval 255; P5 para máscaras)
# --------------------------------------------------------------------------------------


def write_ppm(img: np.ndarray, path: str | Path) -> Path:
    """Escribe ``img`` (``HxWx3`` uint8) como PPM P6 binario con maxval 255."""
    img = np.ascontiguousarray(img, dtype=np.uint8)
    if img.ndim != 3 or img.shape[2] != 3:
        raise ValueError(f"se esperaba HxWx3, tengo {img.shape}")
    h, w, _ = img.shape
    path = Path(path)
    with path.open("wb") as f:
        f.write(f"P6\n{w} {h}\n255\n".encode("ascii"))
        f.write(img.tobytes())
    return path


def write_pgm(mask: np.ndarray, path: str | Path) -> Path:
    """Escribe ``mask`` (``HxW`` uint8) como PGM P5 binario con maxval 255."""
    mask = np.ascontiguousarray(mask, dtype=np.uint8)
    if mask.ndim != 2:
        raise ValueError(f"se esperaba HxW, tengo {mask.shape}")
    h, w = mask.shape
    path = Path(path)
    with path.open("wb") as f:
        f.write(f"P5\n{w} {h}\n255\n".encode("ascii"))
        f.write(mask.tobytes())
    return path


def read_pnm(path: str | Path) -> np.ndarray:
    """Lee un P6 (-> ``HxWx3``) o P5 (-> ``HxW``) binario con maxval 255."""
    data = Path(path).read_bytes()
    tokens: list[bytes] = []
    pos = 0
    while len(tokens) < 4:
        while pos < len(data) and data[pos:pos + 1].isspace():
            pos += 1
        if pos < len(data) and data[pos:pos + 1] == b"#":
            while pos < len(data) and data[pos:pos + 1] not in (b"\n", b"\r"):
                pos += 1
            continue
        start = pos
        while pos < len(data) and not data[pos:pos + 1].isspace():
            pos += 1
        if start == pos:
            raise ValueError(f"{path}: cabecera PNM truncada")
        tokens.append(data[start:pos])
    pos += 1  # un único byte de espacio tras maxval
    magic, w, h, maxval = tokens[0], int(tokens[1]), int(tokens[2]), int(tokens[3])
    if magic not in (b"P6", b"P5") or maxval != 255 or w < 1 or h < 1:
        raise ValueError(f"{path}: solo P6/P5 con maxval 255 (tengo {magic!r}, {w}x{h}, {maxval})")
    channels = 3 if magic == b"P6" else 1
    body = data[pos:pos + w * h * channels]
    if len(body) != w * h * channels:
        raise ValueError(f"{path}: cuerpo truncado ({len(body)} de {w * h * channels} bytes)")
    arr = np.frombuffer(body, dtype=np.uint8)
    return arr.reshape(h, w, 3).copy() if channels == 3 else arr.reshape(h, w).copy()


def read_ppm(path: str | Path) -> np.ndarray:
    """Lee un PPM P6 (``HxWx3``); error si el fichero es P5."""
    arr = read_pnm(path)
    if arr.ndim != 3:
        raise ValueError(f"{path}: es un P5, no un P6")
    return arr


# --------------------------------------------------------------------------------------
# Oráculo de referencia de la capa 2
# --------------------------------------------------------------------------------------


def lab_to_srgb8(lab) -> np.ndarray:
    """CIELAB (D65) -> sRGB8 con clamp y redondeo (mitades hacia arriba), como ``ce_lab_to_srgb8``."""
    from colour.algebra import vecmul
    from colour.models import Lab_to_XYZ, eotf_inverse_sRGB

    xyz = np.asarray(Lab_to_XYZ(np.asarray(lab, dtype=float), ref.D65_XY), dtype=float)
    lin = np.asarray(vecmul(ref.MATRIX_XYZ_TO_RGB, xyz), dtype=float)
    enc = np.clip(np.asarray(eotf_inverse_sRGB(np.clip(lin, 0.0, 1.0)), dtype=float), 0.0, 1.0)
    return np.floor(enc * 255.0 + 0.5).astype(np.int64)


def palette_reference(img: np.ndarray, k: int = 3, n_init: int = 10, random_state: int = 0) -> list[dict[str, Any]]:
    """KMeans (scikit-learn) en Lab sobre los colores únicos ponderados por frecuencia.

    Devuelve una lista ordenada por peso descendente de ``{"lab", "rgb", "weight"}`` con
    ``sum(weight) == 1``. Invariante al orden de los píxeles (``np.unique`` ordena): pesos y
    rgb idénticos; los centros Lab pueden variar algún ulp entre ejecuciones por la reducción
    paralela de scikit-learn, así que se comparan con tolerancia, nunca bit a bit.
    """
    from sklearn.cluster import KMeans

    px = np.ascontiguousarray(img, dtype=np.uint8).reshape(-1, 3)
    uniq, counts = np.unique(px, axis=0, return_counts=True)
    labs = ref.srgb8_to_lab_strict(uniq)
    k_eff = max(1, min(int(k), len(uniq)))
    km = KMeans(n_clusters=k_eff, n_init=n_init, random_state=random_state)
    assign = km.fit_predict(labs, sample_weight=counts.astype(np.float64))
    total = float(counts.sum())
    out: list[dict[str, Any]] = []
    for j in range(k_eff):
        members = assign == j
        weight = float(counts[members].sum()) / total
        if weight <= 0.0:
            continue
        center = km.cluster_centers_[j]
        out.append({
            "lab": [float(v) for v in center],
            "rgb": [int(v) for v in lab_to_srgb8(center)],
            "weight": weight,
        })
    out.sort(key=lambda s: (-s["weight"], s["lab"]))
    return out
