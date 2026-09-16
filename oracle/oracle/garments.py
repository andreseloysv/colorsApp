"""Paleta por prenda (``ce garments`` / ``ce batch --garments``): composiciones sombreadas,
métricas, barrido de calibración y bloque «prendas» de la capa 2.

    uv run --project oracle python -m oracle.garments [--cli build/tools/ce] [--out harness/out] [--n 170]
    uv run --project oracle python -m oracle.garments sweep [--cli ...] [--out ...] [--people]

Motivo (CONTEXT §13): en una foto real el mismo pantalón rosa palo salía como cuatro colores
(luz, sombra y pliegues). El motor calcula ahora la paleta por región de prenda, agrupa los
tonos del mismo color con distinta luz y representa cada grupo con su tono iluminado
(``ce_palette_extract_garments``). Este módulo lo mide con composiciones sintéticas cuya
verdad se conoce: una figura (torso = región 1, dos piernas = región 2, máscara 0 fuera) sobre
un fondo texturado, cada pieza sombreada en luz lineal como un cilindro lambertiano
(factor 0,45-1,0 a lo ancho), con pliegues oscuros (factor 0,55-0,7), brillos especulares
(0-3 % de la pieza, mezcla hacia el blanco) y ruido gaussiano sigma 1,5. Cuatro familias
(deterministas, ``numpy.random.default_rng(seed)``):

- ``liso``: torso de un color y piernas de otro (ΔE00 >= 20). El caso 0 es el de la foto del
  usuario: camiseta #2b2c2c y pantalón #ddc0c8.
- ``rayas``: torso bicolor (ΔE00 >= 25) y piernas de un tercero (ΔE00 >= 20 a los dos): la mitad
  rayas de 8-16 px y la otra mitad un estampado de motivos claros de 6-12 px sobre fondo oscuro
  (~35 % del área), siempre con los bordes desenfocados en luz lineal (caja de radio 1 px), que
  crea los tonos intermedios que unen los dos colores por transitividad en las fotos reales
  (vestido azul marino con estampado blanco de harness/people/02). El motor reduce a la mitad:
  motivos más finos que el desenfoque ya no contienen los colores puros.
- ``vestido``: el mismo color arriba y abajo (vestido o mono): debe fusionarse en la región 3.
- ``sombra_fuerte``: como ``liso`` pero una de las dos prendas tiene sombras duras y discretas
  (bandas verticales con factor 1,0 / 0,7 / 0,45 / 0,28 y, en la más oscura, tono +15° y croma
  ×0,85 por la luz rebotada), como el pantalón de la foto real, cuyos cuatro tonos iban de L* 40
  a 77: debe seguir saliendo un color.
- ``sombra_proyectada``: como ``liso``, pero una de las dos prendas lleva una SOMBRA PROYECTADA
  CONTIGUA sobre el 40-60 % de su alto (borde recto con pendiente suave y penumbra de 0-3 px) que
  quita 2-4,5 pasos de luz lineal, encima del lambertiano y los pliegues. Es la sombra de sol contra
  sombra abierta en exteriores, la que el verificador midió como el fallo mayor: el grupo de sombra
  salía como un segundo color falso en la prenda lisa. Debe seguir saliendo un color por prenda.
- ``tono_cercano``: dos prendas distintas de tono cercano (camiseta azul marino y vaquero, gris
  oscuro y gris medio...): el color de abajo es el de arriba con ΔL* ±8-20, croma ×0,8-1,2 y
  tono ±10°, con ΔE00 real entre 8 y 18. No deben fusionarse. El primer caso es el par
  #1f2a44 / #3d5b7d.
- ``sombra_cielo`` (NUEVA, ADR-011 segunda vuelta; REFORZADA en la tercera): como ``liso``, pero una
  prenda tiene una SOMBRA ABIERTA DE EXTERIOR sobre el 55-70 % de su alto: al sol recibe sol + cielo
  y en la sombra solo el cielo, así que la sombra **no es una escala de la luz: se azulea**
  (``sky_shadow_gain``, ganancias por canal derivadas de los iluminantes CIE de luz día, 2-3,3 pasos
  = fracción de cielo 0,10-0,25). La PENUMBRA es ancha (6-18 px sobre ~140, y en un tercio de los
  casos la transición es CONTINUA de arriba abajo, sin borde): sin tonos intermedios el gate NO veía
  el fallo que el verificador medía con su propio generador. Es el fallo de ``harness/people/06`` y
  el requisito literal del usuario: debe salir UN color.
- ``estampado_sombra`` (NUEVA): fondo oscuro + motivo claro desenfocado con esa misma sombra encima,
  así que el motivo EN SOMBRA tiene la luminancia del fondo AL SOL (el encadenado de
  ``harness/people/02``). Los dos colores no pueden ser un par tonal (eso lo mide ``bicolor_tonal``):
  se exige ΔE00 >= 8 al modelo escalado. Deben salir los dos colores.
- ``degradado_color`` (NUEVA): degradado continuo entre tres tintes separados en tono (tie-dye). No
  puede colapsar a un solo color; se esperan 2 colores en la región del degradado (el tono iluminado
  de cada grupo cae DENTRO del degradado, así que no se compara con ningún color verdadero).
- ``bicolor_tonal`` (NUEVA, INFORMATIVA; AMPLIADA en la tercera vuelta): rayas de un tinte y su
  PROPIA SOMBRA. La mitad de los casos con el modelo (1) (escala pura, ΔE00 real 10/20/30/45) y la
  otra mitad con el modelo (2) (el mismo tinte bajo el CIELO azul, 1,5-3 pasos). Los dos modelos de
  sombra unen esos pares y sale un solo color: es el límite conocido y documentado (ADR-011),
  medido pero fuera de los gates. Las familias de gate (``rayas``, ``estampado_sombra``) rechazan a
  propósito los pares que ``same_material_residual`` marca como ambiguos, para medir lo que dicen
  medir y no el límite conocido.
- ``banda_fusion`` (NUEVA, INFORMATIVA): dos prendas distintas a ΔE00 REAL 5, 6, 6,5, 7 y 8 para
  medir la banda en la que la fusión a «prenda entera» depende de la luz y la textura (la promesa de
  ce.h es sobre TONOS ILUMINADOS ESTIMADOS, no sobre el color verdadero).

Métricas por composición (región esperada -> colores devueltos con esa región):

- ``colors_ok``: número de colores exacto por prenda (liso y tono_cercano 1 + 1; rayas 2 + 1;
  vestido 1 en la región 3) y sin región 3 donde no toca.
- ``lit_de``: ΔE00 de cada color verdadero (el color base sin sombra) a su swatch emparejado
  (Hungarian dentro de la región).
- ``wrong_fusion``: liso, rayas o tono_cercano con alguna región 3 (prendas distintas fusionadas);
  ``stripes_merged``: rayas con un solo color arriba; ``missed_fusion``: vestido sin región 3.

Umbrales del bloque (sección ``L2.garments`` de ``harness/thresholds.json``; mientras el
usuario no los promueva se usan ``DEFAULTS``, propuestos en ``harness/out/thresholds.proposed.json``).
"""

from __future__ import annotations

import argparse
import itertools
import json
import math
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
from scipy.optimize import linear_sum_assignment

from oracle import reference as ref
from synth import compose as sc

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "harness" / "out"
PEOPLE_DIR = REPO_ROOT / "harness" / "people"
PEOPLE_MASKS_DIR = REPO_ROOT / "harness" / "out" / "people-masks"

SEED = 20260916
N_CASES = 170
SIZE = (160, 320)  # (ancho, alto)
KINDS: tuple[str, ...] = ("liso", "rayas", "vestido", "tono_cercano", "sombra_fuerte", "sombra_proyectada",
                          "sombra_cielo", "estampado_sombra", "degradado_color", "bicolor_tonal", "banda_fusion")
#: Familias informativas: miden un LÍMITE CONOCIDO y documentado del motor (ADR-011), no entran en los
#: gates de ``colors_ok_rate`` ni de ``lit_de00_p90``; sus cifras se publican aparte.
INFORMATIVE_KINDS: tuple[str, ...] = ("bicolor_tonal", "banda_fusion")
#: Familias sobre las que se calibró ``lit_de00_p90_max``: el ΔE00 al tono iluminado VERDADERO solo
#: tiene sentido cuando la prenda está mayormente iluminada. Las familias con media prenda en sombra
#: profunda o cromática (y el degradado, cuyo tono cae DENTRO del degradado) sesgan el tono a propósito
#: —está documentado en ce.h y en ADR-011—: sus ΔE00 se publican aparte (``lit_de00_new_families``).
LIT_DE_KINDS: tuple[str, ...] = ("liso", "rayas", "vestido", "tono_cercano", "sombra_fuerte",
                                 "sombra_proyectada")
#: Reparto de las 170 composiciones por familia (el resto de n se reparte igual). Las familias nuevas
#: van al final para que las anteriores conserven sus índices, semillas y bytes.
KIND_SHARES: dict[str, int] = {"liso": 25, "rayas": 20, "vestido": 15, "tono_cercano": 25, "sombra_fuerte": 15,
                               "sombra_proyectada": 15, "sombra_cielo": 15, "estampado_sombra": 10,
                               "degradado_color": 10, "bicolor_tonal": 10, "banda_fusion": 10}
PINK_PANTS = {"top": (0x2B, 0x2C, 0x2C), "bottom": (0xDD, 0xC0, 0xC8)}
#: Vestido azul marino con estampado blanco desenfocado de test_garment (caso de harness/people/02).
PRINT_DRESS = ((0x14, 0x1A, 0x2C), (0xEC, 0xEB, 0xE6))
NAVY_DENIM = {"top": (0x1F, 0x2A, 0x44), "bottom": (0x3D, 0x5B, 0x7D)}
NOISE_SIGMA = 1.5

#: Umbrales por defecto del bloque (propuestos; ver harness/out/thresholds.proposed.json).
DEFAULTS: dict[str, Any] = {
    "cases": 170,
    "colors_ok_rate_min": 0.95,
    "lit_de00_p90_max": 4.0,
    "wrong_fusions_max": 0,
    "missed_fusion_rate_max": 0.05,
    "cast_shadow_split_max": 0,
    "close_pairs_over_threshold_min": 20,
    "sky_shadow_split_max": 0,
    "print_shadow_lost_max": 1,
    "gradient_collapsed_max": 0,
}

#: Opciones de prenda por defecto del motor (``ce_garment_opts_default``) para validar ``opts``.
ENGINE_DEFAULT_GARMENT_OPTS: dict[str, float] = {
    "shade_kL": 3.0, "shade_merge_de": 6.5, "lit_low_pct": 0.75, "lit_high_pct": 0.95,
    "secondary_min_share": 0.25, "max_colors_per_region": 2,
}

