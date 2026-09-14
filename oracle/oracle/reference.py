"""Oráculo estricto de referencia para la capa 1 del motor de color.

Todas las funciones de este módulo se apoyan en colour-science y replican,
paso a paso y sin atajos, la cadena que implementa el motor en C:

    sRGB8 -> sRGB (0..1) -> lineal (EOTF por tramos IEC 61966-2-1)
          -> XYZ (matriz DERIVADA de primarios + blanco D65 xy(0.3127, 0.3290))
          -> CIELAB (blanco Xn = x/y, Yn = 1, Zn = (1-x-y)/y; eps = 216/24389,
             kappa = 24389/27)

y, aparte, ΔE2000 (Sharma, Wu y Dalal 2005) y la adaptación cromática de
Bradford (inv(CAT) · diag(dst/src) · CAT).

Decisiones importantes:

* La matriz RGB->XYZ es la derivada (``use_derived_matrix_RGB_to_XYZ=True``),
  NO la de cuatro decimales de la norma IEC. Así el blanco (255,255,255)
  mapea exactamente al blanco de referencia y L = 100, a = b = 0.
* No se aplica ninguna adaptación cromática en sRGB -> XYZ (el blanco del
  espacio y el del Lab son el mismo D65), así que se multiplica la matriz
  directamente en lugar de llamar a ``colour.sRGB_to_XYZ`` (que por defecto
  compone una CAT02 identidad-numérica que añade ruido de ~1e-16).
* Ejecutar este módulo como script imprime las constantes (matriz derivada,
  su inversa, blanco de referencia) con ``repr`` (17 dígitos significativos)
  listas para incrustar en C.
"""

from __future__ import annotations

from dataclasses import astuple

import numpy as np
import colour
from colour.adaptation import CAT_BRADFORD, matrix_chromatic_adaptation_VonKries
from colour.algebra import vecmul
from colour.difference import delta_E_CIE2000
from colour.difference.delta_e import intermediate_attributes_CIE2000
from colour.models import RGB_COLOURSPACE_sRGB, XYZ_to_Lab, eotf_sRGB, xy_to_XYZ

# --------------------------------------------------------------------------
# Constantes
# --------------------------------------------------------------------------

#: Blanco de referencia D65 (CIE 015:2004, observador 2°) usado para CIELAB.
D65_XY: np.ndarray = np.array([0.3127, 0.3290])

#: Iluminantes CIE 015:2004 (observador 2°). Mismo orden que ``ce_illuminant``
#: en C. En colour el nombre de F2 es "FL2".
ILLUMINANT_NAMES: tuple[str, ...] = ("A", "D50", "D65", "D75", "F2")
_COLOUR_ILLUMINANT_KEY = {"A": "A", "D50": "D50", "D65": "D65", "D75": "D75", "F2": "FL2"}

#: Valores literales de la especificación; se comprueban contra colour al importar.
ILLUMINANTS_XY: dict[str, tuple[float, float]] = {
    "A": (0.44758, 0.40745),
    "D50": (0.34570, 0.35850),
    "D65": (0.31270, 0.32900),
    "D75": (0.29903, 0.31488),
    "F2": (0.37210, 0.37510),
}


def _check_illuminants() -> None:
    """Verifica que los xy literales coinciden con los de colour (CIE 015:2004)."""
    table = colour.CCS_ILLUMINANTS["CIE 1931 2 Degree Standard Observer"]
    for name, xy in ILLUMINANTS_XY.items():
        ref = table[_COLOUR_ILLUMINANT_KEY[name]]
        if not np.array_equal(np.asarray(ref, dtype=float), np.asarray(xy, dtype=float)):
            raise RuntimeError(f"xy del iluminante {name} difiere de colour: {ref} != {xy}")


_check_illuminants()


def _derived_srgb() -> colour.RGB_Colourspace:
    """Copia de sRGB con las matrices derivadas de primarios + blanco."""
    cs = RGB_COLOURSPACE_sRGB.copy()
    cs.use_derived_transformation_matrices(True)
    return cs


_SRGB_DERIVED = _derived_srgb()

#: Matriz RGB(lineal) -> XYZ derivada de los primarios sRGB y del blanco D65.
MATRIX_RGB_TO_XYZ: np.ndarray = np.array(_SRGB_DERIVED.matrix_RGB_to_XYZ, dtype=float)
#: Inversa (np.linalg.inv) de la anterior.
MATRIX_XYZ_TO_RGB: np.ndarray = np.array(_SRGB_DERIVED.matrix_XYZ_to_RGB, dtype=float)


def illuminant_xyz(name: str) -> np.ndarray:
    """XYZ del blanco de un iluminante (Y = 1), como ``colour.xy_to_XYZ``."""
    return np.asarray(xy_to_XYZ(np.array(ILLUMINANTS_XY[name])), dtype=float)


#: Blanco de referencia D65 en XYZ (Y = 1) tal como lo calcula colour.
WHITE_D65_XYZ: np.ndarray = illuminant_xyz("D65")


# --------------------------------------------------------------------------
# sRGB -> XYZ -> Lab
# --------------------------------------------------------------------------


