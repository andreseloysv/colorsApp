"""Generador determinista de imágenes por combinación de Wada (capa 3 del harness).

    from synth import wada_gen as wg
    img, meta = wg.variant(combo_id=12, v=3)             # semilla = 0 + 12*1000 + 3
    wg.generate_set(out_dir, variants=range(10))          # 348 x 10 PPM + manifest.jsonl

Cada imagen (256x256 sRGB8) muestra los colores de una combinación del diccionario
(``data/wada/dictionary.json``) con una degradación controlada. Toda la aleatoriedad sale
de ``numpy.random.default_rng(seed)`` con ``seed = seed_base + combo_id*1000 + v``; el
ruido de textura usa ``opensimplex`` con esa misma semilla. Misma semilla, mismos bytes.

Variantes de desarrollo (``v`` = 0..9; ``seed_base`` = 0):

| v | nombre          | grupo (umbrales) | qué hace                                                      |
|---|-----------------|------------------|---------------------------------------------------------------|
| 0 | clean           | clean            | franjas planas; proporciones aleatorias, cada una en 15..60 % |
| 1 | shapes          | shapes           | rectángulos anidados, L o elipses sobre fondo                 |
| 2 | texture         | texture          | ruido opensimplex en L* (±6)                                  |
| 3 | shading         | shading          | gradiente lineal de L* (±12 %) en dirección aleatoria         |
| 4 | illuminant_A    | illuminant       | Bradford D65 -> A en XYZ lineal (balance de blancos erróneo)  |
| 5 | illuminant_F2   | illuminant       | Bradford D65 -> F2                                            |
| 6 | illuminant_D75  | illuminant       | Bradford D65 -> D75                                           |
| 7 | jpeg            | jpeg_q10/q30     | JPEG (Pillow, 4:2:0) con q = 10 o 30 elegido por semilla      |
| 8 | exposure        | exposure         | ±1 EV en lineal y croma x0,7..1,3 en Lab                      |
| 9 | distractor      | distractor       | 40 % del lienzo (marco o banda) con un color ajeno (ΔE00 > 15)|

Holdout ciego (``v`` = 10 y 11): ``seed_base`` = ``$COLORSAPP_HOLDOUT_SEED`` (solo el
usuario la exporta; ver ``holdout_seed_base``). Cada imagen del holdout sigue **la misma
distribución que el dev**: se elige al azar (con la semilla del usuario) una de las diez
variantes 0..9 y se aplica su plan (layout, degradación y parámetros) con proporciones y
geometría nuevas. Así el gate «holdout ≥ dev − 3 puntos» compara conjuntos comparables y
mide el sobreajuste a las semillas del dev, no la dificultad de una mezcla distinta de
degradaciones (la versión inicial combinaba 1..3 degradaciones por imagen y quedaba
~20 puntos por debajo del dev con cualquier motor). Los metadatos del holdout llevan
``holdout_variant`` (nombre de la variante dev elegida) y ``holdout_degradation`` (su
grupo de umbrales) para desglosarlo, pero su ``degradation`` es ``"holdout"``. **La
semilla nunca se escribe en ningún fichero**: los metadatos del holdout no llevan
``seed`` y su manifest no lleva ``seed_base``.

Las matrices de Bradford salen de ``oracle.reference.bradford_matrix`` (colour-science);
``tests/test_wada_gen.py`` comprueba que reproducen ``engine/tests/data/golden_bradford.tsv``
a 1e-9, así que el generador y el motor usan la misma adaptación.

``generate_set`` escribe ``cNNN_vVV.ppm`` (P6, ``synth.compose.write_ppm``) y
``manifest.jsonl``: primera línea ``{"kind": "meta", ...}`` con ``generator_hash``
(sha256 de este fichero + dict_version + versiones de numpy/Pillow/opensimplex), luego una
línea ``{"kind": "image", ...}`` por imagen con ``combo_id``, ``v``, ``variant``,
``degradation`` (grupo de umbrales), ``params`` y (solo dev) ``seed``.
"""

from __future__ import annotations

import hashlib
import io
import json
import math
import os
from pathlib import Path
from typing import Any

import numpy as np