#: Constantes de ce.h que fija este trabajo (se comprueban en oracle/tests/test_garments.py).
ENGINE_SHADE_CONSTANTS: dict[str, float] = {
    "CE_GARMENT_SHADE_S_MIN": 0.04, "CE_GARMENT_SHADE_LIT_DE": 3.0, "CE_GARMENT_SKY_W_MAX": 1.15,
    "CE_GARMENT_SKY_W_SLOPE": 0.54, "CE_GARMENT_GRADIENT_MIN_SHARE": 0.10,
    "CE_GARMENT_GRADIENT_HUE_DE": 12.0, "CE_GARMENT_GRADIENT_MIX_FRACTION": 0.25,
    "CE_GARMENT_LIT_CORE_FRACTION": 0.35, "CE_GARMENT_LIT_Y_RATIO": 0.5,
}

#: Temperaturas de la sombra abierta de exterior: el cielo azul sobre el blanco de escena al que
#: la cámara ya balanceó (sol + cielo). Con ellas se derivan las ganancias por canal de
#: ``sky_shadow_gain`` y la matriz CE_GARMENT_SKY_M del motor (en conos de Bradford).
SKY_CCT_K = 12000.0
SCENE_CCT_K = 5500.0


class GarmentError(RuntimeError):
    """``ce garments`` o ``ce batch --garments`` fallaron o devolvieron algo que no es JSON."""


# --------------------------------------------------------------------------------------
# Color
# --------------------------------------------------------------------------------------


def srgb8_to_linear(rgb8: np.ndarray) -> np.ndarray:
    c = np.asarray(rgb8, dtype=np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb8(lin: np.ndarray) -> np.ndarray:
    lin = np.clip(np.asarray(lin, dtype=np.float64), 0.0, 1.0)
    enc = np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * np.power(lin, 1.0 / 2.4) - 0.055)
    return np.floor(np.clip(enc, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def lab_of(rgb8) -> np.ndarray:
    return np.asarray(ref.srgb8_to_lab_strict(np.asarray(rgb8, dtype=np.int64)), dtype=float)


def de00(a, b, kL: float = 1.0) -> float:
    return float(ref.de2000(np.asarray(a, dtype=float), np.asarray(b, dtype=float), kL=kL))


def _lch_to_rgb8(L: float, C: float, h_deg: float) -> tuple[int, int, int]:
    h = math.radians(h_deg)
    lab = np.array([L, C * math.cos(h), C * math.sin(h)])
    return tuple(int(v) for v in sc.lab_to_srgb8(lab))  # type: ignore[return-value]


def _random_color(rng: np.random.Generator, L: tuple[float, float] = (15.0, 90.0),
                  C: tuple[float, float] = (0.0, 55.0)) -> tuple[int, int, int]:
    return _lch_to_rgb8(float(rng.uniform(*L)), float(rng.uniform(*C)), float(rng.uniform(0.0, 360.0)))


def _distinct(rng: np.random.Generator, others: list[tuple[int, int, int]], min_de: float,
              **kw: Any) -> tuple[int, int, int]:
    for _ in range(10000):
        c = _random_color(rng, **kw)
        lab = lab_of(c)
        if all(de00(lab, lab_of(o)) >= min_de for o in others):
            return c
    raise RuntimeError(f"no encontré un color a ΔE00 >= {min_de}")


def _pair_at_de(rng: np.random.Generator, top: tuple[int, int, int], target: float,
                tol: float = 0.25) -> tuple[tuple[int, int, int], float]:
    """Otra prenda a ΔE00 REAL ``target`` ± ``tol`` del color de arriba (familia ``banda_fusion``)."""
    lab = lab_of(top)
    C = math.hypot(lab[1], lab[2])
    h = math.degrees(math.atan2(lab[2], lab[1]))
    best, best_err = None, 1e9
    for _ in range(20000):
        cand = _lch_to_rgb8(lab[0] + float(rng.uniform(-target, target)) * 1.5,
                            max(0.0, C * float(rng.uniform(0.85, 1.15))), h + float(rng.uniform(-12.0, 12.0)))
        d = de00(lab, lab_of(cand))
        if abs(d - target) < best_err:
            best, best_err = (cand, d), abs(d - target)
        if best_err <= tol:
            break
    assert best is not None
    return best


def close_tone(rng: np.random.Generator, top: tuple[int, int, int]) -> tuple[tuple[int, int, int], float]:
    """Prenda distinta de tono cercano: ΔL* ±8-20, croma ×0,8-1,2, tono ±10°, ΔE00 real en [8, 18]."""
    lab = lab_of(top)
    C = math.hypot(lab[1], lab[2])
    h = math.degrees(math.atan2(lab[2], lab[1]))
    for _ in range(10000):
        dL = float(rng.uniform(8.0, 20.0)) * (1.0 if rng.random() < 0.5 else -1.0)
        L2 = lab[0] + dL
        if not (8.0 <= L2 <= 92.0):
            continue
        c2 = _lch_to_rgb8(L2, C * float(rng.uniform(0.8, 1.2)), h + float(rng.uniform(-10.0, 10.0)))
        d = de00(lab, lab_of(c2))
        if 8.0 <= d <= 18.0:
            return c2, d
    raise RuntimeError("no encontré un tono cercano con ΔE00 en [8, 18]")


# --------------------------------------------------------------------------------------
# Sombreado y figura
# --------------------------------------------------------------------------------------


def shade_factor(h: int, w: int, rng: np.random.Generator, *, light_x: float, ambient: float = 0.45,
                 folds: int = 0, fold_factor: float = 0.55) -> tuple[np.ndarray, np.ndarray]:
    """Factor lambertiano (cilindro vertical, luz ``(light_x, 0, 1)``) en [ambient, 1] a lo ancho,
    multiplicado por ``folds`` bandas horizontales de 2-4 filas con ``fold_factor``. Devuelve
    (factor HxW, perfil lambertiano por columna)."""
    u = (np.arange(w, dtype=np.float64) + 0.5) / w * 2.0 - 1.0
    nz = np.sqrt(np.clip(1.0 - u * u, 0.0, 1.0))
    norm = math.hypot(light_x, 1.0)
    lamb = np.clip((u * light_x + nz) / norm, 0.0, 1.0)
    prof = ambient + (1.0 - ambient) * lamb
    f = np.tile(prof, (h, 1))
    for _ in range(folds):
        t = int(rng.integers(2, 5))
        y = int(rng.integers(0, max(1, h - t)))
        f[y:y + t, :] *= fold_factor
    return f, lamb


def hard_shadow_piece(color: tuple[int, int, int], h: int, w: int, rng: np.random.Generator, *,
                      light_x: float) -> np.ndarray:
    """Pieza con sombras duras: 3-5 bandas verticales de anchura aleatoria con factor 1,0 / 0,7 /
    0,45 / 0,28 (la primera banda siempre iluminada); en las de factor 0,28 el color base gira
    +15° de tono y pierde un 15 % de croma (luz rebotada). Lambertiano suave y 2-5 pliegues encima."""
    lab = lab_of(color)
    C = math.hypot(lab[1], lab[2])
    hue = math.degrees(math.atan2(lab[2], lab[1]))
    deep = np.array(_lch_to_rgb8(float(lab[0]), C * 0.85, hue + 15.0), dtype=np.uint8)
    n_bands = int(rng.integers(3, 6))
    cuts = np.sort(rng.choice(np.arange(2, w - 1), size=n_bands - 1, replace=False))
    edges = [0, *cuts.tolist(), w]
    factors = [1.0] + [float(rng.choice([1.0, 0.7, 0.45, 0.28])) for _ in range(n_bands - 1)]
    base = np.empty((h, w, 3), dtype=np.uint8)
    fband = np.ones(w)
    for k in range(n_bands):
        base[:, edges[k]:edges[k + 1]] = deep if factors[k] == 0.28 else np.array(color, dtype=np.uint8)
        fband[edges[k]:edges[k + 1]] = factors[k]
    f, _lamb = shade_factor(h, w, rng, light_x=light_x, ambient=0.75, folds=int(rng.integers(2, 6)),
                            fold_factor=float(rng.uniform(0.55, 0.7)))
    return linear_to_srgb8(srgb8_to_linear(base) * (f * fband[None, :])[..., None])


def projected_shadow_piece(color: tuple[int, int, int], h: int, w: int, rng: np.random.Generator, *,
                           light_x: float) -> tuple[np.ndarray, float, float]:
    """Pieza lisa con una SOMBRA PROYECTADA CONTIGUA: primero el lambertiano, los pliegues y el
    especular de ``shade_piece``; encima, un borde recto de pendiente ±0,35 a una altura del 40-60 %
    con penumbra de 0-3 px que quita 2-4,5 pasos de luz lineal (factor 2^-pasos). Devuelve
    (pieza, pasos, fracción sombreada)."""
    base = np.empty((h, w, 3), dtype=np.uint8)
    base[:] = color
    piece = shade_piece(base, rng, light_x=light_x, folds=int(rng.integers(3, 7)),
                        fold_factor=float(rng.uniform(0.55, 0.7)), specular=float(rng.uniform(0.0, 0.03)),
                        ambient=float(rng.uniform(0.6, 0.8)))
    stops = float(rng.uniform(2.0, 4.5))
    frac = float(rng.uniform(0.4, 0.6))
    slope = float(rng.uniform(-0.35, 0.35))
    penumbra = int(rng.integers(0, 4))
    yy, xx = np.mgrid[0:h, 0:w]
    edge = (1.0 - frac) * h + slope * (xx - 0.5 * w)
    t = np.clip((yy - edge) / penumbra, 0.0, 1.0) if penumbra > 0 else (yy > edge).astype(np.float64)
    f = 1.0 - (1.0 - 2.0 ** (-stops)) * t
    return linear_to_srgb8(srgb8_to_linear(piece) * f[..., None]), stops, frac


def scaled_model_residual(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    """ΔE00 del color más oscuro al más claro ESCALADO en XYZ lineal (mínimos cuadrados).

    Es el estadístico del modelo (1) de ``ce_garment_same_material``: por debajo de
    ``CE_GARMENT_SHADE_LIT_DE`` (3) el motor considera que son el mismo tejido con distinta luz
    (límite conocido, ADR-011). Sirve para separar las familias: ``bicolor_tonal`` lo busca bajo,
    ``estampado_sombra`` lo exige alto para medir el encadenado y no el límite conocido."""
    xa = ref.lab_to_xyz(lab_of(a)) if hasattr(ref, "lab_to_xyz") else None
    if xa is None:  # sin helper en el oráculo: XYZ desde sRGB lineal con la matriz de sRGB
        m = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750],
                      [0.0193339, 0.1191920, 0.9503041]])
        xa = m @ srgb8_to_linear(np.array(a, dtype=np.uint8))
        xb = m @ srgb8_to_linear(np.array(b, dtype=np.uint8))
    else:
        xb = ref.lab_to_xyz(lab_of(b))
    lo, hi = (xa, xb) if xa[1] <= xb[1] else (xb, xa)
    denom = float(hi @ hi)
    if denom <= 0.0:
        return float("inf")
    s = float(lo @ hi) / denom
    m = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
    model = s * hi
    rgb = np.clip(np.linalg.inv(m) @ model, 0.0, 1.0)
    lo_rgb = np.clip(np.linalg.inv(m) @ lo, 0.0, 1.0)
    return de00(lab_of(tuple(int(v) for v in linear_to_srgb8(lo_rgb))),
                lab_of(tuple(int(v) for v in linear_to_srgb8(rgb))))


