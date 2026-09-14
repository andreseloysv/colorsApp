"""Valida al validador: el oráculo pasa los 34 pares de Sharma, Wu y Dalal.

También comprueba los anclajes básicos (blanco -> L = 100, negro -> 0) y que
la matriz de Bradford D65 -> D50 coincide con el ejemplo documentado de
colour-science.
"""

from pathlib import Path

import numpy as np
import pytest

from oracle import reference as ref

REPO_ROOT = Path(__file__).resolve().parents[2]
SHARMA_FILE = REPO_ROOT / "engine" / "tests" / "data" / "ciede2000testdata.txt"


def load_sharma() -> np.ndarray:
    rows = []
    for line in SHARMA_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        rows.append([float(v) for v in line.split()])
    data = np.array(rows, dtype=float)
    assert data.shape == (34, 7), f"esperaba 34x7, tengo {data.shape}"
    return data


@pytest.fixture(scope="module")
def sharma() -> np.ndarray:
    return load_sharma()


def test_sharma_34_pairs(sharma: np.ndarray) -> None:
    lab1, lab2, expected = sharma[:, 0:3], sharma[:, 3:6], sharma[:, 6]
    got = ref.de2000(lab1, lab2)
    np.testing.assert_allclose(got, expected, rtol=0.0, atol=1e-4)


def test_sharma_symmetry(sharma: np.ndarray) -> None:
    lab1, lab2, expected = sharma[:, 0:3], sharma[:, 3:6], sharma[:, 6]
    got = ref.de2000(lab2, lab1)
    np.testing.assert_allclose(got, expected, rtol=0.0, atol=1e-4)


def test_sharma_pairwise_scalar(sharma: np.ndarray) -> None:
    """Cada par por separado (rutas escalares, no solo vectorizadas)."""
    for row in sharma:
        d = float(ref.de2000(row[0:3], row[3:6]))
        assert abs(d - row[6]) <= 1e-4, row


def test_de2000_k_matches_default(sharma: np.ndarray) -> None:
    lab1, lab2 = sharma[:, 0:3], sharma[:, 3:6]
    np.testing.assert_allclose(ref.de2000(lab1, lab2, 1.0, 1.0, 1.0), ref.de2000(lab1, lab2), atol=0.0)
    # kL = 2 debe coincidir con el modo "textiles" de colour.
    from colour.difference import delta_E_CIE2000

    np.testing.assert_allclose(
        ref.de2000(lab1, lab2, kL=2.0), delta_E_CIE2000(lab1, lab2, textiles=True), atol=1e-12
    )


def test_white_and_black() -> None:
    white = ref.srgb8_to_lab_strict([255, 255, 255])
    assert abs(white[0] - 100.0) <= 1e-9
    assert abs(white[1]) <= 1e-9 and abs(white[2]) <= 1e-9
    black = ref.srgb8_to_lab_strict([0, 0, 0])
    np.testing.assert_allclose(black, [0.0, 0.0, 0.0], atol=1e-12)


def test_matrix_rows_sum_to_white() -> None:
    np.testing.assert_allclose(ref.MATRIX_RGB_TO_XYZ.sum(axis=1), ref.WHITE_D65_XYZ, atol=1e-15)
    np.testing.assert_allclose(ref.MATRIX_RGB_TO_XYZ @ ref.MATRIX_XYZ_TO_RGB, np.eye(3), atol=1e-15)


def test_bradford_d65_to_d50_matches_colour_example() -> None:
    expected = np.array(
        [
            [1.0479297, 0.0229468, -0.0501922],
            [0.0296278, 0.9904344, -0.0170738],
            [-0.0092430, 0.0150551, 0.7518742],
        ]
    )
    np.testing.assert_allclose(ref.bradford_matrix("D65", "D50"), expected, atol=1e-7)


def test_bradford_identity() -> None:
    np.testing.assert_allclose(ref.bradford_matrix("D65", "D65"), np.eye(3), atol=1e-14)