from oracle import reference as ref
from synth import compose as sc

REPO_ROOT = Path(__file__).resolve().parents[2]
DICTIONARY_PATH = REPO_ROOT / "data" / "wada" / "dictionary.json"

SIZE = 256
N_COMBOS = 348
DEV_VARIANTS: tuple[int, ...] = tuple(range(10))
HOLDOUT_VARIANTS: tuple[int, ...] = (10, 11)
HOLDOUT_SEED_ENV = "COLORSAPP_HOLDOUT_SEED"

VARIANT_NAMES: dict[int, str] = {
    0: "clean", 1: "shapes", 2: "texture", 3: "shading", 4: "illuminant_A",
    5: "illuminant_F2", 6: "illuminant_D75", 7: "jpeg", 8: "exposure", 9: "distractor",
    10: "holdout", 11: "holdout",
}
#: Grupos de degradación tal como los nombra ``harness/thresholds.json`` (L3.by_degradation).
DEGRADATION_GROUPS: tuple[str, ...] = (
    "clean", "shapes", "texture", "shading", "illuminant", "jpeg_q10", "jpeg_q30", "exposure", "distractor",
)
ILLUMINANTS: tuple[str, ...] = ("A", "F2", "D75")
JPEG_Q_DEV: tuple[int, ...] = (10, 30)
#: Orden canónico de aplicación de las degradaciones a nivel de píxel (JPEG siempre la última).
DEGRADATION_ORDER: tuple[str, ...] = ("distractor", "texture", "shading", "illuminant", "exposure", "jpeg")

PROP_MIN, PROP_MAX = 0.15, 0.60
TEXTURE_AMP_L = 6.0
SHADING_AMP = 0.12
DISTRACTOR_AREA = 0.40
DISTRACTOR_MIN_DE = 15.0
L_MIN, L_MAX = 15.0, 90.0


# --------------------------------------------------------------------------------------
# Diccionario
# --------------------------------------------------------------------------------------

_DICT_CACHE: dict[str, Any] | None = None


def load_dictionary(path: Path = DICTIONARY_PATH) -> dict[str, Any]:
    """``dictionary.json`` con el Lab (oráculo estricto) de cada color añadido en ``labs``."""
    global _DICT_CACHE
    if _DICT_CACHE is not None and _DICT_CACHE["_path"] == str(path):
        return _DICT_CACHE
    d = json.loads(Path(path).read_text(encoding="utf-8"))
    rgbs = np.array([c["rgb"] for c in d["colors"]], dtype=np.int64)
    d["rgbs"] = rgbs
    d["labs"] = np.asarray(ref.srgb8_to_lab_strict(rgbs), dtype=float)
    d["combos_by_id"] = {int(c["id"]): c for c in d["combinations"]}
    d["_path"] = str(path)
    _DICT_CACHE = d
    return d


def combo_ids(dictionary: dict[str, Any] | None = None) -> list[int]:
    d = dictionary or load_dictionary()
    return sorted(d["combos_by_id"])


def dict_version(dictionary: dict[str, Any] | None = None) -> str:
    return str((dictionary or load_dictionary())["dict_version"])


def generator_hash(dictionary: dict[str, Any] | None = None) -> str:
    """12 hex: sha256 del código de este módulo + dict_version + versiones que afectan a los bytes."""
    import PIL
    import opensimplex

    h = hashlib.sha256()
    h.update(Path(__file__).read_bytes())
    h.update(dict_version(dictionary).encode("ascii"))
    h.update(f"numpy={np.__version__};pillow={PIL.__version__};opensimplex={opensimplex.__version__}".encode("ascii"))
    return h.hexdigest()[:12]


def seed_for(combo_id: int, v: int, seed_base: int = 0) -> int:
    return int(seed_base) + int(combo_id) * 1000 + int(v)


def holdout_seed_base() -> int | None:
    """``int($COLORSAPP_HOLDOUT_SEED)`` o None si no está definida (holdout => skipped)."""
    raw = os.environ.get(HOLDOUT_SEED_ENV)
    if raw is None or raw.strip() == "":
        return None
    try:
        return int(raw.strip(), 0)
    except ValueError as exc:
        raise ValueError(f"{HOLDOUT_SEED_ENV} debe ser un entero, no {raw!r}") from exc