def sky_shadow_gain(stops: float, sky_cct: float = SKY_CCT_K, scene_cct: float = SCENE_CCT_K) -> np.ndarray:
    """Ganancias por canal en luz lineal sRGB de una SOMBRA ABIERTA de exterior (la prenda pasa de
    sol + cielo a solo cielo), normalizadas a luminancia ``2**-stops``.

    Es el modelo FÍSICO con el que se generan las composiciones y el test Unity (f1), derivado con
    colour-science en un espacio DISTINTO (diagonal en sRGB lineal) del que usa el motor (diagonal en
    conos de Bradford, ``CE_GARMENT_SKY_M``): el test no es tautológico.
    """
    import colour

    def rgb_lin(cct: float) -> np.ndarray:
        xyz = colour.xy_to_XYZ(colour.temperature.CCT_to_xy_CIE_D(cct))
        xyz = xyz / xyz[1]
        return np.asarray(colour.XYZ_to_sRGB(xyz, apply_cctf_encoding=False), dtype=float)

    g = rgb_lin(sky_cct) / rgb_lin(scene_cct)
    y = float(np.dot(g, np.array([0.2126729, 0.7151522, 0.0721750])))
    return g * (2.0 ** -stops) / y


def sky_matrix(sky_cct: float = SKY_CCT_K, scene_cct: float = SCENE_CCT_K) -> np.ndarray:
    """``S = M⁻¹·diag(g−1)·M`` (Bradford) del motor: la dirección del azuleo de la sombra en XYZ."""
    import colour

    M = np.array([[0.8951, 0.2664, -0.1614], [-0.7502, 1.7135, 0.0367], [0.0389, -0.0685, 1.0296]])

    def white(cct: float) -> np.ndarray:
        xyz = colour.xy_to_XYZ(colour.temperature.CCT_to_xy_CIE_D(cct))
        return xyz / xyz[1]

    g = (M @ white(sky_cct)) / (M @ white(scene_cct))
    g = g / g[1]
    return np.linalg.inv(M) @ np.diag(g - 1.0) @ M