def srgb_to_linear(rgb) -> np.ndarray:
    """EOTF sRGB por tramos (IEC 61966-2-1) sobre valores codificados 0..1."""
    return np.asarray(eotf_sRGB(np.asarray(rgb, dtype=float)), dtype=float)


def srgb_to_xyz_strict(rgb) -> np.ndarray:
    """sRGB codificado (0..1) -> XYZ (D65) con la matriz derivada, sin CAT."""
    lin = srgb_to_linear(rgb)
    return np.asarray(vecmul(MATRIX_RGB_TO_XYZ, lin), dtype=float)


def xyz_to_lab(xyz) -> np.ndarray:
    """XYZ -> CIELAB con blanco D65 xy(0.3127, 0.3290)."""
    return np.asarray(XYZ_to_Lab(np.asarray(xyz, dtype=float), D65_XY), dtype=float)


def srgb_to_lab_strict(rgb) -> np.ndarray:
    """sRGB codificado (0..1) -> CIELAB (D65)."""
    return xyz_to_lab(srgb_to_xyz_strict(rgb))


def srgb8_to_lab_strict(rgb8) -> np.ndarray:
    """sRGB de 8 bits (enteros 0..255, un triple o un array (..., 3)) -> CIELAB.

    La normalización es ``v / 255`` en double, exactamente como en el motor C.
    """
    rgb = np.asarray(rgb8, dtype=float) / 255.0
    return srgb_to_lab_strict(rgb)


# --------------------------------------------------------------------------
# Diferencias de color
# --------------------------------------------------------------------------


def de76(lab1, lab2) -> np.ndarray:
    """ΔE*ab (CIE 1976): distancia euclídea en Lab."""
    d = np.asarray(lab1, dtype=float) - np.asarray(lab2, dtype=float)
    return np.sqrt(np.sum(d * d, axis=-1))


def de2000(lab1, lab2, kL: float = 1.0, kC: float = 1.0, kH: float = 1.0) -> np.ndarray:
    """ΔE00 (Sharma, Wu y Dalal 2005) con factores paramétricos opcionales.

    Con kL = kC = kH = 1 delega en ``colour.difference.delta_E_CIE2000``; con
    otros factores usa los atributos intermedios de colour (mismos S_L, S_C,
    S_H, R_T) y aplica la fórmula final con los k dados.
    """
    lab1 = np.asarray(lab1, dtype=float)
    lab2 = np.asarray(lab2, dtype=float)
    if kL == 1.0 and kC == 1.0 and kH == 1.0:
        return np.asarray(delta_E_CIE2000(lab1, lab2), dtype=float)
    S_L, S_C, S_H, dLp, dCp, dHp, R_T = astuple(intermediate_attributes_CIE2000(lab1, lab2))
    tL = dLp / (kL * S_L)
    tC = dCp / (kC * S_C)
    tH = dHp / (kH * S_H)
    return np.asarray(np.sqrt(tL * tL + tC * tC + tH * tH + R_T * tC * tH), dtype=float)


# --------------------------------------------------------------------------
# Adaptación cromática (Bradford)
# --------------------------------------------------------------------------


def bradford_matrix(src: str, dst: str) -> np.ndarray:
    """Matriz 3x3 de adaptación de Bradford del iluminante ``src`` al ``dst``.

    Es ``inv(CAT_BRADFORD) · diag(RGB_dst / RGB_src) · CAT_BRADFORD`` tal como la
    calcula ``colour.adaptation.matrix_chromatic_adaptation_VonKries``.
    """
    return np.asarray(
        matrix_chromatic_adaptation_VonKries(
            illuminant_xyz(src), illuminant_xyz(dst), transform="Bradford"
        ),
        dtype=float,
    )


def xyz_adapt(xyz, src: str, dst: str) -> np.ndarray:
    """Aplica la matriz de Bradford ``src -> dst`` a XYZ (un triple o (..., 3))."""
    return np.asarray(vecmul(bradford_matrix(src, dst), np.asarray(xyz, dtype=float)), dtype=float)


# --------------------------------------------------------------------------
# Constantes para C
# --------------------------------------------------------------------------


def _c_matrix(name: str, m: np.ndarray) -> str:
    rows = ",\n".join("    " + ", ".join(repr(float(v)) for v in row) for row in np.asarray(m))
    return f"static const double {name}[9] = {{\n{rows}\n}};"


def c_constants() -> str:
    """Texto con las constantes (repr, 17 dígitos) para pegar en ce_math.c."""
    parts = [
        f"/* colour-science {colour.__version__}, numpy {np.__version__} */",
        _c_matrix("CE_M_RGB_TO_XYZ", MATRIX_RGB_TO_XYZ),
        _c_matrix("CE_M_XYZ_TO_RGB", MATRIX_XYZ_TO_RGB),
        "/* blanco D65 (Y = 1) calculado por colour.xy_to_XYZ */",
        "static const double CE_WHITE_D65[3] = {"
        + ", ".join(repr(float(v)) for v in WHITE_D65_XYZ)
        + "};",
        _c_matrix("CE_CAT_BRADFORD", CAT_BRADFORD),
        _c_matrix("CE_CAT_BRADFORD_INV_NUMPY", np.linalg.inv(CAT_BRADFORD)),
    ]
    return "\n".join(parts)


if __name__ == "__main__":
    print(c_constants())