def is_holdout(v: int) -> bool:
    return int(v) in HOLDOUT_VARIANTS


# --------------------------------------------------------------------------------------
# Conversiones de color vectorizadas (oráculo estricto)
# --------------------------------------------------------------------------------------


def _img_to_lab(img: np.ndarray) -> np.ndarray:
    h, w, _ = img.shape
    return ref.srgb8_to_lab_strict(img.reshape(-1, 3)).reshape(h, w, 3)


def _lab_to_img(lab: np.ndarray) -> np.ndarray:
    h, w, _ = lab.shape
    return np.ascontiguousarray(sc.lab_to_srgb8(lab.reshape(-1, 3)).reshape(h, w, 3).astype(np.uint8))


def _img_to_linear(img: np.ndarray) -> np.ndarray:
    return ref.srgb_to_linear(img.astype(np.float64) / 255.0)


def _linear_to_img(lin: np.ndarray) -> np.ndarray:
    from colour.models import eotf_inverse_sRGB

    enc = np.asarray(eotf_inverse_sRGB(np.clip(lin, 0.0, 1.0)), dtype=float)
    return np.ascontiguousarray(np.floor(np.clip(enc, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8))


# --------------------------------------------------------------------------------------
# Geometría: mapas de etiquetas (índice en la combinación; -1 = distractor)
# --------------------------------------------------------------------------------------


def sample_proportions(rng: np.random.Generator, n: int, lo: float = PROP_MIN, hi: float = PROP_MAX,
                       max_tries: int = 5000) -> np.ndarray:
    """``n`` fracciones que suman 1, cada una en ``[lo, hi]`` (rechazo; si no cabe, iguales)."""
    if n * lo > 1.0 + 1e-12 or n * hi < 1.0 - 1e-12:
        return np.full(n, 1.0 / n)
    for _ in range(max_tries):
        w = rng.uniform(lo, hi, size=n)
        p = w / w.sum()
        if np.all(p >= lo - 1e-12) and np.all(p <= hi + 1e-12):
            return p
    return np.full(n, 1.0 / n)


def _sizes(props: np.ndarray, length: int) -> list[int]:
    sizes = [max(1, int(round(float(p) * length))) for p in props[:-1]]
    rest = length - sum(sizes)
    if rest < 1:  # redondeos: quita del más grande
        deficit = 1 - rest
        i = int(np.argmax(sizes))
        sizes[i] -= deficit
        rest = 1
    sizes.append(rest)
    return sizes


def layout_stripes(rng: np.random.Generator, n: int, props: np.ndarray, w: int, h: int) -> np.ndarray:
    vertical = bool(rng.integers(0, 2))
    order = rng.permutation(n)
    length = w if vertical else h
    sizes = _sizes(props, length)
    labels = np.empty((h, w), dtype=np.int64)
    pos = 0
    for label in order:
        size = sizes[int(label)]
        if vertical:
            labels[:, pos:pos + size] = label
        else:
            labels[pos:pos + size, :] = label
        pos += size
    return labels


def _rect_dims(area: float, aspect: float, max_w: int, max_h: int) -> tuple[int, int]:
    wd = max(1, min(max_w, int(round(math.sqrt(max(area, 1.0) * aspect)))))
    ht = max(1, min(max_h, int(round(area / wd))))
    if ht == max_h:
        wd = max(1, min(max_w, int(round(area / ht))))
    return wd, ht


def layout_nested(rng: np.random.Generator, n: int, props: np.ndarray, w: int, h: int) -> np.ndarray:
    """Fondo + rectángulos anidados: el rectángulo k contiene los colores k..n-1."""
    order = rng.permutation(n)
    labels = np.full((h, w), int(order[0]), dtype=np.int64)
    x0, y0, pw, ph = 0, 0, w, h
    total = w * h
    for k in range(1, n):
        area = float(props[order[k:]].sum()) * total
        rw, rh = _rect_dims(area, float(rng.uniform(0.6, 1.6)), pw, ph)
        x = x0 + int(rng.integers(0, pw - rw + 1))
        y = y0 + int(rng.integers(0, ph - rh + 1))
        labels[y:y + rh, x:x + rw] = int(order[k])
        x0, y0, pw, ph = x, y, rw, rh
    return labels


def layout_l_shape(rng: np.random.Generator, n: int, props: np.ndarray, w: int, h: int) -> np.ndarray:
    """Una L (franja lateral + franja superior) del primer color; el resto en franjas."""
    order = rng.permutation(n)
    total = w * h
    n0 = float(props[order[0]]) * total
    wa = max(1, min(w - 2, int(round(float(rng.uniform(0.15, 0.35)) * w))))
    ha = max(1, min(h - 2, int(round((n0 - wa * h) / (w - wa)))))
    labels = np.full((h, w), int(order[0]), dtype=np.int64)
    rest = props[order[1:]]
    sizes = _sizes(rest / rest.sum(), w - wa)
    pos = wa
    for k, size in enumerate(sizes):
        labels[ha:, pos:pos + size] = int(order[k + 1])
        pos += size
    if rng.integers(0, 2):
        labels = labels[:, ::-1]
    if rng.integers(0, 2):
        labels = labels[::-1, :]
    return np.ascontiguousarray(labels)


def layout_ellipses(rng: np.random.Generator, n: int, props: np.ndarray, w: int, h: int) -> np.ndarray:
    """Fondo (el color de mayor proporción) + una elipse por color restante, con poco solape."""
    order = np.argsort(-props, kind="stable")
    labels = np.full((h, w), int(order[0]), dtype=np.int64)
    yy, xx = np.mgrid[0:h, 0:w]
    total = w * h
    for k in range(1, n):
        area = float(props[order[k]]) * total
        best = None
        for _ in range(12):
            aspect = float(rng.uniform(0.6, 1.6))
            a = math.sqrt(area * aspect / math.pi)
            b = area / (math.pi * a)
            a = min(a, w / 2.0 - 1.0)
            b = min(b, h / 2.0 - 1.0)
            cx = float(rng.uniform(a, w - a))
            cy = float(rng.uniform(b, h - b))
            mask = ((xx - cx) / a) ** 2 + ((yy - cy) / b) ** 2 <= 1.0
            overlap = int(np.count_nonzero(mask & (labels != int(order[0]))))
            if best is None or overlap < best[0]:
                best = (overlap, mask)
            if overlap == 0:
                break
        labels[best[1]] = int(order[k])
    return labels


SHAPE_KINDS: tuple[str, ...] = ("nested", "l_shape", "ellipses")


def layout_shapes(rng: np.random.Generator, n: int, props: np.ndarray, w: int, h: int) -> tuple[np.ndarray, str]:
    kind = SHAPE_KINDS[int(rng.integers(0, len(SHAPE_KINDS)))]
    if kind == "nested":
        return layout_nested(rng, n, props, w, h), kind
    if kind == "l_shape":
        return layout_l_shape(rng, n, props, w, h), kind
    return layout_ellipses(rng, n, props, w, h), kind


# --------------------------------------------------------------------------------------
# Degradaciones (imagen sRGB8 -> imagen sRGB8)
# --------------------------------------------------------------------------------------


def simplex_noise(seed: int, w: int, h: int, feature_px: float = 24.0, coarse: int = 4) -> np.ndarray:
    """Ruido opensimplex ``h x w`` en [-1, 1] muestreado a 1/``coarse`` y ampliado bilinealmente."""
    import opensimplex
    from scipy.ndimage import zoom

    cw, ch = max(2, math.ceil(w / coarse)), max(2, math.ceil(h / coarse))
    gen = opensimplex.OpenSimplex(int(seed))
    x = np.arange(cw) * coarse / feature_px
    y = np.arange(ch) * coarse / feature_px
    small = np.asarray(gen.noise2array(x, y), dtype=float)  # (ch, cw)
    big = zoom(small, (h / ch, w / cw), order=1, mode="nearest", grid_mode=True)
    return np.clip(np.ascontiguousarray(big[:h, :w]), -1.0, 1.0)


def apply_texture(img: np.ndarray, seed: int, amp: float = TEXTURE_AMP_L) -> tuple[np.ndarray, dict[str, Any]]:
    h, w, _ = img.shape
    noise = simplex_noise(seed, w, h)
    peak = float(np.abs(noise).max()) or 1.0
    lab = _img_to_lab(img)
    lab[..., 0] = np.clip(lab[..., 0] + noise * (amp / peak), 0.0, 100.0)
    return _lab_to_img(lab), {"amp_L": amp, "feature_px": 24.0}


def apply_shading(img: np.ndarray, rng: np.random.Generator, amp: float = SHADING_AMP) -> tuple[np.ndarray, dict[str, Any]]:
    h, w, _ = img.shape
    theta = float(rng.uniform(0.0, 2.0 * math.pi))
    yy, xx = np.mgrid[0:h, 0:w]
    t = ((xx - (w - 1) / 2.0) * math.cos(theta) + (yy - (h - 1) / 2.0) * math.sin(theta))
    half = max(abs(float(t.max())), abs(float(t.min())), 1e-9)
    g = amp * (t / half)
    lab = _img_to_lab(img)
    lab[..., 0] = np.clip(lab[..., 0] * (1.0 + g), 0.0, 100.0)
    return _lab_to_img(lab), {"amp": amp, "theta_deg": round(math.degrees(theta), 3)}


def apply_illuminant(img: np.ndarray, name: str) -> tuple[np.ndarray, dict[str, Any]]:
    """sRGB -> XYZ (D65) -> Bradford D65->``name`` -> de vuelta con la matriz sRGB (sin readaptar)."""
    m = ref.bradford_matrix("D65", name)
    lin = _img_to_linear(img)
    xyz = lin @ ref.MATRIX_RGB_TO_XYZ.T
    xyz = xyz @ m.T
    lin2 = xyz @ ref.MATRIX_XYZ_TO_RGB.T
    return _linear_to_img(lin2), {"illuminant": name}


def apply_jpeg(img: np.ndarray, quality: int) -> tuple[np.ndarray, dict[str, Any]]:
    from PIL import Image

    buf = io.BytesIO()
    Image.fromarray(np.ascontiguousarray(img, dtype=np.uint8), "RGB").save(buf, format="JPEG", quality=int(quality))
    out = np.asarray(Image.open(io.BytesIO(buf.getvalue())).convert("RGB"), dtype=np.uint8)
    return np.ascontiguousarray(out), {"quality": int(quality), "bytes": len(buf.getvalue())}


def apply_exposure(img: np.ndarray, ev: float, saturation: float) -> tuple[np.ndarray, dict[str, Any]]:
    lin = _img_to_linear(img) * (2.0 ** float(ev))
    img2 = _linear_to_img(lin)
    lab = _img_to_lab(img2)
    lab[..., 1:] *= float(saturation)
    return _lab_to_img(lab), {"ev": float(ev), "saturation": round(float(saturation), 4)}


def sample_distractor_color(rng: np.random.Generator, combo_labs: np.ndarray, min_de: float = DISTRACTOR_MIN_DE,
                            max_tries: int = 20000) -> tuple[list[int], float]:
    """sRGB8 con 15 <= L <= 90 y ΔE00 > ``min_de`` de todos los colores de la combinación."""
    best: tuple[float, list[int]] | None = None
    for _ in range(max_tries):
        rgb = [int(v) for v in rng.integers(0, 256, size=3)]
        lab = ref.srgb8_to_lab_strict(rgb)
        if not (L_MIN <= float(lab[0]) <= L_MAX):
            continue
        de = float(np.min(ref.de2000(np.repeat(lab[None, :], len(combo_labs), axis=0), combo_labs)))
        if best is None or de > best[0]:
            best = (de, rgb)
        if de > min_de:
            return rgb, de
    assert best is not None
    return best[1], best[0]


def distractor_geometry(rng: np.random.Generator, w: int, h: int, area: float = DISTRACTOR_AREA) -> tuple[str, tuple[int, int, int, int]]:
    """Devuelve (kind, (x0, y0, iw, ih)) del rectángulo interior que queda para la combinación."""
    kind = ("frame", "band")[int(rng.integers(0, 2))]
    if kind == "frame":
        s = math.sqrt(1.0 - area)
        iw, ih = max(8, int(round(w * s))), max(8, int(round(h * s)))
        return kind, ((w - iw) // 2, (h - ih) // 2, iw, ih)
    side = ("left", "right", "top", "bottom")[int(rng.integers(0, 4))]
    if side in ("left", "right"):
        iw = max(8, int(round(w * (1.0 - area))))
        return f"band_{side}", ((w - iw) if side == "left" else 0, 0, iw, h)
    ih = max(8, int(round(h * (1.0 - area))))
    return f"band_{side}", (0, (h - ih) if side == "top" else 0, w, ih)


# --------------------------------------------------------------------------------------
# Composición de una variante
# --------------------------------------------------------------------------------------


def _plan(v: int, rng: np.random.Generator) -> dict[str, Any]:
    """Qué layout y qué degradaciones (con sus parámetros aleatorios) lleva la variante ``v``."""
    v = int(v)
    if v in HOLDOUT_VARIANTS:
        # Misma distribución que el dev: una variante 0..9 al azar (semilla del usuario)
        # con su plan; proporciones, geometría y parámetros se sortean después como en
        # cualquier imagen. Ver la cabecera del módulo (gate holdout >= dev - 3 puntos).
        dev_v = int(DEV_VARIANTS[int(rng.integers(0, len(DEV_VARIANTS)))])
        plan = _plan(dev_v, rng)
        plan["dev_variant"] = dev_v
        return plan
    if v not in VARIANT_NAMES:
        raise ValueError(f"variante desconocida v={v}; válidas 0..11")
    name = VARIANT_NAMES[v]
    plan: dict[str, Any] = {"layout": "shapes" if v == 1 else "stripes", "degradations": []}
    if v == 2:
        plan["degradations"] = ["texture"]
    elif v == 3:
        plan["degradations"] = ["shading"]
    elif v in (4, 5, 6):
        plan["degradations"] = ["illuminant"]
        plan["illuminant"] = name.split("_", 1)[1]
    elif v == 7:
        plan["degradations"] = ["jpeg"]
        plan["jpeg_q"] = int(JPEG_Q_DEV[int(rng.integers(0, len(JPEG_Q_DEV)))])
    elif v == 8:
        plan["degradations"] = ["exposure"]
    elif v == 9:
        plan["degradations"] = ["distractor"]
    return plan


def degradation_group(v: int, params: dict[str, Any]) -> str:
    """Grupo de ``thresholds.json`` L3.by_degradation al que pertenece la imagen."""
    v = int(v)
    if v in HOLDOUT_VARIANTS:
        return "holdout"
    if v in (4, 5, 6):
        return "illuminant"
    if v == 7:
        return f"jpeg_q{int(params['jpeg']['quality'])}"
    return VARIANT_NAMES[v]


def variant(combo_id: int, v: int, seed_base: int = 0, size: int = SIZE,
            dictionary: dict[str, Any] | None = None) -> tuple[np.ndarray, dict[str, Any]]:
    """Imagen ``size x size x 3`` (uint8) de la combinación ``combo_id`` con la variante ``v``.

    ``meta``: combo_id, v, variant, degradation, colors (índices del diccionario), layout,
    proportions (nominales), areas (fracción real de píxeles por color tras la geometría),
    params (por degradación) y ``seed`` solo si ``v`` no es holdout.
    """
    d = dictionary or load_dictionary()
    combo = d["combos_by_id"][int(combo_id)]
    colors = [int(i) for i in combo["colors"]]
    n = len(colors)
    palette = d["rgbs"][colors].astype(np.uint8)
    combo_labs = d["labs"][colors]
    seed = seed_for(combo_id, v, seed_base)
    rng = np.random.default_rng(seed)
    w = h = int(size)

    plan = _plan(v, rng)
    props = sample_proportions(rng, n)
    params: dict[str, Any] = {}

    # Geometría (el distractor reduce el lienzo disponible para la combinación).
    x0, y0, iw, ih = 0, 0, w, h
    distractor: tuple[list[int], float, str] | None = None
    if "distractor" in plan["degradations"]:
        kind, (x0, y0, iw, ih) = distractor_geometry(rng, w, h)
        rgb, de = sample_distractor_color(rng, combo_labs)
        distractor = (rgb, de, kind)
    if plan["layout"] == "stripes":
        inner = layout_stripes(rng, n, props, iw, ih)
        layout_name = "stripes"
    else:
        inner, layout_name = layout_shapes(rng, n, props, iw, ih)
    labels = np.full((h, w), -1, dtype=np.int64)
    labels[y0:y0 + ih, x0:x0 + iw] = inner
    img = np.empty((h, w, 3), dtype=np.uint8)
    img[labels >= 0] = palette[labels[labels >= 0]]
    if distractor is not None:
        rgb, de, kind = distractor
        img[labels < 0] = np.asarray(rgb, dtype=np.uint8)
        params["distractor"] = {"rgb": rgb, "min_de00": round(de, 3), "geometry": kind,
                                "area": float(np.count_nonzero(labels < 0)) / (w * h)}
    counts = np.bincount(labels[labels >= 0].ravel(), minlength=n)
    areas = [float(c) / (w * h) for c in counts]

    # Degradaciones a nivel de píxel, en orden canónico (JPEG siempre la última).
    for name in DEGRADATION_ORDER:
        if name == "distractor" or name not in plan["degradations"]:
            continue
        if name == "texture":
            img, p = apply_texture(img, seed)
        elif name == "shading":
            img, p = apply_shading(img, rng)
        elif name == "illuminant":
            img, p = apply_illuminant(img, plan["illuminant"])
        elif name == "exposure":
            ev = float((-1.0, 1.0)[int(rng.integers(0, 2))])
            sat = float(rng.uniform(0.7, 1.3))
            img, p = apply_exposure(img, ev, sat)
        else:
            img, p = apply_jpeg(img, plan["jpeg_q"])
        params[name] = p

    meta: dict[str, Any] = {
        "combo_id": int(combo_id),
        "v": int(v),
        "variant": VARIANT_NAMES[int(v)],
        "degradation": degradation_group(v, params),
        "degradations": list(plan["degradations"]),
        "colors": colors,
        "layout": layout_name,
        "proportions": [float(p) for p in props],
        "areas": areas,
        "size": [w, h],
        "params": params,
    }
    if is_holdout(v):
        dev_v = int(plan["dev_variant"])
        meta["holdout_variant"] = VARIANT_NAMES[dev_v]
        meta["holdout_degradation"] = degradation_group(dev_v, params)
    else:
        meta["seed"] = seed
    return np.ascontiguousarray(img), meta


# --------------------------------------------------------------------------------------
# Conjuntos y manifest
# --------------------------------------------------------------------------------------


def image_name(combo_id: int, v: int) -> str:
    return f"c{int(combo_id):03d}_v{int(v):02d}.ppm"


def generate_set(out_dir: str | Path, variants, combos=None, seed_base: int | None = 0, size: int = SIZE,
                 log=None) -> Path:
    """Escribe los PPM de ``combos`` x ``variants`` en ``out_dir`` y devuelve la ruta del manifest.

    Si alguna variante es de holdout, ``seed_base`` es obligatorio (la semilla del usuario) y
    ni las filas ni la cabecera del manifest la incluyen. Determinista: misma semilla, mismos
    bytes en los PPM y en el manifest (las filas van en orden de combo y variante).
    """
    d = load_dictionary()
    variants = [int(v) for v in variants]
    combos = [int(c) for c in (combos if combos is not None else combo_ids(d))]
    holdout = any(is_holdout(v) for v in variants)
    if holdout and seed_base is None:
        raise ValueError(f"las variantes de holdout {HOLDOUT_VARIANTS} exigen seed_base ({HOLDOUT_SEED_ENV})")
    if seed_base is None:
        seed_base = 0
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    meta_line: dict[str, Any] = {
        "kind": "meta",
        "generator": "synth.wada_gen",
        "generator_hash": generator_hash(d),
        "dict_version": dict_version(d),
        "size": int(size),
        "variants": variants,
        "combos": combos if len(combos) != len(d["combos_by_id"]) else "all",
        "n_combos": len(combos),
        "n_images": len(combos) * len(variants),
        "holdout": holdout,
    }
    if not holdout:
        meta_line["seed_base"] = int(seed_base)
    rows: list[str] = [json.dumps(meta_line, ensure_ascii=False, sort_keys=True)]
    for i, combo_id in enumerate(combos):
        for v in variants:
            img, meta = variant(combo_id, v, seed_base=int(seed_base), size=size, dictionary=d)
            name = image_name(combo_id, v)
            sc.write_ppm(img, out / name)
            row = {"kind": "image", "file": name, **meta}
            rows.append(json.dumps(row, ensure_ascii=False, sort_keys=True))
        if log is not None and (i + 1) % 50 == 0:
            log(f"  wada_gen: {i + 1}/{len(combos)} combinaciones ({len(variants)} variantes)")
    manifest = out / "manifest.jsonl"
    manifest.write_text("\n".join(rows) + "\n", encoding="utf-8")
    return manifest


def read_manifest(path: str | Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """(meta, filas de imagen) de un ``manifest.jsonl``."""
    meta: dict[str, Any] = {}
    rows: list[dict[str, Any]] = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        obj = json.loads(line)
        if obj.get("kind") == "meta":
            meta = obj
        elif obj.get("kind") == "image":
            rows.append(obj)
    return meta, rows


def set_is_current(out_dir: str | Path, variants, combos=None, size: int = SIZE) -> bool:
    """True si ``out_dir/manifest.jsonl`` fue generado con este código/diccionario y sus PPM existen."""
    out = Path(out_dir)
    manifest = out / "manifest.jsonl"
    if not manifest.is_file():
        return False
    try:
        meta, rows = read_manifest(manifest)
    except (OSError, ValueError):
        return False
    d = load_dictionary()
    variants = [int(v) for v in variants]
    combos = [int(c) for c in (combos if combos is not None else combo_ids(d))]
    expected_combos: Any = combos if len(combos) != len(d["combos_by_id"]) else "all"
    if meta.get("generator_hash") != generator_hash(d) or meta.get("dict_version") != dict_version(d):
        return False
    if meta.get("variants") != variants or meta.get("combos") != expected_combos or meta.get("size") != int(size):
        return False
    if len(rows) != len(combos) * len(variants):
        return False
    return all((out / r["file"]).is_file() for r in rows)


def main(argv: list[str] | None = None) -> int:
    import argparse

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, required=True, help="directorio de salida (PPM + manifest.jsonl)")
    ap.add_argument("--variants", type=str, default="0-9", help="p. ej. 0-9, 0,3,7 o 10-11 (holdout)")
    ap.add_argument("--combos", type=str, default=None, help="ids separados por coma o rango a-b (por defecto las 348)")
    ap.add_argument("--seed-base", type=int, default=None, help="seed_base (dev: 0; holdout: por defecto $COLORSAPP_HOLDOUT_SEED)")
    ap.add_argument("--size", type=int, default=SIZE)
    args = ap.parse_args(argv)

    def parse_ids(text: str) -> list[int]:
        ids: list[int] = []
        for part in text.split(","):
            part = part.strip()
            if "-" in part:
                a, b = part.split("-", 1)
                ids += list(range(int(a), int(b) + 1))
            elif part:
                ids.append(int(part))
        return ids

    variants = parse_ids(args.variants)
    combos = parse_ids(args.combos) if args.combos else None
    seed_base = args.seed_base
    if seed_base is None:
        seed_base = holdout_seed_base() if any(is_holdout(v) for v in variants) else 0
    if seed_base is None:
        print(f"wada_gen: las variantes de holdout exigen {HOLDOUT_SEED_ENV} o --seed-base", file=os.sys.stderr)
        return 2
    manifest = generate_set(args.out, variants, combos, seed_base=seed_base, size=args.size, log=print)
    _meta, rows = read_manifest(manifest)
    print(f"wada_gen: {len(rows)} imágenes en {args.out} (manifest {manifest.name}, generator_hash {generator_hash()})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