def sky_model_residual(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    """ΔE00 del más oscuro al más claro bajo el MODELO (2) de ``ce_garment_same_material`` (sombra
    abierta de exterior: ``c ≈ s·(a + w·S·a)`` con ``(s, s·w)`` de mínimos cuadrados). ``inf`` si el
    ajuste sale fuera de los límites físicos que exige el motor (``s`` en [0,04, 1] y
    ``0 <= w <= min(1,15, 0,54·(1−s)/s)``), es decir, si el motor NO puede tomarlos por el mismo
    tejido. Junto con ``scaled_model_residual`` (modelo 1) dice si un par es AMBIGUO para el motor."""
    m = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
    xa = m @ srgb8_to_linear(np.array(a, dtype=np.uint8))
    xb = m @ srgb8_to_linear(np.array(b, dtype=np.uint8))
    lo, hi = (xa, xb) if xa[1] <= xb[1] else (xb, xa)
    u = sky_matrix() @ hi
    aa, au, uu = float(hi @ hi), float(hi @ u), float(u @ u)
    ca, cu = float(lo @ hi), float(lo @ u)
    det = aa * uu - au * au
    if det <= 0.0:
        return float("inf")
    sc = (ca * uu - cu * au) / det
    alpha = (aa * cu - au * ca) / det
    if not (0.04 <= sc <= 1.0):
        return float("inf")
    w = alpha / sc
    wmax = min(0.54 * (1.0 - sc) / sc, 1.15)
    if not (0.0 <= w <= wmax):
        return float("inf")
    model = sc * hi + alpha * u
    if not (model > 0.0).all():
        return float("inf")
    inv = np.linalg.inv(m)
    lo_rgb = np.clip(inv @ lo, 0.0, 1.0)
    md_rgb = np.clip(inv @ model, 0.0, 1.0)
    return de00(lab_of(tuple(int(v) for v in linear_to_srgb8(lo_rgb))),
                lab_of(tuple(int(v) for v in linear_to_srgb8(md_rgb))))


def same_material_residual(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    """El menor de los residuos de los DOS modelos de sombra del motor. Por debajo de
    ``CE_GARMENT_SHADE_LIT_DE`` (3) el motor une el par y devuelve un solo color: es el límite
    conocido de ADR-011, que la familia informativa ``bicolor_tonal`` mide a propósito y que las
    familias de gate evitan (si no, medirían el límite conocido en vez de lo que dicen medir)."""
    return min(scaled_model_residual(a, b), sky_model_residual(a, b))


def sky_shadow_piece(color: tuple[int, int, int], h: int, w: int, rng: np.random.Generator, *,
                     light_x: float, smooth: bool = False) -> tuple[np.ndarray, float, float]:
    """Pieza lisa con SOMBRA ABIERTA DE EXTERIOR sobre el 55-70 % de su alto: la sombra no es una
    escala de la luz, se azulea (``sky_shadow_gain``, 2-3,3 pasos). Es el fallo de harness/people/06
    y el requisito literal del usuario (CONTEXT §13, "el pantalón es de un solo color").

    La PENUMBRA es ancha a propósito (6-18 px sobre una pieza de ~140 px de alto, un 4-13 %): una
    oclusión PARCIAL es una combinación lineal de los dos iluminantes, así que sus tonos caen sobre
    el segmento entre el tono al sol y el tono en sombra y forman SU PROPIO cluster. Con la penumbra
    de 0-3 px de la primera versión no había tonos intermedios, el motor no llegaba a tomarlos por
    una MEZCLA y el gate no veía el fallo que el verificador sí medía con su generador
    (32 escenas de 32 con dos colores). Con ``smooth`` la transición es CONTINUA de arriba abajo
    (lambertiano entre luz y sombra, sin borde recto), que es el caso más difícil.

    Devuelve (pieza, pasos, fracción sombreada)."""
    base = np.empty((h, w, 3), dtype=np.uint8)
    base[:] = color
    piece = shade_piece(base, rng, light_x=light_x, folds=int(rng.integers(3, 7)),
                        fold_factor=float(rng.uniform(0.55, 0.7)), specular=float(rng.uniform(0.0, 0.03)),
                        ambient=float(rng.uniform(0.6, 0.8)))
    stops = float(rng.uniform(2.0, 3.3))
    frac = float(rng.uniform(0.55, 0.7))
    slope = float(rng.uniform(-0.35, 0.35))
    penumbra = int(rng.integers(6, 19))
    gain = sky_shadow_gain(stops) / (2.0 ** -stops) * (2.0 ** -stops)
    yy, xx = np.mgrid[0:h, 0:w]
    if smooth:
        t = np.clip((yy / max(h - 1, 1) - (1.0 - frac) * 0.5) / max(frac, 1e-9), 0.0, 1.0)
        t = t * t * (3.0 - 2.0 * t)  # smoothstep: sin borde, todo el tramo es penumbra
    else:
        edge = (1.0 - frac) * h + slope * (xx - 0.5 * w)
        t = np.clip((yy - edge) / penumbra + 0.5, 0.0, 1.0)
    f = 1.0 + t[..., None] * (gain[None, None, :] - 1.0)
    return linear_to_srgb8(srgb8_to_linear(piece) * f), stops, frac


def gradient_piece(colors: list[tuple[int, int, int]], h: int, w: int, rng: np.random.Generator, *,
                   light_x: float) -> np.ndarray:
    """Pieza con DEGRADADO DE COLOR (tie-dye, degradado teñido): interpolación continua en luz lineal
    entre ``colors`` a lo alto, con el lambertiano y los pliegues encima. No puede colapsar a un color."""
    n = len(colors) - 1
    t = np.linspace(0.0, float(n), h)
    k = np.clip(t.astype(int), 0, n - 1)
    f = (t - k)[:, None]
    lin = np.stack([srgb8_to_linear(np.array(colors, dtype=np.uint8))[k][:, c] * (1.0 - f[:, 0])
                    + srgb8_to_linear(np.array(colors, dtype=np.uint8))[k + 1][:, c] * f[:, 0] for c in range(3)],
                   axis=-1)
    base = linear_to_srgb8(np.repeat(lin[:, None, :], w, axis=1))
    return shade_piece(base, rng, light_x=light_x, folds=int(rng.integers(2, 5)),
                       fold_factor=float(rng.uniform(0.6, 0.75)), specular=float(rng.uniform(0.0, 0.02)),
                       ambient=0.6)


def tonal_pair(rng: np.random.Generator, base: tuple[int, int, int], target_de: float) -> tuple[int, int, int]:
    """El MISMO tinte con menos luz (bicolor tonal): ``base`` escalado en XYZ lineal hasta un ΔE00
    aproximado ``target_de``. Es el límite conocido del modelo de sombra (ADR-011): el motor lo ve
    como una prenda lisa con sombra y devuelve un solo color."""
    lab = lab_of(base)
    best, best_err = base, 1e9
    for s in np.linspace(0.05, 0.95, 91):
        cand = linear_to_srgb8(srgb8_to_linear(np.array(base, dtype=np.uint8)) * s)
        err = abs(de00(lab, lab_of(tuple(int(v) for v in cand))) - target_de)
        if err < best_err:
            best_err, best = err, tuple(int(v) for v in cand)
    return best  # type: ignore[return-value]


def shade_piece(base: np.ndarray, rng: np.random.Generator, *, light_x: float, folds: int,
                fold_factor: float, specular: float, ambient: float = 0.45) -> np.ndarray:
    """Pieza HxWx3 uint8: ``base`` (HxWx3 sRGB8 sin sombra) en luz lineal x factor, más un brillo
    especular en las columnas más iluminadas (``specular`` del ancho, mezcla 0,6 hacia el blanco).
    ``ambient`` es el suelo del lambertiano (0,45 = sombra propia profunda)."""
    h, w, _ = base.shape
    f, lamb = shade_factor(h, w, rng, light_x=light_x, folds=folds, fold_factor=fold_factor, ambient=ambient)
    lin = srgb8_to_linear(base) * f[..., None]
    n_spec = int(round(specular * w))
    if n_spec > 0:
        cols = np.argsort(-lamb, kind="stable")[:n_spec]
        lin[:, cols, :] = lin[:, cols, :] + 0.6 * (1.0 - lin[:, cols, :])
    return linear_to_srgb8(lin)


def _stripes(h: int, w: int, a: tuple[int, int, int], b: tuple[int, int, int], width: int) -> np.ndarray:
    rows = (np.arange(h) // width) % 2
    out = np.empty((h, w, 3), dtype=np.uint8)
    out[rows == 0] = a
    out[rows == 1] = b
    return out


def _print_pattern(h: int, w: int, dark: tuple[int, int, int], light: tuple[int, int, int], motif: int,
                   rng: np.random.Generator) -> np.ndarray:
    """Motivos claros cuadrados de ``motif`` px sobre fondo oscuro en una rejilla con desplazamiento
    aleatorio (~35 % del área clara)."""
    out = np.empty((h, w, 3), dtype=np.uint8)
    out[:] = dark
    step = int(round(motif / 0.6))
    for y in range(0, h, step):
        for x in range(0, w, step):
            dy, dx = int(rng.integers(0, step - motif + 1)), int(rng.integers(0, step - motif + 1))
            out[y + dy:y + dy + motif, x + dx:x + dx + motif] = light
    return out


def blur_linear(img: np.ndarray, radius: int) -> np.ndarray:
    """Desenfoque de caja separable de radio ``radius`` en luz lineal (bordes replicados)."""
    if radius <= 0:
        return img
    lin = srgb8_to_linear(img)
    k = 2 * radius + 1
    for axis in (0, 1):
        pad = [(0, 0)] * 3
        pad[axis] = (radius, radius)
        padded = np.pad(lin, pad, mode="edge")
        csum = np.cumsum(padded, axis=axis)
        zero_shape = list(csum.shape)
        zero_shape[axis] = 1
        csum = np.concatenate([np.zeros(zero_shape), csum], axis=axis)
        hi = np.take(csum, np.arange(k, csum.shape[axis]), axis=axis)
        lo = np.take(csum, np.arange(0, csum.shape[axis] - k), axis=axis)
        lin = (hi - lo) / k
    return linear_to_srgb8(lin)


@dataclass
class Case:
    index: int
    kind: str
    seed: int
    img: np.ndarray
    mask: np.ndarray
    regions: np.ndarray
    #: Colores verdaderos (sRGB8) por región esperada: 1, 2 o 3.
    truth: dict[int, list[tuple[int, int, int]]]
    pair_de00: float | None = None
    #: Pasos de luz que quita la sombra proyectada (familias ``sombra_proyectada`` y ``sombra_cielo``).
    shadow_stops: float | None = None
    #: Colores esperados por región cuando no coincide con ``len(truth[r])`` (degradado: los extremos
    #: son dos, pero el tono iluminado de cada grupo cae DENTRO del degradado y no se compara).
    expected_counts: dict[int, int] | None = None


def figure_geometry(width: int, height: int) -> dict[str, tuple[slice, slice]]:
    return {
        "torso": (slice(int(0.12 * height), int(0.52 * height)), slice(int(0.22 * width), int(0.78 * width))),
        "leg_l": (slice(int(0.52 * height), int(0.96 * height)), slice(int(0.26 * width), int(0.49 * width))),
        "leg_r": (slice(int(0.52 * height), int(0.96 * height)), slice(int(0.51 * width), int(0.74 * width))),
    }


def make_case(index: int, kind: str, seed: int, size: tuple[int, int] = SIZE, canonical: bool = False) -> Case:
    rng = np.random.default_rng(seed)
    w, h = size
    geo = figure_geometry(w, h)
    bg_color = _random_color(rng)
    img = np.empty((h, w, 3), dtype=np.uint8)
    img[:] = bg_color
    img = sc.add_noise(img, 6.0, seed + 7)
    mask = np.zeros((h, w), dtype=np.uint8)
    regions = np.zeros((h, w), dtype=np.uint8)
    pair = None
    hard_part = None
    cast_part = None
    sky_part = None
    grad_part = None
    shadow_stops = None
    expected_counts = None
    if kind in ("liso", "sombra_fuerte", "sombra_proyectada", "sombra_cielo"):
        if canonical:
            top, bottom = PINK_PANTS["top"], PINK_PANTS["bottom"]
        else:
            top = _random_color(rng)
            bottom = _distinct(rng, [top], 20.0)
        truth = {1: [top], 2: [bottom]}
        bases = {"torso": top, "leg": bottom}
        if kind == "sombra_fuerte":
            hard_part = "torso" if rng.random() < 0.4 else "leg"
        elif kind == "sombra_proyectada":
            cast_part = "torso" if rng.random() < 0.4 else "leg"
        elif kind == "sombra_cielo":
            sky_part = "torso" if rng.random() < 0.4 else "leg"
    elif kind == "rayas":
        dark = _random_color(rng, L=(12.0, 38.0), C=(5.0, 45.0))
        light = _distinct(rng, [dark], 25.0, L=(72.0, 95.0), C=(0.0, 25.0))
        # Que el par no sea AMBIGUO para los dos modelos de sombra del motor (un gris claro y su
        # versión a la sombra azul son indistinguibles de una prenda lisa a medio sol: eso es el
        # límite conocido de ADR-011 y lo mide la familia informativa bicolor_tonal, no este gate).
        for _ in range(200):
            if same_material_residual(dark, light) >= 5.0:
                break
            dark = _random_color(rng, L=(12.0, 38.0), C=(5.0, 45.0))
            light = _distinct(rng, [dark], 25.0, L=(72.0, 95.0), C=(0.0, 25.0))
        bottom = _distinct(rng, [dark, light], 20.0)
        truth = {1: [dark, light], 2: [bottom]}
        pattern = "print" if index % 2 == 1 else "stripes"
        size = int(rng.integers(6, 13)) if pattern == "print" else int(rng.integers(8, 17))
        bases = {"torso": (pattern, dark, light, size, 1), "leg": bottom}
    elif kind == "estampado_sombra":
        # Fondo oscuro + motivo claro DESENFOCADO y, encima, una sombra abierta de exterior sobre la
        # mitad: el motivo en sombra tiene la luminancia del fondo al sol (caso de harness/people/02).
        dark = _random_color(rng, L=(8.0, 30.0), C=(2.0, 30.0))
        light = _distinct(rng, [dark], 45.0, L=(78.0, 96.0), C=(0.0, 18.0))
        for _ in range(200):  # que no sean un PAR AMBIGUO para los dos modelos (eso lo mide bicolor_tonal)
            if scaled_model_residual(dark, light) >= 8.0 and sky_model_residual(dark, light) >= 5.0:
                break
            dark = _random_color(rng, L=(8.0, 30.0), C=(2.0, 30.0))
            light = _distinct(rng, [dark], 45.0, L=(78.0, 96.0), C=(0.0, 18.0))
        bottom = _distinct(rng, [dark, light], 20.0)
        truth = {1: [dark, light], 2: [bottom]}
        bases = {"torso": ("print", dark, light, int(rng.integers(6, 13)), 1), "leg": bottom}
        sky_part = "torso"
    elif kind == "degradado_color":
        # Degradado de color de verdad (tie-dye): tres tintes separados en tono.
        c0 = _random_color(rng, L=(35.0, 70.0), C=(25.0, 55.0))
        c1 = _distinct(rng, [c0], 35.0, L=(45.0, 85.0), C=(25.0, 55.0))
        c2 = _distinct(rng, [c0, c1], 35.0, L=(35.0, 75.0), C=(25.0, 55.0))
        top = _distinct(rng, [c0, c1, c2], 20.0)
        truth = {1: [top]}
        expected_counts = {1: 1, 2: 2}
        bases = {"torso": top, "leg": ("gradient", [c0, c1, c2])}
        grad_part = "leg"
    elif kind == "bicolor_tonal":
        # LÍMITE CONOCIDO (informativa): rayas de un tinte y su propia sombra (el mismo color con
        # menos luz). El modelo de sombra las une y sale un solo color.
        tint = _random_color(rng, L=(55.0, 88.0), C=(0.0, 45.0))
        if index % 2 == 1:
            # La mitad de los casos: par ambiguo por el MODELO (2) (sombra abierta de exterior), no
            # por la escala pura: el mismo tinte visto bajo el cielo azul. Es el límite conocido que
            # el modelo de cielo AÑADE (ce.h, ADR-011) y hay que medirlo, no esconderlo.
            stops = float(rng.choice([1.5, 2.0, 2.5, 3.0]))
            dark = tuple(int(v) for v in linear_to_srgb8(
                srgb8_to_linear(np.array(tint, dtype=np.uint8)) * sky_shadow_gain(stops)))
        else:
            dark = tonal_pair(rng, tint, float(rng.choice([10.0, 20.0, 30.0, 45.0])))
        bottom = _distinct(rng, [tint, dark], 20.0)
        truth = {1: [tint, dark], 2: [bottom]}
        pair = de00(lab_of(tint), lab_of(dark))
        bases = {"torso": ("stripes", tint, dark, int(rng.integers(8, 17)), 1), "leg": bottom}
    elif kind == "banda_fusion":
        # Informativa: dos prendas distintas con ΔE00 REAL alrededor de shade_merge_de (5, 6, 6,5, 7,
        # 8), para medir la banda en la que la fusión a región 3 depende de la luz y la textura
        # (la promesa de ce.h es sobre TONOS ILUMINADOS ESTIMADOS, no sobre el color verdadero).
        target = float((5.0, 6.0, 6.5, 7.0, 8.0)[index % 5])
        top = _random_color(rng, L=(20.0, 75.0), C=(2.0, 40.0))
        bottom, pair = _pair_at_de(rng, top, target)
        truth = {1: [top], 2: [bottom]}
        bases = {"torso": top, "leg": bottom}
    elif kind == "vestido":
        dress = _random_color(rng, L=(22.0, 85.0), C=(3.0, 50.0))
        truth = {3: [dress]}
        bases = {"torso": dress, "leg": dress}
    elif kind == "tono_cercano":
        if canonical:
            top, bottom = NAVY_DENIM["top"], NAVY_DENIM["bottom"]
            pair = de00(lab_of(top), lab_of(bottom))
        else:
            top = _random_color(rng, L=(18.0, 80.0), C=(2.0, 40.0))
            bottom, pair = close_tone(rng, top)
        truth = {1: [top], 2: [bottom]}
        bases = {"torso": top, "leg": bottom}
    else:
        raise ValueError(f"familia desconocida {kind!r}")

    light_x = float(rng.uniform(-0.6, 0.6))
    for part, (ys, xs) in geo.items():
        ph, pw = ys.stop - ys.start, xs.stop - xs.start
        spec = bases["torso"] if part == "torso" else bases["leg"]
        if hard_part is not None and (part == "torso") == (hard_part == "torso"):
            piece = hard_shadow_piece(spec, ph, pw, rng, light_x=light_x)  # type: ignore[arg-type]
        elif grad_part is not None and (part == "torso") == (grad_part == "torso"):
            piece = gradient_piece(list(spec[1]), ph, pw, rng, light_x=light_x)  # type: ignore[index]
        elif sky_part is not None and (part == "torso") == (sky_part == "torso"):
            if isinstance(spec, tuple) and spec and spec[0] == "print":
                base = blur_linear(_print_pattern(ph, pw, spec[1], spec[2], spec[3], rng), spec[4])
                piece = shade_piece(base, rng, light_x=light_x, folds=int(rng.integers(1, 4)),
                                    fold_factor=float(rng.uniform(0.6, 0.75)), specular=0.0,
                                    ambient=float(rng.uniform(0.6, 0.8)))
                stops = float(rng.uniform(1.5, 3.0))
                gain = sky_shadow_gain(stops)
                # Con PENUMBRA (8-16 px): los tonos intermedios del fondo oscuro y los del motivo
                # claro llenan el hueco de luminancia, que es lo que puede encadenar por
                # transitividad el fondo con el motivo.
                pen = int(rng.integers(8, 17))
                yy2 = np.mgrid[0:ph, 0:pw][0]
                t2 = np.clip((yy2 - ph * 0.4) / pen + 0.5, 0.0, 1.0)
                f = 1.0 + t2[..., None] * (gain[None, None, :] - 1.0)
                piece = linear_to_srgb8(srgb8_to_linear(piece) * f)
            else:
                piece, stops, _frac = sky_shadow_piece(spec, ph, pw, rng, light_x=light_x,  # type: ignore[arg-type]
                                                       smooth=(index % 3 == 2))
            shadow_stops = stops if shadow_stops is None else shadow_stops
        elif cast_part is not None and (part == "torso") == (cast_part == "torso"):
            piece, stops, _frac = projected_shadow_piece(spec, ph, pw, rng, light_x=light_x)  # type: ignore[arg-type]
            shadow_stops = stops if shadow_stops is None else shadow_stops
        else:
            if isinstance(spec, tuple) and spec and spec[0] == "stripes":
                base = blur_linear(_stripes(ph, pw, spec[1], spec[2], spec[3]), spec[4])
            elif isinstance(spec, tuple) and spec and spec[0] == "print":
                base = blur_linear(_print_pattern(ph, pw, spec[1], spec[2], spec[3], rng), spec[4])
            else:
                base = np.empty((ph, pw, 3), dtype=np.uint8)
                base[:] = spec
            folds = int(rng.integers(3, 7)) if part != "torso" else int(rng.integers(1, 4))
            piece = shade_piece(base, rng, light_x=light_x, folds=folds, fold_factor=float(rng.uniform(0.55, 0.7)),
                                specular=float(rng.uniform(0.0, 0.03)))
        img[ys, xs] = piece
        mask[ys, xs] = 255
        regions[ys, xs] = 1 if part == "torso" else 2
    img = sc.add_noise(img, NOISE_SIGMA, seed + 11)
    return Case(index, kind, seed, img, mask, regions, truth, pair, shadow_stops, expected_counts)


def pink_pants_case(seed: int = SEED) -> Case:
    return make_case(0, "liso", seed, canonical=True)


#: Paleta que dio la app con la foto real del tranvía (CONTEXT §13): camiseta y cuatro tonos del
#: mismo pantalón, con sus pesos. Solo valores hex, nunca la foto.
REAL_PANTS_PALETTE: tuple[tuple[str, float], ...] = (
    ("#222524", 0.394), ("#b49aa2", 0.227), ("#917a7e", 0.162), ("#d5b8c0", 0.134), ("#6b5a57", 0.083))


def real_pants_proxy(seed: int = SEED) -> Case:
    """Réplica plana de la paleta real: torso #222524 y piernas en bandas verticales con los cuatro
    tonos del pantalón en sus proporciones (ruido sigma 1,5). Informativo: sin gradientes, el
    tono iluminado mezcla los dos tonos claros (L* 66 y 77)."""
    w, h = SIZE
    geo = figure_geometry(w, h)
    img = np.zeros((h, w, 3), dtype=np.uint8)
    img[:] = (90, 120, 60)
    mask = np.zeros((h, w), dtype=np.uint8)
    regions = np.zeros((h, w), dtype=np.uint8)
    pants = [(_hex(c), wgt) for c, wgt in REAL_PANTS_PALETTE[1:]]
    total = sum(wgt for _, wgt in pants)
    for part, (ys, xs) in geo.items():
        if part == "torso":
            img[ys, xs] = _hex(REAL_PANTS_PALETTE[0][0])
            regions[ys, xs] = 1
        else:
            pw = xs.stop - xs.start
            x = xs.start
            for k, (rgb, wgt) in enumerate(pants):
                x1 = xs.stop if k == len(pants) - 1 else x + int(round(pw * wgt / total))
                img[ys, x:x1] = rgb
                x = x1
            regions[ys, xs] = 2
        mask[ys, xs] = 255
    img = sc.add_noise(img, NOISE_SIGMA, seed + 13)
    return Case(900, "pantalon_real", seed, img, mask, regions,
                {1: [_hex("#2b2c2c")], 2: [_hex("#ddc0c8")]})


def build_cases(n: int = N_CASES, seed: int = SEED) -> list[Case]:
    """``n`` composiciones repartidas por ``KIND_SHARES`` (proporcional), deterministas."""
    total = sum(KIND_SHARES.values())
    counts = {k: (KIND_SHARES[k] * n) // total for k in KINDS}
    for k in itertools.cycle(KINDS):
        if sum(counts.values()) >= n:
            break
        counts[k] += 1
    cases: list[Case] = []
    idx = 0
    for kind in KINDS:
        for j in range(counts[kind]):
            canonical = (j == 0 and kind in ("liso", "tono_cercano"))
            cases.append(make_case(idx, kind, seed * 1000 + idx, canonical=canonical))
            idx += 1
    return cases


def write_case(case: Case, work: Path) -> tuple[Path, Path, Path]:
    stem = f"g{case.index:03d}_{case.kind}"
    return (sc.write_ppm(case.img, work / f"{stem}.ppm"), sc.write_pgm(case.mask, work / f"{stem}.mask.pgm"),
            sc.write_pgm(case.regions, work / f"{stem}.regions.pgm"))


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------


def _fmt_opt(value: Any) -> str:
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    return repr(float(value))


#: Nombre de la opción del CLI de cada campo de ce_garment_opts.
GARMENT_FLAGS: dict[str, str] = {
    "shade_kL": "--shade-kl", "shade_merge_de": "--shade-merge-de", "lit_low_pct": "--lit-low",
    "lit_high_pct": "--lit-high", "secondary_min_share": "--secondary-min-share",
    "max_colors_per_region": "--max-colors-per-region",
}


def option_args(garment_opts: dict[str, Any] | None = None, palette_opts: dict[str, Any] | None = None,
                match_opts: dict[str, Any] | None = None) -> list[str]:
    args: list[str] = []
    for key, value in (palette_opts or {}).items():
        args += ["--" + key.replace("_", "-"), _fmt_opt(value)]
    for key, value in (garment_opts or {}).items():
        args += [GARMENT_FLAGS[key], _fmt_opt(value)]
    for key, value in (match_opts or {}).items():
        args += ["--" + key if key in ("kL", "kC", "kH") else "--" + key.replace("_", "-"), _fmt_opt(value)]
    return args


def has_garments(cli: Path | None) -> bool:
    if cli is None:
        return False
    try:
        proc = subprocess.run([str(cli), "garments"], capture_output=True, text=True, check=False, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return "garments" in (proc.stdout + proc.stderr)


def run_garments(cli: Path, image: Path, *, mask: Path | None = None, regions: Path | None = None,
                 match: bool = False, top: int = 3, garment_opts: dict[str, Any] | None = None,
                 palette_opts: dict[str, Any] | None = None, match_opts: dict[str, Any] | None = None,
                 debug_dir: Path | None = None, timeout: float = 120.0) -> dict[str, Any]:
    args = ["garments", str(image)]
    if mask is not None:
        args += ["--mask", str(mask)]
    if regions is not None:
        args += ["--regions", str(regions)]
    args += option_args(garment_opts, palette_opts, match_opts)
    if match:
        args += ["--match", "--top", str(top)]
    if debug_dir is not None:
        args += ["--debug-dir", str(debug_dir)]
    args.append("--json")
    proc = subprocess.run([str(cli), *args], capture_output=True, text=True, check=False, timeout=timeout)
    if proc.returncode != 0:
        raise GarmentError(f"ce {' '.join(args)} -> exit {proc.returncode}: {proc.stderr.strip()[:300]}")
    try:
        out = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise GarmentError(f"ce garments: stdout no es JSON ({exc})") from exc
    out["_stdout"] = proc.stdout
    return out


def run_batch_garments(cli: Path, entries: list[tuple[Path, Path | None, Path | None]], *,
                       garment_opts: dict[str, Any] | None = None, palette_opts: dict[str, Any] | None = None,
                       match_opts: dict[str, Any] | None = None, top: int = 3,
                       timeout: float = 900.0) -> list[dict[str, Any]]:
    """``ce batch --garments`` sobre (imagen, máscara|None, regiones|None); un resultado por entrada."""
    with tempfile.TemporaryDirectory(prefix="colorsapp-garments-") as tmp:
        lst = Path(tmp) / "list.txt"
        lines = []
        for img, mask, regions in entries:
            parts = [f'"{img}"', f'"{mask}"' if mask is not None else "-"]
            if regions is not None:
                parts.append(f'"{regions}"')
            lines.append(" ".join(parts))
        lst.write_text("\n".join(lines) + "\n", encoding="utf-8")
        args = ["batch", str(lst), "--garments", *option_args(garment_opts, palette_opts, match_opts),
                "--top", str(top), "--json"]
        proc = subprocess.run([str(cli), *args], capture_output=True, text=True, check=False, timeout=timeout)
    if proc.returncode not in (0, 1):
        raise GarmentError(f"ce batch --garments -> exit {proc.returncode}: {proc.stderr.strip()[:300]}")
    results = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
    if len(results) != len(entries):
        raise GarmentError(f"ce batch --garments: {len(results)} líneas para {len(entries)} entradas")
    return results


# --------------------------------------------------------------------------------------
# Métricas
# --------------------------------------------------------------------------------------


def colors_by_region(result: dict[str, Any]) -> dict[int, list[dict[str, Any]]]:
    out: dict[int, list[dict[str, Any]]] = {}
    for g in result.get("garments", []):
        out.setdefault(int(g["region"]), []).append(g)
    return out


def evaluate_case(case: Case, result: dict[str, Any]) -> dict[str, Any]:
    """Métricas de una composición frente a su verdad (ver docstring del módulo)."""
    got = colors_by_region(result)
    if "error" in result:
        return {"index": case.index, "kind": case.kind, "error": result["error"], "colors_ok": False,
                "lit_de": [], "wrong_fusion": False, "missed_fusion": False, "stripes_merged": False,
                "shadow_stops": case.shadow_stops}
    counts = {r: len(v) for r, v in got.items()}
    expected = dict(case.expected_counts) if case.expected_counts else {r: len(v) for r, v in case.truth.items()}
    colors_ok = counts == expected
    lit_de: list[float] = []
    for region, truth_rgbs in case.truth.items():
        swatches = got.get(region, [])
        if not swatches:
            lit_de += [float("inf")] * len(truth_rgbs)
            continue
        cost = np.array([[de00(lab_of(t), s["lab"]) for s in swatches] for t in truth_rgbs])
        rows, cols = linear_sum_assignment(cost)
        matched = {int(r): float(cost[r, c]) for r, c in zip(rows, cols)}
        lit_de += [matched.get(i, float("inf")) for i in range(len(truth_rgbs))]
    return {
        "index": case.index,
        "kind": case.kind,
        "counts": {str(k): v for k, v in sorted(counts.items())},
        "expected": {str(k): v for k, v in sorted(expected.items())},
        "colors_ok": bool(colors_ok),
        "lit_de": lit_de,
        "lit_de_max": max(lit_de) if lit_de else 0.0,
        "wrong_fusion": case.kind != "vestido" and 3 in got,
        "missed_fusion": case.kind == "vestido" and 3 not in got,
        "stripes_merged": case.kind == "rayas" and counts.get(1, 0) < 2,
        # Familias nuevas: un fallo por familia, con nombre propio.
        "sky_shadow_split": case.kind == "sombra_cielo" and sum(counts.values()) > 2,
        "print_shadow_lost": case.kind == "estampado_sombra" and counts.get(1, 0) + counts.get(3, 0) < 2,
        "gradient_collapsed": case.kind == "degradado_color" and counts.get(2, 0) + counts.get(3, 0) < 2,
        "tonal_kept": case.kind == "bicolor_tonal" and counts.get(1, 0) >= 2,
        "band_fused": case.kind == "banda_fusion" and 3 in got,
        "pair_de00": case.pair_de00,
        "shadow_stops": case.shadow_stops,
        "garments": [{"region": g["region"], "hex": g["hex"], "weight": g["weight"],
                      "n_merged_clusters": g["n_merged_clusters"]} for g in result.get("garments", [])],
    }


def summarize(rows: list[dict[str, Any]], shade_merge_de: float) -> dict[str, Any]:
    gated = [r for r in rows if r["kind"] not in INFORMATIVE_KINDS]
    n = len(gated)
    lit_rows = [r for r in rows if r["kind"] in LIT_DE_KINDS]
    new_rows = [r for r in gated if r["kind"] not in LIT_DE_KINDS]
    finite = [d for r in lit_rows for d in r["lit_de"] if np.isfinite(d)]
    finite_new = [d for r in new_rows for d in r["lit_de"] if np.isfinite(d)]
    by_kind = {}
    for kind in KINDS:
        kr = [r for r in rows if r["kind"] == kind]
        if kr:
            by_kind[kind] = {"n": len(kr), "colors_ok": sum(r["colors_ok"] for r in kr),
                             "wrong_fusion": sum(r["wrong_fusion"] for r in kr),
                             "missed_fusion": sum(r["missed_fusion"] for r in kr)}
    sky = [r for r in rows if r["kind"] == "sombra_cielo"]
    prints = [r for r in rows if r["kind"] == "estampado_sombra"]
    grads = [r for r in rows if r["kind"] == "degradado_color"]
    tonal = [r for r in rows if r["kind"] == "bicolor_tonal"]
    band = [r for r in rows if r["kind"] == "banda_fusion"]
    band_curve: dict[str, list[int]] = {}
    for r in band:
        key = f"{float(r.get('pair_de00') or 0.0):.1f}"
        cur = band_curve.setdefault(key, [0, 0])
        cur[0] += int(bool(r["band_fused"]))
        cur[1] += 1
    close = [r for r in rows if r["kind"] == "tono_cercano" and r.get("pair_de00") is not None]
    over = [r for r in close if float(r["pair_de00"]) > float(shade_merge_de)]
    dresses = [r for r in rows if r["kind"] == "vestido"]
    cast = [r for r in rows if r["kind"] == "sombra_proyectada"]
    cast_split = [r for r in cast if not r["colors_ok"] and sum(int(v) for v in r.get("counts", {}).values()) > 2]
    return {
        "n": n,
        "n_all": len(rows),
        "informative_kinds": list(INFORMATIVE_KINDS),
        "colors_ok": sum(r["colors_ok"] for r in gated),
        "colors_ok_rate": (sum(r["colors_ok"] for r in gated) / n) if n else 0.0,
        "lit_de00_median": float(np.median(finite)) if finite else float("inf"),
        "lit_de00_p90": float(np.percentile(finite, 90)) if finite else float("inf"),
        "lit_de00_max": float(max(finite)) if finite else float("inf"),
        "unmatched_colors": sum(1 for r in lit_rows for d in r["lit_de"] if not np.isfinite(d)),
        "lit_de00_new_families": {
            "n": len(finite_new),
            "median": float(np.median(finite_new)) if finite_new else 0.0,
            "p90": float(np.percentile(finite_new, 90)) if finite_new else 0.0,
            "max": float(max(finite_new)) if finite_new else 0.0,
        },
        "wrong_fusions": sum(r["wrong_fusion"] for r in gated),
        "stripes_merged": sum(r["stripes_merged"] for r in gated),
        "missed_fusions": sum(r["missed_fusion"] for r in gated),
        "missed_fusion_rate": (sum(r["missed_fusion"] for r in dresses) / len(dresses)) if dresses else 0.0,
        "close_pairs": len(close),
        "close_pairs_over_threshold": len(over),
        "close_pairs_over_threshold_fused": sum(r["wrong_fusion"] for r in over),
        "cast_shadow_cases": len(cast),
        "cast_shadow_split": len(cast_split),
        "cast_shadow_split_stops": sorted(round(float(r["shadow_stops"]), 2) for r in cast_split
                                          if r.get("shadow_stops") is not None),
        "cast_shadow_stops_range": ([round(min(float(r["shadow_stops"]) for r in cast if r.get("shadow_stops")), 2),
                                     round(max(float(r["shadow_stops"]) for r in cast if r.get("shadow_stops")), 2)]
                                    if cast else []),
        # Familias nuevas (ADR-011, segunda vuelta).
        "sky_shadow_cases": len(sky),
        "sky_shadow_split": sum(r["sky_shadow_split"] for r in sky),
        "sky_shadow_stops_range": ([round(min(float(r["shadow_stops"]) for r in sky if r.get("shadow_stops")), 2),
                                    round(max(float(r["shadow_stops"]) for r in sky if r.get("shadow_stops")), 2)]
                                   if sky else []),
        "print_shadow_cases": len(prints),
        "print_shadow_lost": sum(r["print_shadow_lost"] for r in prints),
        "gradient_cases": len(grads),
        "gradient_collapsed": sum(r["gradient_collapsed"] for r in grads),
        # Informativas: límites conocidos y documentados (ADR-011), fuera de los gates.
        "tonal_cases": len(tonal),
        "tonal_kept": sum(r["tonal_kept"] for r in tonal),
        "tonal_pair_de00": sorted(round(float(r["pair_de00"]), 1) for r in tonal if r.get("pair_de00")),
        "band_cases": len(band),
        "band_fused": sum(r["band_fused"] for r in band),
        "band_curve": {k: band_curve[k] for k in sorted(band_curve, key=float)},
        "by_kind": by_kind,
    }


def evaluate(cli: Path, cases: list[Case], work: Path, *, garment_opts: dict[str, Any] | None = None,
             palette_opts: dict[str, Any] | None = None) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    entries = [write_case(c, work) for c in cases]
    results = run_batch_garments(cli, [(img, mask, reg) for img, mask, reg in entries],
                                 garment_opts=garment_opts, palette_opts=palette_opts)
    rows = [evaluate_case(c, r) for c, r in zip(cases, results)]
    opts = dict(ENGINE_DEFAULT_GARMENT_OPTS)
    opts.update(garment_opts or {})
    return rows, summarize(rows, float(opts["shade_merge_de"]))


# --------------------------------------------------------------------------------------
# harness/people (máscaras y poses de visionmask)
# --------------------------------------------------------------------------------------

#: Opciones de ce garment-regions para las fotos: la silueta corporal de SubjectKit (torso con
#: margen 0,35 y cápsulas de ancho 1,0 con antebrazos), así la región cubre la máscara final.
PEOPLE_REGION_ARGS: tuple[str, ...] = ("--torso-margin", "0.35", "--limb-width", "1.0", "--forearms", "1")
PEOPLE_VARIANT = "largest-clothing-skin"


def people_entries(cli: Path, work: Path, people_dir: Path = PEOPLE_DIR, masks_dir: Path = PEOPLE_MASKS_DIR,
                   variant: str = PEOPLE_VARIANT) -> list[dict[str, Any]]:
    """Fotos de harness/people con máscara final de ``variant`` y pose: (ppm, máscara, regiones, anotación)."""
    expected_path = people_dir / "expected.json"
    if not expected_path.is_file() or not masks_dir.is_dir():
        return []
    expected = {e["file"]: e for e in json.loads(expected_path.read_text(encoding="utf-8"))}
    out = []
    for fname, exp in sorted(expected.items()):
        base = Path(fname).stem
        ppm = masks_dir / f"{base}.ppm"
        mask = masks_dir / f"{base}.{variant}.pgm"
        layers = masks_dir / f"{base}.{variant}.layers"
        pose = layers / "pose.txt"
        if not (ppm.is_file() and mask.is_file() and pose.is_file()):
            continue
        img = sc.read_ppm(ppm)
        regions = work / f"{base}.regions.pgm"
        proc = subprocess.run([str(cli), "garment-regions", "--size", f"{img.shape[1]}x{img.shape[0]}", "--mask",
                               str(mask), "--pose", str(pose), "--out", str(regions), *PEOPLE_REGION_ARGS],
                              capture_output=True, text=True, check=False, timeout=60)
        entry: dict[str, Any] = {"base": base, "ppm": ppm, "mask": mask, "expected": exp}
        if proc.returncode == 0:
            entry["regions"] = regions
            entry["region_pixels"] = json.loads(proc.stdout)
        else:
            entry["regions"] = None
            entry["regions_error"] = proc.stderr.strip()[:200]
        out.append(entry)
    return out


def evaluate_people(cli: Path, entries: list[dict[str, Any]], *, garment_opts: dict[str, Any] | None = None,
                    palette_opts: dict[str, Any] | None = None) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Colores por prenda y ΔE00 a la ropa anotada de la persona más grande (``expected.json``)."""
    if not entries:
        return [], {"n": 0}
    results = run_batch_garments(cli, [(e["ppm"], e["mask"], e.get("regions")) for e in entries],
                                 garment_opts=garment_opts, palette_opts=palette_opts)
    rows = []
    part_region = {"torso": 1, "legs": 2}
    for e, r in zip(entries, results):
        got = colors_by_region(r)
        garments = e["expected"].get("largest_person", {}).get("garments", [])
        des = []
        for g in garments:
            region = part_region.get(g["part"])
            pool = [s for s in r.get("garments", []) if region is None or s["region"] in (region, 3)]
            if not pool:
                pool = r.get("garments", [])
            if pool:
                des.append(min(de00(lab_of(_hex(g["color_hex"])), s["lab"]) for s in pool))
        rows.append({
            "base": e["base"],
            "has_regions": e.get("regions") is not None,
            "counts": {str(k): len(v) for k, v in sorted(got.items())},
            "n_garment_swatches": len(r.get("garments", [])),
            "garment_de": des,
            "garments": [{"region": s["region"], "hex": s["hex"], "weight": round(float(s["weight"]), 4),
                          "n_merged_clusters": s["n_merged_clusters"]} for s in r.get("garments", [])],
            "top3": [h["id"] for h in r.get("hits", [])],
        })
    all_de = [d for row in rows for d in row["garment_de"]]
    return rows, {
        "n": len(rows),
        "with_regions": sum(r["has_regions"] for r in rows),
        "mean_swatches": float(np.mean([r["n_garment_swatches"] for r in rows])),
        "max_colors_in_a_region": max((max((int(v) for v in r["counts"].values()), default=0) for r in rows), default=0),
        "garment_de00_median": float(np.median(all_de)) if all_de else float("inf"),
        "garment_de00_mean": float(np.mean(all_de)) if all_de else float("inf"),
    }


def _hex(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


# --------------------------------------------------------------------------------------
# Bloque «prendas» de la capa 2
# --------------------------------------------------------------------------------------


def resolve_thresholds(thresholds: dict[str, Any] | None) -> tuple[dict[str, Any], list[str]]:
    section = ((thresholds or {}).get("L2", {}) or {}).get("garments", {}) if thresholds else {}
    values: dict[str, Any] = {}
    defaulted: list[str] = []
    for key, default in DEFAULTS.items():
        if isinstance(section, dict) and key in section:
            values[key] = section[key]
        else:
            values[key] = default
            defaulted.append(key)
    return values, defaulted


def run_block(cli: Path, thresholds: dict[str, Any] | None, work: Path, n: int | None = None,
              log=print) -> tuple[list[Any], dict[str, Any]]:
    """Checks del bloque «prendas» (mismo esquema que ``oracle.l2.Check``) y detalle."""
    from oracle.l2 import Check

    th, defaulted = resolve_thresholds(thresholds)
    n_cases = int(n if n is not None else th["cases"])
    t0 = time.perf_counter()
    cases = build_cases(n_cases)
    checks: list[Check] = []
    try:
        rows, summ = evaluate(cli, cases, work)
    except GarmentError as exc:
        checks.append(Check(f"prendas ({n_cases} composiciones sombreadas): ce batch --garments", "fail", str(exc)))
        return checks, {"error": str(exc)}
    seconds = round(time.perf_counter() - t0, 3)
    kinds = ", ".join(f"{k} {v['colors_ok']}/{v['n']}" for k, v in summ["by_kind"].items())
    checks.append(Check(
        f"prendas ({n_cases}): colores por prenda exactos (liso 1+1, rayas 2+1, vestido 1 en región 3, tono cercano 1+1) >= {th['colors_ok_rate_min']}",
        "pass" if summ["colors_ok_rate"] >= float(th["colors_ok_rate_min"]) else "fail",
        f"{summ['colors_ok']}/{summ['n']} ({kinds})", value=summ["colors_ok_rate"],
        threshold=float(th["colors_ok_rate_min"]), seconds=seconds))
    checks.append(Check(
        f"prendas: ΔE00 al tono iluminado verdadero ({', '.join(LIT_DE_KINDS)}), p90 < {th['lit_de00_p90_max']}",
        "pass" if summ["lit_de00_p90"] < float(th["lit_de00_p90_max"]) and summ["unmatched_colors"] == 0 else "fail",
        f"mediana {summ['lit_de00_median']:.2f}, p90 {summ['lit_de00_p90']:.2f}, máx {summ['lit_de00_max']:.2f}; "
        f"colores sin emparejar {summ['unmatched_colors']}; familias con media prenda en sombra o con "
        f"degradado (informativo): mediana {summ['lit_de00_new_families']['median']:.2f}, p90 "
        f"{summ['lit_de00_new_families']['p90']:.2f}", value=summ["lit_de00_p90"],
        threshold=float(th["lit_de00_p90_max"])))
    checks.append(Check(
        f"prendas: fusiones erróneas (prendas distintas en región 3) <= {th['wrong_fusions_max']}; "
        f">= {th['close_pairs_over_threshold_min']} pares de tono cercano con ΔE00 real > shade_merge_de",
        "pass" if (summ["wrong_fusions"] <= int(th["wrong_fusions_max"])
                   and summ["close_pairs_over_threshold"] >= int(th["close_pairs_over_threshold_min"])) else "fail",
        f"fusiones erróneas {summ['wrong_fusions']}; rayas fusionadas {summ['stripes_merged']}; pares de tono cercano "
        f"{summ['close_pairs']} ({summ['close_pairs_over_threshold']} con ΔE00 > shade_merge_de, fusionados "
        f"{summ['close_pairs_over_threshold_fused']})", value=summ["wrong_fusions"],
        threshold=int(th["wrong_fusions_max"])))
    checks.append(Check(
        f"prendas: prendas lisas partidas en dos por una sombra proyectada <= {th['cast_shadow_split_max']}",
        "pass" if summ["cast_shadow_split"] <= int(th["cast_shadow_split_max"]) else "fail",
        f"{summ['cast_shadow_split']}/{summ['cast_shadow_cases']} composiciones con sombra proyectada contigua de "
        f"{summ['cast_shadow_stops_range']} pasos dan un segundo color falso"
        + (f" (pasos {summ['cast_shadow_split_stops']})" if summ["cast_shadow_split_stops"] else ""),
        value=summ["cast_shadow_split"], threshold=int(th["cast_shadow_split_max"])))
    checks.append(Check(
        f"prendas: prendas lisas partidas por una SOMBRA AZUL de exterior <= {th['sky_shadow_split_max']}; "
        f"estampados que pierden el motivo claro con esa sombra <= {th['print_shadow_lost_max']}; "
        f"degradados de color colapsados a un color <= {th['gradient_collapsed_max']}",
        "pass" if (summ["sky_shadow_split"] <= int(th["sky_shadow_split_max"])
                   and summ["print_shadow_lost"] <= int(th["print_shadow_lost_max"])
                   and summ["gradient_collapsed"] <= int(th["gradient_collapsed_max"])) else "fail",
        f"sombra azul {summ['sky_shadow_split']}/{summ['sky_shadow_cases']} "
        f"({summ['sky_shadow_stops_range']} pasos); estampado con sombra {summ['print_shadow_lost']}/"
        f"{summ['print_shadow_cases']}; degradado {summ['gradient_collapsed']}/{summ['gradient_cases']}",
        value=summ["sky_shadow_split"], threshold=int(th["sky_shadow_split_max"])))
    checks.append(Check(
        "prendas: límites conocidos (informativo, ADR-011): bicolor tonal y banda de fusión",
        "info",
        f"bicolor tonal (un tinte y su propia sombra) conservado {summ['tonal_kept']}/{summ['tonal_cases']} "
        f"(ΔE00 reales {summ['tonal_pair_de00']}); banda de fusión a región 3 {summ['band_fused']}/"
        f"{summ['band_cases']} por ΔE00 real " + ", ".join(f"{k}: {v[0]}/{v[1]}" for k, v in summ["band_curve"].items()),
        value=summ["tonal_kept"]))
    checks.append(Check(
        f"prendas: vestidos sin fusionar en región 3 <= {th['missed_fusion_rate_max']}",
        "pass" if summ["missed_fusion_rate"] <= float(th["missed_fusion_rate_max"]) else "fail",
        f"{summ['missed_fusions']}/{summ['by_kind'].get('vestido', {}).get('n', 0)}",
        value=summ["missed_fusion_rate"], threshold=float(th["missed_fusion_rate_max"])))
    if defaulted:
        checks.append(Check("umbrales L2.garments con valores por defecto (propuestos, no promovidos)", "info",
                            ", ".join(f"{k}={th[k]}" for k in defaulted), value=len(defaulted)))
    for c in checks:
        log(f"  [{c.status:>7}] {c.name}" + (f" ({c.seconds:.1f}s)" if c.seconds else ""))
        if c.status == "fail":
            log("           " + c.detail.replace("\n", "\n           "))
    return checks, {"summary": summ, "rows": rows, "thresholds": th, "thresholds_defaulted": defaulted,
                    "seconds": seconds}


# --------------------------------------------------------------------------------------
# Barrido de calibración
# --------------------------------------------------------------------------------------

SWEEP_KL: tuple[float, ...] = (1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0, 8.0)
SWEEP_DE: tuple[float, ...] = (3.0, 4.0, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 10.0, 12.0)
SWEEP_PCT: tuple[tuple[float, float], ...] = ((0.4, 0.9), (0.5, 0.8), (0.5, 0.9), (0.6, 0.9), (0.6, 0.95), (0.7, 0.9),
                                              (0.7, 0.95), (0.75, 0.95), (0.8, 0.98), (0.85, 0.98), (0.9, 1.0),
                                              (0.0, 1.0))
L2_SWEEP_COMPOSITIONS = 200


def l2_compositions(work: Path, n: int = L2_SWEEP_COMPOSITIONS) -> list[tuple[Path, list[dict[str, Any]]]]:
    """Las composiciones planas de la capa 2 (semillas 1..n, mitad por layout) como PPM."""
    from oracle.l2 import layout_for_seed

    out = []
    for seed in range(1, n + 1):
        img, truth = sc.compose(seed, layout=layout_for_seed(seed))
        out.append((sc.write_ppm(img, work / f"l2comp_{seed}.ppm"), truth))
    return out


def evaluate_l2(cli: Path, comps: list[tuple[Path, list[dict[str, Any]]]], garment_opts: dict[str, Any]) -> dict[str, Any]:
    """Camino de prendas sin mapa sobre las composiciones de L2 (--center-sigma 0: peso = área).

    Colores "principales": los ``max_colors_per_region`` de mayor área con área >= secondary_min_share
    (con 40/35/25 el tercero no cabe en 2 colores por región y no cuenta). ``major_recovered``:
    principales con un swatch a ΔE00 < 2; ``wrong_merges``: pares de principales (ΔE00 >= 15 por
    construcción) cuyo swatch más cercano es el mismo (fusión de colores distintos)."""
    opts = dict(ENGINE_DEFAULT_GARMENT_OPTS)
    opts.update(garment_opts)
    results = run_batch_garments(cli, [(p, None, None) for p, _t in comps], garment_opts=garment_opts,
                                 palette_opts={"center_sigma": 0.0})
    major = recovered = merges = 0
    for (_p, truth), r in zip(comps, results):
        gs = r.get("garments", [])
        if not gs:
            continue
        principal = sorted(truth, key=lambda t: -t["area"])[:int(opts["max_colors_per_region"])]
        principal = [t for t in principal if t["area"] >= float(opts["secondary_min_share"])]
        nearest = []
        for t in principal:
            des = [de00(t["lab"], g["lab"]) for g in gs]
            k = int(np.argmin(des))
            nearest.append(k)
            major += 1
            recovered += int(des[k] < 2.0)
        merges += len(nearest) - len(set(nearest))
    return {"n": len(comps), "major_colors": major, "major_recovered": recovered,
            "major_recovered_rate": recovered / major if major else 0.0, "wrong_merges": merges}


def evaluate_unit_images(cli: Path, fixtures_dir: Path, garment_opts: dict[str, Any]) -> dict[str, Any]:
    """Las imágenes de los tests Unity (a) pantalón rosa, (b) rayas y (c) vestido, si existen."""
    reg = fixtures_dir / "garment_regions.pgm"
    out: dict[str, Any] = {}
    for name in ("pants", "stripes", "dress", "print_dress"):
        img = fixtures_dir / f"garment_{name}.ppm"
        if not (img.is_file() and reg.is_file()):
            return {"status": "sin fixtures (make test)"}
        r = run_garments(cli, img, regions=reg, garment_opts=garment_opts)
        counts = {str(k): len(v) for k, v in sorted(colors_by_region(r).items())}
        entry: dict[str, Any] = {"counts": counts}
        if name == "pants":
            low = [g for g in r["garments"] if g["region"] == 2]
            entry["ok"] = counts == {"1": 1, "2": 1}
            entry["lower_de00"] = de00(lab_of(PINK_PANTS["bottom"]), low[0]["lab"]) if low else None
            entry["ok"] = entry["ok"] and entry["lower_de00"] is not None and entry["lower_de00"] < 4.0
        elif name == "stripes":
            entry["ok"] = counts == {"1": 2, "2": 1}
        elif name == "dress":
            entry["ok"] = counts == {"3": 1}
        else:
            des = sorted(min(de00(lab_of(t), g["lab"]) for g in r["garments"]) for t in PRINT_DRESS)
            entry["de"] = des
            entry["ok"] = counts == {"3": 2} and max(des) < 8.0
        out[name] = entry
    out["status"] = "ok"
    return out


def sweep(cli: Path, out_dir: Path, *, n: int = N_CASES, people: bool = True, fixtures_dir: Path | None = None,
          log=print) -> dict[str, Any]:
    """Barrido de calibración de shade_kL x shade_merge_de (y de los percentiles del tono iluminado
    con los valores elegidos) sobre las composiciones sombreadas, las de L2, las imágenes de los
    tests Unity y harness/people. Escribe ``garments_sweep.json`` y ``garments_sweep.md``."""
    cases = build_cases(n)
    fixtures_dir = fixtures_dir or (REPO_ROOT / "build" / "testout")
    grid = []
    with tempfile.TemporaryDirectory(prefix="colorsapp-gsweep-") as tmp:
        work = Path(tmp)
        comps = l2_compositions(work)
        people_list = people_entries(cli, work) if people else []
        proxy = real_pants_proxy()

        def one(opts: dict[str, Any]) -> dict[str, Any]:
            rows, summ = evaluate(cli, cases + [proxy], work, garment_opts=opts)
            proxy_row = rows[-1]
            summ = summarize(rows[:-1], float({**ENGINE_DEFAULT_GARMENT_OPTS, **opts}["shade_merge_de"]))
            _prow, psum = evaluate_people(cli, people_list, garment_opts=opts) if people_list else ([], {"n": 0})
            return {"opts": opts, "synthetic": summ, "real_pants_proxy": {"counts": proxy_row["counts"],
                                                                          "lit_de": proxy_row["lit_de"]},
                    "l2": evaluate_l2(cli, comps, opts), "unit": evaluate_unit_images(cli, fixtures_dir, opts),
                    "people": psum}

        for kL, de in itertools.product(SWEEP_KL, SWEEP_DE):
            e = one({"shade_kL": kL, "shade_merge_de": de})
            grid.append(e)
            sm, l2m, u = e["synthetic"], e["l2"], e["unit"]
            log(f"kL {kL:>4} de {de:>4}: ok {sm['colors_ok']}/{sm['n']} fus {sm['wrong_fusions']} rayas {sm['stripes_merged']} "
                f"| L2 {l2m['major_recovered']}/{l2m['major_colors']} merges {l2m['wrong_merges']} | unit "
                f"{sum(1 for k in ('pants', 'stripes', 'dress', 'print_dress') if (u.get(k) or {}).get('ok'))}/4")
        chosen = {"shade_kL": ENGINE_DEFAULT_GARMENT_OPTS["shade_kL"], "shade_merge_de": ENGINE_DEFAULT_GARMENT_OPTS["shade_merge_de"]}
        pct = []
        for lo, hi in SWEEP_PCT:
            e = one({**chosen, "lit_low_pct": lo, "lit_high_pct": hi})
            pct.append(e)
            log(f"pct {lo}-{hi}: p50 {e['synthetic']['lit_de00_median']:.2f} p90 {e['synthetic']['lit_de00_p90']:.2f} "
                f"máx {e['synthetic']['lit_de00_max']:.2f}")
    detail = {"n": n, "seed": SEED, "chosen": chosen, "grid": grid, "percentiles": pct}
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "garments_sweep.json").write_text(json.dumps(detail, indent=1, ensure_ascii=False, default=float) + "\n",
                                                 encoding="utf-8")
    (out_dir / "garments_sweep.md").write_text(render_sweep(detail), encoding="utf-8")
    return detail


def render_sweep(detail: dict[str, Any]) -> str:
    def row(e: dict[str, Any], label: str) -> str:
        sm, l2m, u, pp = e["synthetic"], e["l2"], e["unit"], e["people"]
        bk = sm["by_kind"]
        unit = "—" if u.get("status") != "ok" else "".join("✓" if u[k]["ok"] else "✗" for k in ("pants", "stripes", "dress", "print_dress"))
        return (f"| {label} | {sm['colors_ok']}/{sm['n']} | " + " | ".join(f"{bk[k]['colors_ok']}/{bk[k]['n']}" for k in KINDS)
                + f" | {sm['wrong_fusions']} | {sm['stripes_merged']} | {sm['close_pairs_over_threshold']} | "
                f"{sm['lit_de00_median']:.2f} / {sm['lit_de00_p90']:.2f} | {l2m['major_recovered']}/{l2m['major_colors']} | "
                f"{l2m['wrong_merges']} | {unit} | " + (f"{pp.get('mean_swatches', 0):.2f} / {pp.get('garment_de00_median', 0):.2f}"
                                                        if pp.get("n") else "—") + " |")

    head = ("| config | colores exactos | " + " | ".join(KINDS) + " | fusiones erróneas | rayas fundidas | pares tono cercano "
            "> umbral | ΔE00 tono iluminado p50 / p90 | L2 colores principales recuperados | L2 fusiones de colores distintos | "
            "Unity a/b/c/estampado | people swatches / ΔE00 mediana |")
    sep = "|---|" + "---:|" * (len(KINDS) + 9)
    lines = ["# Barrido de la paleta por prenda", "",
             f"{detail['n']} composiciones sombreadas (semilla {detail['seed']}), {L2_SWEEP_COMPOSITIONS} composiciones de L2 "
             "(camino de prendas sin mapa, --center-sigma 0), imágenes de los tests Unity y harness/people (máscara "
             f"{PEOPLE_VARIANT} con regiones de la pose). Elegido: kL {detail['chosen']['shade_kL']}, umbral "
             f"{detail['chosen']['shade_merge_de']}.", "", "## shade_kL × shade_merge_de", "", head, sep]
    for e in detail["grid"]:
        o = e["opts"]
        mark = " **(elegido)**" if o == detail["chosen"] else ""
        lines.append(row(e, f"kL {o['shade_kL']:g}, ΔE {o['shade_merge_de']:g}{mark}"))
    lines += ["", "## Percentiles del tono iluminado (con los valores elegidos)", "", head, sep]
    for e in detail["percentiles"]:
        o = e["opts"]
        lines.append(row(e, f"{o['lit_low_pct']:g}-{o['lit_high_pct']:g}"))
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    from oracle.l2 import find_cli_optional, load_thresholds

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", nargs="?", default="block", choices=("block", "sweep"))
    ap.add_argument("--cli", type=str, default=None)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--n", type=int, default=None)
    ap.add_argument("--no-people", action="store_true")
    args = ap.parse_args(argv)
    cli = find_cli_optional(args.cli)
    if not has_garments(cli):
        print("prendas: el CLI no tiene 'ce garments'")
        return 1
    if args.mode == "sweep":
        sweep(cli, args.out, n=args.n or N_CASES, people=not args.no_people)
        print(f"barrido: {args.out / 'garments_sweep.md'} y .json")
        return 0
    with tempfile.TemporaryDirectory(prefix="colorsapp-garments-") as tmp:
        checks, detail = run_block(cli, load_thresholds(), Path(tmp), n=args.n)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "garments_detail.json").write_text(
        json.dumps(detail, indent=1, ensure_ascii=False, default=float) + "\n", encoding="utf-8")
    failed = [c for c in checks if c.status == "fail"]
    print(f"prendas {'FAIL' if failed else 'OK'}: {len(checks) - len(failed)}/{len(checks)} checks")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
